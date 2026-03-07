# EyeD User Guide

## What is EyeD?

EyeD is an iris biometric recognition system. It captures images of a person's eye, extracts a unique iris code, and matches it against enrolled identities. Think of it like a fingerprint scanner, but using the iris pattern instead.

## System Overview

```
Camera (RPi) ──► Server (Docker) ──► Browser (Dashboard)
  captures          analyzes            displays
  eye images        iris patterns       results
```

**Current status**: The iris analysis engine is operational. Camera capture, gateway, and web dashboard are planned for future phases.

## Getting Started

### 1. Set up database credentials

Database credentials are managed via Docker secrets in the `secrets/` directory (git-ignored). On a fresh clone, create the files:

```bash
mkdir -p secrets
echo "eyed"     > secrets/db_user.txt
echo "eyed"     > secrets/db_name.txt
echo "eyed_dev" > secrets/db_password.txt
```

These files are read at container startup by both PostgreSQL and iris-engine. Never commit them to version control.

### 2. Start the system

```bash
docker compose up
```

### 3. Verify it's running

```bash
curl http://localhost:9500/health/ready
```

You should see:
```json
{
  "alive": true,
  "ready": true,
  "pipeline_loaded": true,
  "nats_connected": true,
  "gallery_size": 0,
  "he_active": true,
  "version": "0.2.0"
}
```

