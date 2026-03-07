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
- **iris-engine API**: http://localhost:9500
- **Swagger UI**: http://localhost:9500/docs
- **NATS monitoring**: http://localhost:9501
- **NATS client**: localhost:9502
- **PostgreSQL**: localhost:9506
- **Redis**: localhost:9508

## Project Structure

```
eyed/
├── iris-engine/              # Iris recognition service (Python, wraps Open-IRIS)
│   ├── Dockerfile            # Multi-target: cpu / cuda
│   ├── requirements.txt      # open-iris, nats-py, fastapi, uvicorn, asyncpg, redis
│   ├── src/
│   │   ├── main.py           # FastAPI app + lifespan (pipeline, pool, Redis, NATS, DB)
│   │   ├── config.py         # Settings from environment variables (EYED_ prefix)
│   │   ├── pipeline.py       # Open-IRIS wrapper: analyze(), create_pipeline()
│   │   ├── pipeline_pool.py  # Pre-loaded pipeline pool for parallel batch work
│   │   ├── matcher.py        # Hamming distance matcher + in-memory gallery
│   │   ├── redis_cache.py    # Redis write-through cache for enrollment persistence
│   │   ├── db_drain.py       # Background Redis → Postgres batch drain writer
│   │   ├── db.py             # PostgreSQL connection pool + template persistence
│   │   ├── core.py           # Shared enrollment logic (single + batch)
│   │   ├── health.py         # Health check logic (pipeline, NATS, Redis, pool)
│   │   ├── nats_service.py   # NATS messaging (analyze, enroll, gallery sync)
│   │   ├── models.py         # Request/response models (Pydantic v1)
│   │   └── routes/
│   │       ├── health.py     # /health/alive, /health/ready
│   │       ├── analyze.py    # /analyze (single image analysis)
│   │       ├── enroll.py     # /enroll + /enroll/batch (pipeline pool + SSE)
│   │       ├── gallery.py    # /gallery (list, detail, delete templates)
│   │       └── datasets.py   # /datasets (list, browse, images)
│   └── tests/
│       ├── test_pipeline.py      # Unit tests + health endpoints
│       ├── test_benchmark.py     # Per-frame latency benchmark
│       ├── test_fnmr.py          # FNMR accuracy (CASIA1)
│       └── test_fnmr_mmu2.py    # FNMR accuracy (MMU2)
│
├── key-service/              # HE decryption service (C++, OpenFHE)
│   ├── Dockerfile            # Multi-stage: builds OpenFHE v1.4.2 from source
│   ├── CMakeLists.txt        # C++17, fetches nats.c + nlohmann/json via FetchContent
│   └── src/
│       ├── main.cpp          # Entry point (~30 lines)
│       ├── nats_service.h/cpp # NATS connection, subscriptions, signal handling
│       ├── he_context.h/cpp  # OpenFHE BFV context: key gen/load, decrypt
│       └── handlers.h/cpp    # NATS message handlers (decrypt_batch, decrypt_template, health)
│
├── client/                   # Flutter desktop app (Mac/Linux/Windows)
│
├── proto/                    # gRPC protocol definitions (Phase 2+)
│   └── capture.proto         # Capture device <-> gateway contract
│
├── config/
│   ├── nats-server.conf      # NATS message broker config
│   └── init.sql              # PostgreSQL schema initialization
│
├── docker-compose.yml        # Production-like stack (CPU)
├── docker-compose.dev.yml    # Dev overrides (hot reload, volume mounts)
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
                         ┌───────────────┐
┌──────────┐             │ iris-engine   │
│   NATS   │◄───────────►│  (Open-IRIS)  │
│  broker  │             │               │         ┌──────────────┐
│          │             │ Pipeline Pool │────────►│  PostgreSQL  │
│          │             │ (3 instances) │         │  (templates) │
│          │             └──────┬────────┘         └──────────────┘
│          │                    │    │
│          │               HTTP :9500│
│          │               /analyze  │
│          │               /enroll   │
│          │               /health/* │
│          │                         │             ┌──────────────┐
│          │                         └────────────►│    Redis     │
│          │                                       │ (write cache)│
│          │                                       └──────────────┘
│          │             ┌──────────────┐
│          │◄───────────►│ key-service  │
└──────────┘             │  (OpenFHE)   │
                         │ BFV decrypt  │
                         └──────────────┘
                           No HTTP port
                           NATS-only
```

