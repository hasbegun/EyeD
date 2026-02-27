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

### 1. Start the system

```bash
docker compose up
```

### 2. Verify it's running

```bash
curl http://localhost:7000/health/ready
```

You should see:
```json
{
  "alive": true,
  "ready": true,
  "pipeline_loaded": true,
  "nats_connected": true,
  "gallery_size": 0,
  "version": "0.1.0"
}
```

### 3. Interactive API docs

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

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
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