**Important:** `he_active` MUST be `true` in any deployment handling real biometric data. If it is `false`, the service is running in plaintext mode — see [Encryption Policy](#encryption-policy) below.

### 4. Interactive API docs

Open http://localhost:7000/docs in your browser for the Swagger UI where you can test all endpoints interactively.

## Core Concepts

### Iris Recognition Pipeline

When an eye image is submitted, it goes through these stages:

1. **Segmentation** — A neural network (MobileNetV2 + UNet++) identifies the iris, pupil, sclera, and eyelashes in the image
2. **Normalization** — The circular iris region is "unwrapped" into a rectangular strip (Daugman rubber sheet model)
3. **Encoding** — 2D Gabor filters extract the iris texture pattern into a binary code (>10,000 bits)
4. **Matching** — The iris code is compared against enrolled templates using fractional Hamming distance

### Matching Score

- **Hamming distance** ranges from 0.0 (identical) to 0.5 (completely different)
- **Match threshold**: 0.39 — below this means the iris belongs to the same person
- **Dedup threshold**: 0.32 — stricter check used during enrollment to prevent duplicate identities

### Gallery

The gallery is the collection of enrolled iris templates. When a new eye image is analyzed, it's compared against all templates in the gallery to find a match.

**Note**: In Phase 1, the gallery is stored in memory and resets when the service restarts. Persistent storage (PostgreSQL) is planned for Phase 5.

## Usage

### Analyzing an Eye Image

Upload a JPEG image of an eye:

```bash
curl -X POST http://localhost:7000/analyze \
  -F "file=@eye_image.jpg" \
  -F "eye_side=left"
```

Response:
```json
{
  "frame_id": "http-a1b2c3d4",
  "device_id": "local",
  "match": {
    "hamming_distance": 0.28,
    "is_match": true,
    "matched_identity_id": "person-001"
  },
  "latency_ms": 95.2
}
```

### Enrolling a New Identity

To register a person in the system:

```bash
curl -X POST http://localhost:7000/enroll \
  -H "Content-Type: application/json" \
  -d '{
    "identity_id": "person-001",
    "identity_name": "Jane Smith",
    "jpeg_b64": "<base64-encoded-jpeg>",
    "eye_side": "left"
  }'
```

The system will:
1. Run the iris pipeline on the image
2. Check for duplicates (is this iris already enrolled?)
3. If unique, add the template to the gallery

### Checking Gallery Size

```bash
curl http://localhost:7000/gallery/size
```

## Image Requirements

For best results, eye images should be:
- **Format**: JPEG
- **Type**: Near-infrared (NIR) preferred, visible light accepted
- **Content**: Close-up of a single eye with iris clearly visible
- **Quality**: In focus, well-lit, minimal occlusion from eyelids/eyelashes
- **Minimum visible iris**: At least 30% of iris must be unoccluded

## Changing Database Credentials

To change the database password (or user/name):

1. Stop all services:
   ```bash
   docker compose down
   ```

2. Edit the secret file(s):
   ```bash
   echo "new_password" > secrets/db_password.txt
   ```

3. Delete the existing database volume (required — PostgreSQL only reads credentials on first init):
   ```bash
   docker volume rm eyed_pgdata
   ```

4. Restart:
   ```bash
   docker compose up
   ```

PostgreSQL will re-initialize with the new credentials, and iris-engine will read them from the secret files automatically.

**Note:** Deleting the volume erases all enrolled data. To change credentials without data loss, connect to the running database and use `ALTER USER` / `ALTER DATABASE` instead, then update the secret files to match.

## Encryption Policy

### Principle: Encryption is mandatory

EyeD handles iris biometric data — among the most sensitive categories of personal data. Encryption of biometric templates is **mandatory** in all environments, including development.

### How encryption works

Iris templates are encrypted using **homomorphic encryption** (OpenFHE BFV scheme, 128-bit security). This means:

- Templates are encrypted before storage in PostgreSQL
- Matching can be performed on encrypted data (no decryption needed for comparison)
- Only the key-service holds the secret key — iris-engine never has access to it

### Auto-detection (tamper-proof)

Encryption is **not** controlled by an environment variable. It is auto-detected from key files:

1. The **key-service** generates BFV keys on first boot into a shared Docker volume (`/keys`)
2. The **iris-engine** checks for 4 required key files at startup (`cryptocontext.bin`, `public.key`, `eval_mult.key`, `eval_rotate.key`)
3. If keys are present → encryption is active. **No env var can override this.**
4. If keys are absent → the service **refuses to start** (fail-closed)

### Development without encryption (requires justification)

In rare cases where a developer needs to run iris-engine without key-service (e.g., debugging the segmentation pipeline), plaintext mode can be enabled:

```bash
export EYED_ALLOW_PLAINTEXT=true
```

Even in plaintext mode, the following safeguards are enforced:

| Safeguard | Description |
|-----------|-------------|
| **No raw biometric data in HTTP responses** | `iris_template_b64` is stripped from all API responses |
| **No biometric data over unauthenticated NATS** | Archive messages omit templates in plaintext mode |
| **CRITICAL log warnings** | Every startup in plaintext mode logs at CRITICAL level |
| **Health endpoint reports `he_active: false`** | Operators can detect plaintext mode via monitoring |

### What is NOT encrypted (known gaps)

| Data | Status | Notes |
|------|--------|-------|
| Raw JPEG images in transit | Unencrypted | Phase 6: TLS/mTLS |
| Database connections | No SSL | Phase 6: `sslmode=verify-full` |
| NATS messages | No auth/TLS | Phase 6: TLS + JWT |
| `iris_popcount` / `mask_popcount` in DB | Plaintext integers | Partial biometric info (bit counts per scale) |
| Rendered iris code PNG images | Visual only | Returned to client for UI display — not raw biometric data |

### Verifying encryption is active

```bash
# Check health endpoint
curl http://localhost:9500/health/ready | jq '.he_active'
# Expected: true

# Check DB — enrolled templates should have HEv1 prefix
docker compose exec postgres psql -U eyed -d eyed -c \
  "SELECT encode(substring(iris_codes for 4), 'escape') FROM templates LIMIT 1;"
# Expected: HEv1
```

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `FATAL: HE key files not found` | key-service has not generated encryption keys | Ensure key-service is running and has started before iris-engine. Check `docker compose logs key-service`. |
| `Failed to decode JPEG image` | File is not a valid JPEG | Ensure the file is an actual JPEG image |
| `VectorizationError: Number of contours must be equal to 1` | Segmentation found no clear iris/pupil boundary | Use a better quality image with clearer iris |
| `OcclusionError: visible_fraction < min_allowed_occlusion` | Too much of the iris is hidden by eyelids/eyelashes | Use an image with the eye more open |
| `Pipeline produced no template` | Segmentation failed entirely | Image may not contain a recognizable eye |

## Planned Features

- **Live camera feed**: Raspberry Pi capture devices streaming via WebRTC
- **Web dashboard**: Browser-based UI for monitoring, enrollment, and match results
- **Persistent storage**: PostgreSQL for templates, SeaweedFS for image archives
- **Multi-device support**: Multiple capture devices with automatic load balancing
- **Security**: mTLS, encrypted templates, audit logging