- **iris-engine**: Python service wrapping [Open-IRIS 1.11.0](https://github.com/worldcoin/open-iris) (Worldcoin, MIT license). Handles segmentation (with image denoising), normalization, Gabor encoding, and Hamming distance matching. Supports image_id tracing through the pipeline. Pipeline pool (3 pre-loaded instances) enables parallel batch enrollment.
- **key-service**: C++ service holding the BFV secret key. Decrypts HE ciphertexts for iris-engine via NATS request-reply. Generates keypairs on first boot into a shared Docker volume (`/keys`). No HTTP port — communicates exclusively over NATS.
- **NATS**: Lightweight message broker for inter-service communication. Used for analyze/enroll messages, gallery sync between nodes, and HE decryption requests to key-service.
- **PostgreSQL**: Persistent storage for enrolled identities, iris templates (HE-encrypted BYTEA), and match audit logs.
- **Redis**: Write-through cache for bulk enrollment. Workers push to a Redis LIST (sub-ms), a background drain writer batches inserts to Postgres asynchronously.

### Planned (Phase 2+)

See `MODERN_ARCHITECTURE.md` for the full architecture including gateway (C++/Go), capture device (C++), web-ui (TypeScript), storage, and template-db.

## iris-engine API

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health/alive` | Liveness probe |
| `GET` | `/health/ready` | Readiness probe (pipeline, NATS, Redis, pool status) |
| `POST` | `/analyze` | Analyze eye image (multipart file upload) |
| `POST` | `/analyze/json` | Analyze eye image (JSON with base64 JPEG) |
| `POST` | `/analyze/detailed` | Analyze with intermediate visualizations |
| `POST` | `/enroll` | Enroll identity with eye image |
| `POST` | `/enroll/batch` | Bulk-enroll from dataset (SSE stream) |
| `GET` | `/gallery/size` | Number of enrolled templates |
| `GET` | `/gallery/list` | List all enrolled identities |
| `GET` | `/gallery/template/{id}` | Template detail with iris code visualization |
| `DELETE` | `/gallery/{identity_id}` | Remove identity from gallery |
| `GET` | `/datasets` | List available datasets |
| `GET` | `/datasets/{name}/subjects` | List subjects in a dataset |
| `GET` | `/datasets/{name}/images` | List images for a subject |

### Analyze (file upload)

```bash
curl -X POST http://localhost:9500/analyze \
  -F "file=@eye_image.jpg" \
  -F "eye_side=left"
```

### Analyze (JSON)

```bash
curl -X POST http://localhost:9500/analyze/json \
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
curl -X POST http://localhost:9500/enroll \
  -H "Content-Type: application/json" \
  -d '{
    "identity_id": "person-001",
    "identity_name": "John Doe",
    "jpeg_b64": "<base64-encoded-jpeg>",
    "eye_side": "left"
  }'
```

### Bulk Enroll (SSE stream)

```bash
curl -N -X POST http://localhost:9500/enroll/batch \
  -H "Content-Type: application/json" \
  -d '{"dataset": "CASIA-Iris-Thousand"}'
```

Each enrolled image emits an SSE `data:` event with per-image result. The stream ends with an `event: done` summary.

### Health Check

```bash
curl http://localhost:9500/health/ready | python3 -m json.tool
```

Response includes `pipeline_loaded`, `nats_connected`, `db_connected`, `redis_connected`, `pipeline_pool_size`, `pipeline_pool_available`, and `gallery_size`.

### NATS Interface

The iris-engine also listens on NATS subjects for production use:
- `eyed.analyze` — submit frames for analysis
- `eyed.enroll` — submit frames for enrollment
- Results published to `eyed.result`

## key-service

The key-service is a C++ microservice that holds the BFV homomorphic encryption secret key. It is the only component in the system that can decrypt ciphertexts — iris-engine encrypts templates using the public key but never has access to the secret key.

### Responsibilities

1. **Key generation** — On first boot, generates a BFV keypair (secret, public, eval-mult, eval-rotate) and writes them to the shared `/keys` volume. Subsequent boots load existing keys.
2. **Batch decryption** — Decrypts encrypted inner-product ciphertexts, computes Hamming distances, and returns match results to iris-engine.
3. **Template decryption** — Decrypts full iris/mask code ciphertexts for admin visualization (gallery detail view).
4. **Health reporting** — Reports readiness and ring dimension.

### NATS Subjects

| Subject | Direction | Description |
|---------|-----------|-------------|
| `eyed.key.decrypt_batch` | request-reply | Decrypt batch of inner products, compute HD, return best match |
| `eyed.key.decrypt_template` | request-reply | Decrypt full template for admin visualization |
| `eyed.key.health` | request-reply | Health check (`{"status":"ok","ring_dimension":8192}`) |

The key-service has **no HTTP port**. All communication is via NATS request-reply.

### BFV Parameters

These must match `iris-engine/src/he_context.py`:

| Parameter | Value |
|-----------|-------|
| Plaintext modulus (t) | 65537 |
| Multiplicative depth | 1 |
| Security level | 128-bit (`HEStd_128_classic`) |
| Iris code slots | 8192 (16 scales × 256 angles × 2 codes) |
| Ring dimension | Auto (typically 8192 or 16384) |

### Module Structure

| File | Purpose |
|------|---------|
| `main.cpp` | Entry point (~30 lines): load config, init HE, connect NATS, wait |
| `nats_service.h/cpp` | Config from env vars, NATS connection with retry, subscription management, signal handling |
| `he_context.h/cpp` | OpenFHE BFV context: key generation/loading, `DecryptScalar()`, `DecryptToVector()` |
| `handlers.h/cpp` | NATS message handlers for decrypt_batch, decrypt_template, health |

### C++ Dependencies

| Library | Version | Source |
|---------|---------|--------|
| OpenFHE | v1.4.2 | Built from source in Dockerfile |
| nats.c | v3.8.2 | CMake FetchContent |
| nlohmann/json | v3.11.3 | CMake FetchContent |

### Building

The key-service builds entirely inside Docker (multi-stage). No local C++ toolchain is needed:

```bash
# Build only key-service
docker compose build key-service

