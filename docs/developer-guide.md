# EyeD Developer Guide

## Prerequisites

- Docker Desktop (Mac, Linux, or Windows with WSL2)
- Git
- curl (for testing)

No local Python, Go, or C++ toolchain needed — everything runs inside Docker containers.

## Quick Start

```bash
# Clone and start
git clone git@github.com:hasbegun/EyeD.git eyed
cd eyed

# Start the stack (CPU-only, works on any machine)
docker compose up

# Verify
curl http://localhost:7000/health/ready
```

Services will be available at:
- **iris-engine API**: http://localhost:7000
- **Swagger UI**: http://localhost:7000/docs
- **NATS monitoring**: http://localhost:7001
- **NATS client**: localhost:7002

## Project Structure

```
eyed/
├── iris-engine/              # Iris recognition service (Python, wraps Open-IRIS)
│   ├── Dockerfile            # Multi-target: cpu / cuda
│   ├── requirements.txt
│   ├── src/
│   │   ├── main.py           # FastAPI app + NATS subscriber
│   │   ├── pipeline.py       # Open-IRIS wrapper
│   │   ├── matcher.py        # Hamming distance matcher + in-memory gallery
│   │   ├── models.py         # Request/response models (Pydantic v1)
│   │   ├── config.py         # Settings from environment variables
│   │   └── health.py         # Health check logic
│   └── tests/
│
├── proto/                    # gRPC protocol definitions (Phase 2+)
│   └── capture.proto         # Capture device <-> gateway contract
│
├── config/
│   └── nats-server.conf      # NATS message broker config
│
├── docker-compose.yml        # Production-like stack (CPU)
├── docker-compose.dev.yml    # Dev overrides (hot reload)
│
├── legacy/                   # Archived old code (BiometricLib, IrisAnalysis, etc.)
├── MODERN_ARCHITECTURE.md    # Full architecture design document
└── PROJECT_ANALYSIS_REPORT.md
```

## Development Workflow

### Running with hot reload

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

This mounts `./iris-engine/src` into the container and enables uvicorn `--reload`, so code changes take effect immediately without rebuilding.

### Rebuilding after dependency changes

```bash
docker compose build iris-engine
docker compose up
```

### Viewing logs

```bash
docker compose logs -f iris-engine    # Follow iris-engine logs
docker compose logs nats              # NATS broker logs
```

### Stopping

```bash
docker compose down
```

## Architecture

### Current (Phase 1)

```
┌──────────┐       ┌──────────────┐
│   NATS   │◄─────►│ iris-engine  │
│  broker  │       │  (Open-IRIS) │
└──────────┘       └──────┬───────┘
                          │
                     HTTP :7000
                     /analyze
                     /enroll
                     /health/*
```

- **iris-engine**: Python service wrapping [Open-IRIS 1.11.0](https://github.com/worldcoin/open-iris) (Worldcoin, MIT license). Handles segmentation (with image denoising), normalization, Gabor encoding, and Hamming distance matching. Supports image_id tracing through the pipeline.
- **NATS**: Lightweight message broker for inter-service communication. Currently used for analyze/enroll messages; will be the backbone for all services.

### Planned (Phase 2+)

See `MODERN_ARCHITECTURE.md` for the full architecture including gateway (C++/Go), capture device (C++), web-ui (TypeScript), storage, and template-db.

## iris-engine API

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health/alive` | Liveness probe |
| `GET` | `/health/ready` | Readiness probe (pipeline loaded + NATS connected) |
| `POST` | `/analyze` | Analyze eye image (multipart file upload) |
| `POST` | `/analyze/json` | Analyze eye image (JSON with base64 JPEG) |
| `POST` | `/enroll` | Enroll identity with eye image |
| `GET` | `/gallery/size` | Number of enrolled templates |

### Analyze (file upload)

```bash
curl -X POST http://localhost:7000/analyze \
  -F "file=@eye_image.jpg" \
  -F "eye_side=left"
```

### Analyze (JSON)

```bash
curl -X POST http://localhost:7000/analyze/json \
  -H "Content-Type: application/json" \
  -d '{
    "frame_id": "test-001",
    "device_id": "local",
    "jpeg_b64": "<base64-encoded-jpeg>",
    "eye_side": "left"
  }'
```

### Enroll

```bash
curl -X POST http://localhost:7000/enroll \
  -H "Content-Type: application/json" \
  -d '{
    "identity_id": "person-001",
    "identity_name": "John Doe",
    "jpeg_b64": "<base64-encoded-jpeg>",
    "eye_side": "left"
  }'
```

### NATS Interface

The iris-engine also listens on NATS subjects for production use:
- `eyed.analyze` — submit frames for analysis
- `eyed.enroll` — submit frames for enrollment
- Results published to `eyed.result`

## Configuration

All settings are controlled via environment variables with `EYED_` prefix:

| Variable | Default | Description |
|----------|---------|-------------|
| `EYED_RUNTIME` | `cpu` | ONNX execution provider: `cpu`, `cuda`, `coreml` |
| `EYED_NATS_URL` | `nats://nats:4222` | NATS server address |
| `EYED_MATCH_THRESHOLD` | `0.39` | Hamming distance threshold for matching |
| `EYED_DEDUP_THRESHOLD` | `0.32` | Stricter threshold for enrollment dedup |
| `EYED_ROTATION_SHIFT` | `15` | Max rotation shifts for matching |
| `EYED_LOG_LEVEL` | `info` | Log level |

## Dependencies

### Open-IRIS 1.11.0 Pinned Dependencies

Open-IRIS 1.11.0 pins exact versions of its dependencies. Do not override:
- `pydantic==1.10.13` (Pydantic v1, NOT v2)
- `opencv-python==4.7.0.68`
- `onnxruntime==1.16.3`
- `numpy==1.24.4`

Our code uses Pydantic v1 syntax (`.json()` not `.model_dump_json()`, `BaseSettings` from `pydantic` not `pydantic_settings`).

**Python version:** Must use Python 3.10. Open-IRIS's pinned numpy (1.24.4) does not build on Python 3.12+.

### Key Open-IRIS 1.11.0 API

```python
import iris

# Create pipeline (config=None for CPU default)
pipeline = iris.IRISPipeline(config=config)

# Create input image (image_id is optional, for traceability)
ir_image = iris.IRImage(img_data=grayscale_array, eye_side="left", image_id="frame-001")

# Run pipeline — returns dict with "error", "iris_template", "metadata"
result = pipeline(ir_image)
template = result.get("iris_template")  # IrisTemplate or None

# Template has iris_codes (List[np.ndarray]) and mask_codes (List[np.ndarray])
# Match using HammingDistanceMatcher
matcher = iris.HammingDistanceMatcher(rotation_shift=15, normalise=True)
distance = matcher.run(template_probe=probe, template_gallery=gallery)
```

## Testing

```bash
# Run tests inside the container
docker compose exec iris-engine pytest tests/ -v

# Or build a test image
docker compose run --rm iris-engine pytest tests/ -v
```

## Language Choices

| Service | Language | Rationale |
|---------|----------|-----------|
| iris-engine | Python 3.10 | Open-IRIS 1.11.0 is Python-native; requires 3.10 (numpy pin incompatible with 3.12+) |
| gateway | C++ (planned) | Performance-critical I/O routing |
| capture | C++ (planned) | Embedded device, V4L2/gRPC, real-time |
| storage | C++ (planned) | Performance preference |
| web-ui | TypeScript (planned) | Browser SPA |

Python is used **only** for iris-engine because the core algorithm library (Open-IRIS) requires it. All other services will be C++.
