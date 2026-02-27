# EyeD User Guide

## Overview

EyeD is an iris recognition system built on the [Open-IRIS 1.11.0](https://github.com/worldcoin/open-iris) pipeline (Worldcoin, MIT license). It processes iris images in real time, extracts biometric templates, and performs identity matching via Hamming distance comparison. Open-IRIS 1.11.0 includes automatic image denoising, 16-bit ONNX model support, improved ellipse geometry fitting, and image_id tracing through the pipeline.

### Architecture

```
Browser (Web UI :9505)
    |
    |-- WebSocket /ws/results (live analysis)
    |-- WebSocket /ws/signaling (WebRTC video)
    |-- HTTP /health/* (status checks)
    |
Gateway (Go :9503 gRPC, :9504 HTTP)
    |
    |-- NATS (:9502) -- pub/sub messaging
    |
Iris Engine (Python :9500) -- Open-IRIS pipeline
    |                |
    |                |-- PostgreSQL (:9506) -- templates, match log
    |
Capture Device (C++) -- image acquisition
```

### Port Map

| Port | Service | Protocol |
|------|---------|----------|
| 9500 | iris-engine | HTTP (FastAPI) |
| 9501 | NATS monitoring | HTTP |
| 9502 | NATS client | TCP |
| 9503 | gateway gRPC | gRPC (capture devices) |
| 9504 | gateway HTTP | HTTP + WebSocket |
| 9505 | web-ui | HTTP (nginx) |
| 9506 | PostgreSQL | TCP |

---

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Node.js 22+ (for local web-ui development only)
- Iris datasets in `data/Iris/CASIA1/` and `data/Iris/MMU2/`

### Start All Services

```bash
make up        # foreground (see all logs)
make up-d      # detached (background)
```

### Verify Services

```bash
make status    # shows container status, health, readiness, gallery
make health    # liveness check
make ready     # readiness check
```

### Access Web UI

Open http://localhost:9505 in a browser. The UI connects to the gateway automatically.

### Stop Services

```bash
make down      # stop containers
make clean     # stop + remove volumes
make nuke      # remove everything (images, volumes, networks)
```

---

## Web UI

### Dashboard (/)

Real-time view of iris analysis results streaming from the pipeline.

- **Stat Cards**: frames processed, match count, error count
- **Live Feed**: scrolling result rows with device ID, frame number, Hamming distance, match status, and latency
- Color coding: green = match, yellow = no match, red = error

### Devices (/devices)

Auto-discovers capture devices from incoming results.

- **Device Cards**: one per detected device with frame count and last HD
- **Video Feed**: WebRTC live stream from each device (requires WebRTC-capable capture device)
- Status badges: LIVE, CONNECTING, WAITING, OFFLINE

### Enrollment (/enrollment)

Register iris templates for identity enrollment. Templates are persisted in PostgreSQL and survive restarts.

- **Dataset Browser** (left panel): Browse CASIA1/MMU2 datasets, select a subject and image
- **Image Preview**: Shows the selected eye image with auto-detected eye side
- **Enrollment Form**: Enter an identity name, confirm eye side, click "Enroll"
  - A new UUID is generated for each identity
  - The pipeline runs analysis, checks for duplicates (HD < 0.32), and enrolls if unique
  - Duplicate detection prevents enrolling the same iris twice
- **Gallery Table** (bottom): Lists all enrolled identities with their templates
  - Shows identity name, truncated ID, eye side tags
  - Delete button removes an identity and all its templates

### Analysis (/analysis)

Interactive pipeline analysis on dataset images. Use this to test and validate the iris recognition pipeline visually. Select an image, click "Analyze", and inspect every stage of the Open-IRIS pipeline.

#### Dataset Browser (left panel)

- Switch between datasets (CASIA1, MMU2) via tabs
- Browse subjects and select individual images
- Eye side (L/R) auto-detected from filename convention
- Image thumbnails load lazily for performance

#### Analysis Results (right panel)

Appears after clicking "Analyze". Each section corresponds to a stage of the iris recognition pipeline.

**Segmentation**

Shows the original image alongside the segmentation overlay. The overlay draws:
- **Orange contour**: iris boundary (outer edge of the colored part of the eye)
- **Green contour**: pupil boundary (inner dark circle)
- **Cross markers**: estimated centers of pupil (green) and iris (orange)

Good segmentation means both contours tightly follow the actual boundaries. If the contours are misaligned, downstream stages (normalization, encoding) will produce unreliable templates.

**Pipeline Outputs**

- **Normalized Iris (128 x 512)**: The iris region unwrapped from its circular shape into a fixed-size rectangular strip using Daugman's rubber-sheet model. Rows represent radial distance (pupil edge at top, iris edge at bottom). Columns represent angular position (0-360 degrees). This normalization makes the template invariant to pupil dilation and image scale.
- **Iris Code**: Binary feature map extracted from the normalized iris using Gabor wavelet filters. Each pixel is either black (0) or white (1), encoding the phase of the iris texture at that location. This is the biometric template used for matching. Shape is 16 filter responses x 512 angular positions.
- **Noise Mask**: Binary mask showing which regions of the normalized iris are usable (white) vs. occluded by eyelids, eyelashes, or reflections (black). Masked regions are excluded during Hamming distance comparison.

**Quality Metrics**

| Metric | Description | Good Range | Interpretation |
|--------|-------------|------------|----------------|
| **Sharpness** | Laplacian variance of the iris region. Measures image focus. | > 500 | Higher = sharper image. Below ~200 indicates significant blur that degrades recognition accuracy. |
| **Offgaze** | Score indicating how far the eye is looking away from the camera. | < 0.01 | Lower = more centered gaze. High values (> 0.1) mean the subject is not looking at the camera, causing iris distortion. |
| **Occlusion (90)** | Fraction of the iris visible within a 90-degree vertical sector (most affected by eyelids). | > 0.7 | 1.0 = fully visible, 0.0 = fully occluded. Below 0.5 means eyelids cover most of the iris, reducing template reliability. |
| **Occlusion (30)** | Fraction visible within a narrower 30-degree sector. Less sensitive to eyelids. | > 0.9 | Usually higher than Occlusion (90). Low values indicate extreme occlusion. |
| **Pupil/Iris Ratio** | Diameter of the pupil divided by the diameter of the iris. | 0.2 - 0.7 | Indicates pupil dilation. Very small (< 0.2) or very large (> 0.7) ratios compress the iris texture, reducing the amount of usable biometric information. |

**Geometry**

| Field | Description |
|-------|-------------|
| **Pupil Center** | (x, y) pixel coordinates of the estimated pupil center in the original image. |
| **Iris Center** | (x, y) pixel coordinates of the estimated iris center. Usually close to but not identical to the pupil center due to natural asymmetry. |
| **Pupil Radius** | Estimated radius of the pupil in pixels. Typical range: 20-80px depending on dilation and image resolution. |
| **Iris Radius** | Estimated radius of the iris in pixels. Typical range: 70-130px for CASIA1 (320x280). |
| **Eye Orientation** | Rotation angle of the eye in degrees. 0 = perfectly horizontal. Used to compensate for head tilt during normalization. |

**Match Result**

Compares the extracted iris template against all enrolled templates in the gallery using fractional Hamming distance (HD).

| HD Range | Meaning |
|----------|---------|
| **0.0 - 0.32** | Strong match (same eye). The default threshold is 0.39. |
| **0.33 - 0.39** | Weak match. May be the same eye under poor conditions. |
| **0.40 - 0.46** | Inconclusive. Could be same or different eyes. |
| **0.47 - 0.50** | No match (different eyes). Random iris pairs average ~0.46. |

- **Green "Match"**: HD is below the configured threshold (default 0.39), indicating the same identity.
- **Yellow "No match found"**: HD exceeds the threshold for all enrolled templates, or no enrolled templates exist.
- **"Gallery is empty"**: No templates have been enrolled yet. Use the Enrollment view to register identities first.

### History (/history)

Searchable audit log of all analysis results received during the session.

- **Filters**: all, match, no-match, error
- **Search**: filter by device ID, frame ID, or identity ID
- **Columns**: time, device, frame, Hamming distance, status, latency

### Admin (/admin)

Live health monitoring of all services, polling every 5 seconds.

- **Gateway**: alive, ready, NATS connection, circuit breaker state, version
- **Iris Engine**: alive, ready, pipeline loaded, NATS connection, gallery size, version
- **NATS**: connection status, port info

### Connection Status

The sidebar shows a "Live" (green dot) or "Offline" (red dot) indicator for the WebSocket connection to the gateway.

---

## Development

### Local Web UI Development

```bash
cd web-ui
npm install
npm run dev    # Vite dev server on http://localhost:3000
```

The Vite dev server proxies `/ws/*`, `/health/*`, and `/engine/*` to the running Docker services. You need the backend services running (`make up-d`) for the proxies to work.

Or use the Makefile shortcut:
```bash
make dev-webui
```

### Hot Reload (iris-engine)

```bash
make dev       # starts with docker-compose.dev.yml overlay
               # iris-engine reloads on source changes
               # test data mounted at /data
```

### Building Individual Services

```bash
make build-webui      # build web-ui Docker image
make build-gateway    # build gateway Docker image
make build-capture    # build capture-device Docker image
make build            # build all
make rebuild          # build all without cache
```

---

## Testing

### Unit Tests

```bash
make test              # 9 tests: health, analyze, gallery, image decoding
```

### FNMR Accuracy Tests

Validate iris matching accuracy on real datasets. Both tests require the datasets in `data/Iris/`.

```bash
make test-fnmr         # CASIA1 dataset (NIR images, target: FNMR < 0.5%)
make test-fnmr-mmu2    # MMU2 dataset (visible light, target: FNMR < 1.0%)
```

**Expected results (20 subjects each):**

| Dataset | Genuine Pairs | FNMR | Mean HD | Threshold |
|---------|--------------|------|---------|-----------|
| CASIA1 | 172 | 0.00% | 0.136 | < 0.5% |
| MMU2 | 376 | 0.53% | 0.248 | < 1.0% |

MMU2 has slightly higher FNMR because it uses visible-wavelength images (vs. CASIA1's near-infrared).

### Pipeline Benchmark

```bash
make test-bench        # 10 frames, target: median < 800ms (CPU Docker)
```

**Expected results:**
- CPU (Docker): ~600-650ms median per frame
- GPU (CUDA): < 50ms median per frame (requires nvidia runtime)

### Integration Test

End-to-end test: capture device -> gateway -> NATS -> iris-engine -> result.

```bash
make test-integration  # submits a frame via gRPC, verifies result via NATS
```

This test temporarily stops the capture-device to avoid interference.

---

## Webcam Support

For development with a live camera instead of dataset images.

### Linux (direct device passthrough)

```bash
make webcam            # passes /dev/video0 to the container
```

### macOS (MJPEG relay)

Docker Desktop on macOS cannot access USB webcams directly. Use the relay:

```bash
# Terminal 1: start the relay on the host
make webcam-relay      # captures from webcam, serves MJPEG on port 8090

# Terminal 2: start services with macOS webcam config
make webcam-macos      # container reads from http://host.docker.internal:8090/video
```

### Configuration

Webcam settings in `capture/config/capture.toml`:

```toml
[camera]
source = "webcam"                    # switch from "directory" to "webcam"
device = "/dev/video0"               # Linux: device path
# device = "http://host.docker.internal:8090/video"  # macOS: relay URL
width = 640
height = 480
```

Or via environment variables:
```bash
EYED_CAMERA_SOURCE=webcam
EYED_CAMERA_DEVICE=/dev/video0
```

---

## Datasets

### CASIA1

- **Location**: `data/Iris/CASIA1/`
- **Format**: JPEG, 320x280, grayscale NIR
- **Structure**: `{subject_dir}/{id}_{eye}_{num}.jpg` (eye: 1=left, 2=right)
- **Size**: 108 subjects, 7 images per eye

### MMU2

- **Location**: `data/Iris/MMU2/`
- **Format**: BMP, 320x240, grayscale visible light
- **Structure**: `{subject_dir}/{subject}{eye:02d}{image:02d}.bmp` (eye: 01=left, 02=right)
- **Size**: 100 subjects, 5 images per eye

---

## Configuration Reference

### iris-engine

| Variable | Default | Description |
|----------|---------|-------------|
| `EYED_RUNTIME` | `cpu` | `cpu`, `cuda`, or `coreml` |
| `EYED_NATS_URL` | `nats://localhost:4222` | NATS server URL |
| `EYED_LOG_LEVEL` | `info` | Logging level |
| `EYED_MATCH_THRESHOLD` | `0.39` | Hamming distance threshold for match |
| `EYED_ROTATION_SHIFT` | `15` | Template rotation search range |
| `EYED_DB_URL` | _(empty)_ | PostgreSQL connection URL. Empty = in-memory only |

### gateway

| Variable | Default | Description |
|----------|---------|-------------|
| `EYED_NATS_URL` | `nats://localhost:4222` | NATS server URL |
| `EYED_GRPC_PORT` | `50051` | gRPC listen port |
| `EYED_HTTP_PORT` | `8080` | HTTP/WebSocket listen port |
| `EYED_LOG_LEVEL` | `info` | Logging level |

### capture-device

| Variable | Default | Description |
|----------|---------|-------------|
| `EYED_GATEWAY_ADDR` | `localhost:50051` | Gateway gRPC address |
| `EYED_DEVICE_ID` | `capture-01` | Device identifier |
| `EYED_IMAGE_DIR` | `/data/Iris/CASIA1` | Image directory (directory mode) |
| `EYED_CAMERA_SOURCE` | `directory` | `directory` or `webcam` |
| `EYED_CAMERA_DEVICE` | `/dev/video0` | Webcam device path or URL |
| `EYED_QUALITY_THRESHOLD` | `0.05` | Sobel quality gate threshold |
| `EYED_LOG_LEVEL` | `info` | Logging level |

---

## Makefile Reference

```
  up              Start all services
  up-d            Start all services (detached)
  down            Stop all services
  dev             Start with hot reload (development)
  build           Build all service images
  build-gateway   Build gateway image only
  build-capture   Build capture-device image only
  build-webui     Build web-ui image only
  rebuild         Rebuild all without cache
  restart         Restart iris-engine
  ps              Show running containers
  health          Liveness check (all services)
  ready           Readiness check (all services)
  gallery         Show gallery size
  status          Full status overview
  logs            Follow all logs
  logs-engine     Follow iris-engine logs
  logs-gateway    Follow gateway logs
  logs-capture    Follow capture-device logs
  logs-webui      Follow web-ui logs
  test            Run fast unit tests inside container
  test-integration Run end-to-end integration test
  test-fnmr       Run FNMR accuracy test on CASIA1 dataset
  test-fnmr-mmu2  Run FNMR accuracy test on MMU2 dataset
  test-bench      Run pipeline latency benchmark
  shell           Open shell in iris-engine container
  dev-webui       Start web-ui dev server (host, port 3000)
  webcam          Start with webcam (Linux)
  webcam-macos    Start with webcam (macOS)
  webcam-relay    Run MJPEG webcam relay on host
  db-shell        Open psql shell in postgres container
  db-reset        Drop and recreate database schema
  clean           Stop and remove volumes
  nuke            Remove everything
  help            Show this help
```