# View logs
docker compose logs -f key-service
```

The Dockerfile builds OpenFHE from source (~5 min first build), then compiles the key-service against it. The runtime image copies only the binary and shared libraries (~60 MB).

## Configuration

All settings are controlled via environment variables with `EYED_` prefix:

| Variable | Default | Description |
|----------|---------|-------------|
| `EYED_RUNTIME` | `cpu` | ONNX execution provider: `cpu`, `cuda`, `coreml` |
| `EYED_NATS_URL` | `nats://nats:4222` | NATS server address |
| `EYED_DB_URL` | `""` | PostgreSQL connection URL (empty = in-memory only) |
| `EYED_REDIS_URL` | `""` | Redis connection URL (empty = direct DB writes) |
| `EYED_MATCH_THRESHOLD` | `0.39` | Hamming distance threshold for matching |
| `EYED_DEDUP_THRESHOLD` | `0.32` | Stricter threshold for enrollment dedup |
| `EYED_ROTATION_SHIFT` | `15` | Max rotation shifts for matching |
| `EYED_PIPELINE_POOL_SIZE` | `3` | Pre-loaded pipeline instances for parallel batch work |
| `EYED_BATCH_WORKERS` | `3` | Thread pool size for bulk enrollment (should match pool size) |
| `EYED_BATCH_DB_SIZE` | `50` | Batch INSERT size for Redis → Postgres drain |
| `EYED_BATCH_DB_INTERVAL` | `1.0` | Seconds between drain flushes |
| `EYED_HE_KEY_DIR` | `/keys` | Directory with HE key files (auto-detected, no toggle) |
| `EYED_ALLOW_PLAINTEXT` | `false` | Dev-only: allow startup without HE keys (NOT for production) |
| `EYED_DATA_ROOT` | `/data/Iris` | Root directory for iris datasets |
| `EYED_LOG_LEVEL` | `info` | Log level |

## Dependencies

### iris-engine Python Dependencies

```
open-iris>=1.11,<2       # Core iris recognition pipeline
nats-py>=2.6             # NATS messaging client
fastapi>=0.100,<0.110    # HTTP API framework
uvicorn[standard]>=0.24  # ASGI server
python-multipart>=0.0.6  # File upload support
asyncpg>=0.29            # PostgreSQL async driver
redis[hiredis]>=5.0,<6   # Redis client (with C extension for speed)
# openfhe (built from source in Dockerfile, not a pip dependency)
```

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
# Run tests (uses dev compose for volume-mounted tests/)
docker compose -f docker-compose.yml -f docker-compose.dev.yml run --rm --no-deps iris-engine \
  sh -c "pip install --quiet pytest 'httpx>=0.27,<0.28' && python3 -m pytest tests/ -v"

# Or via Makefile
make test
```

Tests include unit tests, health endpoint tests, per-frame latency benchmarks, and FNMR accuracy tests against CASIA1 and MMU2 datasets.

## Language Choices

| Service | Language | Rationale |
|---------|----------|-----------|
| iris-engine | Python 3.10 | Open-IRIS 1.11.0 is Python-native; requires 3.10 (numpy pin incompatible with 3.12+) |
| key-service | C++17 | Holds BFV secret key; OpenFHE is C++ native |
| gateway | C++ (planned) | Performance-critical I/O routing |
| capture | C++ (planned) | Embedded device, V4L2/gRPC, real-time |
| storage | C++ (planned) | Performance preference |
| web-ui | TypeScript (planned) | Browser SPA |

Python is used **only** for iris-engine because the core algorithm library (Open-IRIS) requires it. All other services are C++.
