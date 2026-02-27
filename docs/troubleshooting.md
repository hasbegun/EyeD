# EyeD Troubleshooting Guide

## Table of Contents

- [Docker & Container Issues](#docker--container-issues)
- [iris-engine Startup Issues](#iris-engine-startup-issues)
- [NATS Issues](#nats-issues)
- [Pipeline & Analysis Errors](#pipeline--analysis-errors)
- [Image Quality Issues](#image-quality-issues)
- [Enrollment Issues](#enrollment-issues)
- [Performance Issues](#performance-issues)
- [Network & Connectivity](#network--connectivity)
- [Useful Commands Reference](#useful-commands-reference)

---

## Docker & Container Issues

### Containers won't start

**Check if Docker is running:**
```bash
docker info
```

**Check if ports are already in use:**
```bash
# macOS / Linux
lsof -i :7000    # iris-engine port
lsof -i :7002    # NATS port
lsof -i :7001    # NATS monitoring port
```

**Kill a process using a port:**
```bash
kill -9 $(lsof -ti :7000)
```

**Start fresh (remove all containers and volumes):**
```bash
docker compose down -v
docker compose up
```

### Build fails

**Clear Docker build cache and rebuild:**
```bash
docker compose build --no-cache iris-engine
```

**Check disk space (Docker images can be large):**
```bash
docker system df
```

**Free up Docker disk space:**
```bash
docker system prune -a    # WARNING: removes all unused images
```

**Check build logs in detail:**
```bash
docker compose build iris-engine 2>&1 | tee build.log
```

### Container keeps restarting

**Check container logs:**
```bash
docker compose logs iris-engine --tail=50
```

**Check container exit code:**
```bash
docker inspect eyed-iris-engine-1 --format='{{.State.ExitCode}}'
```

**Get a shell into a running container:**
```bash
docker compose exec iris-engine /bin/bash
```

**Get a shell into a container even if it's crashing:**
```bash
docker compose run --rm --entrypoint /bin/bash iris-engine
```

### Image is too large

**Check image sizes:**
```bash
docker images | grep eyed
```

Expected sizes:
- `eyed-iris-engine` (CPU): ~800MB–1.2GB (includes Open-IRIS + OpenCV + ONNX Runtime)
- `nats`: ~20MB

---

## iris-engine Startup Issues

### Model download fails

On first startup, the iris-engine downloads the segmentation model (~56MB) from HuggingFace. If this fails:

**Check internet connectivity from inside the container:**
```bash
docker compose exec iris-engine curl -I https://huggingface.co
```

**Pre-download the model and mount it:**
```bash
# Download model locally
pip install huggingface_hub
python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download('Worldcoin/iris-semantic-segmentation',
                'iris_semseg_upp_scse_mobilenetv2.onnx',
                local_dir='/tmp/models')
"

# Mount into container via docker-compose override
# Add to docker-compose.dev.yml:
# volumes:
#   - /tmp/models:/root/.cache/huggingface:ro
```

**Check if model is cached (after first successful download):**
```bash
docker compose exec iris-engine ls -la /root/.cache/huggingface/
```

### Pipeline fails to initialize

**Check Python version:**
```bash
docker compose exec iris-engine python3 --version
# Should be Python 3.10.x
```

**Check installed packages:**
```bash
docker compose exec iris-engine pip list | grep -E "open-iris|pydantic|fastapi|onnxruntime|opencv"
```

Expected output:
```
fastapi              0.10x.x
onnxruntime          1.16.3
open-iris            1.11.0
opencv-python        4.7.0.68
pydantic             1.10.13
numpy                1.24.4
```

**Test Open-IRIS import directly:**
```bash
docker compose exec iris-engine python3 -c "
import iris
print('Open-IRIS version:', iris.__version__)  # Should be 1.11.0
pipeline = iris.IRISPipeline()
print('Pipeline loaded successfully')

# Quick smoke test
import numpy as np
dummy = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
result = pipeline(iris.IRImage(img_data=dummy, eye_side='left'))
print('Pipeline result keys:', list(result.keys()))
"
```

### Wrong Pydantic version error

If you see errors like `model_dump_json`, `model_validate`, or `pydantic_settings`:

Open-IRIS 1.11.0 pins `pydantic==1.10.13` (v1). Our code uses v1 syntax:
- `.json()` not `.model_dump_json()`
- `.dict()` not `.model_dump()`
- `from pydantic import BaseSettings` not `from pydantic_settings import BaseSettings`

---

## NATS Issues

### iris-engine can't connect to NATS

**Check if NATS is running:**
```bash
docker compose ps nats
```

**Check NATS logs:**
```bash
docker compose logs nats
```

**Test NATS connectivity from iris-engine container:**
```bash
docker compose exec iris-engine python3 -c "
import asyncio, nats
async def test():
    nc = await nats.connect('nats://nats:4222')
    print('Connected to NATS')
    await nc.close()
asyncio.run(test())
"
```

**Check NATS monitoring dashboard:**
```bash
curl -s http://localhost:7001/varz | python3 -m json.tool
```

**Check NATS connections:**
```bash
curl -s http://localhost:7001/connz | python3 -m json.tool
```

**Check NATS subscriptions:**
```bash
curl -s http://localhost:7001/subsz | python3 -m json.tool
```

**Note:** iris-engine runs fine without NATS — the HTTP endpoints (`/analyze`, `/enroll`) work independently. NATS is only needed for the production pipeline (gateway → iris-engine → gateway).

### NATS config errors

**Validate NATS config:**
```bash
docker compose exec nats nats-server --config /etc/nats/nats-server.conf -t
```

**Check NATS server info:**
```bash
curl -s http://localhost:7001/ | python3 -m json.tool
```

---

## Pipeline & Analysis Errors

### `Failed to decode JPEG image`

The uploaded file is not a valid JPEG.

**Verify the file is actually a JPEG:**
```bash
file your_image.jpg
# Should output: JPEG image data, ...
```

**Check file size (should be > 1KB for a real image):**
```bash
ls -la your_image.jpg
```

**Convert to JPEG if it's a different format:**
```bash
# Requires ImageMagick
convert input.png output.jpg

# Or with Python
python3 -c "
from PIL import Image
Image.open('input.png').convert('L').save('output.jpg')
"
```

### `VectorizationError: Number of contours must be equal to 1`

The DNN segmented the image but couldn't find exactly one pupil or iris boundary.

**Common causes:**
- Image does not contain a recognizable eye
- Image has multiple eyes (crop to a single eye)
- Image is too dark or too bright
- Image is not close enough to the eye

**Debug by checking what the DNN sees:**
```bash
docker compose exec iris-engine python3 -c "
import cv2, numpy as np, iris

img = cv2.imread('/path/to/image.jpg', cv2.IMREAD_GRAYSCALE)
print(f'Image shape: {img.shape}, dtype: {img.dtype}')
print(f'Min: {img.min()}, Max: {img.max()}, Mean: {img.mean():.1f}')

pipeline = iris.IRISPipeline()
result = pipeline(iris.IRImage(img_data=img, eye_side='left'))
print('Error:', result.get('error'))
print('Template:', result.get('iris_template'))
print('Keys:', list(result.keys()))
"
```

### `OcclusionError: visible_fraction < min_allowed_occlusion`

The iris was found but too much of it is covered by eyelids or eyelashes.

**Current threshold:** 30% of iris must be visible.

**Solutions:**
- Ask the subject to open their eye wider
- Adjust camera angle to reduce eyelid occlusion
- Use the image with the eye most open from a burst of captures

### `SegmentationError` or `NormalizationError`

Less common errors from the Open-IRIS pipeline internals.

**Get the full traceback:**
```bash
# The error field in the response includes the traceback
curl -s -X POST http://localhost:7000/analyze \
  -F "file=@image.jpg" -F "eye_side=left" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('error'):
    print(data['error'])
else:
    print('Success! Latency:', data['latency_ms'], 'ms')
"
```

---

## Image Quality Issues

### Testing image quality

**Generate a test image to verify the pipeline works:**
```bash
python3 -c "
import cv2, numpy as np
h, w = 480, 640
img = np.ones((h, w), dtype=np.uint8) * 180
cy, cx = h // 2, w // 2
y, x = np.ogrid[:h, :w]
dist = np.sqrt((x - cx)**2 + (y - cy)**2)
img[dist < 120] = 100
img[dist < 45] = 20
angles = np.arctan2(y - cy, x - cx)
iris_ring = (dist < 120) & (dist >= 45)
pattern = (np.sin(angles * 40) * 20).astype(np.uint8)
img[iris_ring] = np.clip(100 + pattern[iris_ring], 60, 140).astype(np.uint8)
cv2.imwrite('/tmp/test_eye.jpg', img)
print('Saved /tmp/test_eye.jpg')
"
```

**Note:** Synthetic images will produce `OcclusionError` or `VectorizationError` — this is expected. The pipeline needs real NIR iris images for full template generation. The test confirms the pipeline plumbing works.

### Best practices for eye images

```
GOOD                                    BAD
┌──────────────────────┐    ┌──────────────────────┐
│                      │    │  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄  │
│   ╔══════════════╗   │    │  ████████████████████ │  <- eyelid covers iris
│   ║  ┌────────┐  ║   │    │  ███ ┌────┐ █████████│
│   ║  │ PUPIL  │  ║   │    │  ███ │    │ █████████│
│   ║  │        │  ║   │    │  ▀▀▀▀└────┘▀▀▀▀▀▀▀▀▀│
│   ║  └────────┘  ║   │    │                      │
│   ║   IRIS       ║   │    └──────────────────────┘
│   ╚══════════════╝   │
│   SCLERA             │    ┌──────────────────────┐
└──────────────────────┘    │                      │
                            │  tiny eye far away   │  <- too far from camera
 Eye fills most of frame    │       . .            │
 Iris clearly visible       │                      │
 Minimal eyelid occlusion   └──────────────────────┘
```

---

## Enrollment Issues

### Duplicate detection

When enrolling, if the system returns `is_duplicate: true`:

```json
{
  "identity_id": "new-person",
  "template_id": "",
  "is_duplicate": true,
  "duplicate_identity_id": "existing-person-001"
}
```

This means the iris is already enrolled under `existing-person-001`. The dedup threshold (0.32) is stricter than the match threshold (0.39) to prevent false enrollments.

### Gallery is empty after restart

In Phase 1, the gallery is **in-memory only**. Templates are lost when the container restarts.

```bash
# Check current gallery size
curl -s http://localhost:7000/gallery/size

# After docker compose restart, gallery will be 0
docker compose restart iris-engine
curl -s http://localhost:7000/gallery/size
# {"gallery_size": 0}
```

Persistent template storage (PostgreSQL) is planned for Phase 5.

### Enrollment fails with pipeline error

Same causes as analysis errors above. The enrollment pipeline runs the same Open-IRIS pipeline as `/analyze` — if analysis fails, enrollment will fail with the same error.

---

## Performance Issues

### Slow inference

**Check current latency:**
```bash
# Analyze and extract latency
curl -s -X POST http://localhost:7000/analyze \
  -F "file=@eye.jpg" -F "eye_side=left" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Latency: {data[\"latency_ms\"]:.0f} ms')
"
```

**Expected latencies:**

| Runtime | Segmentation | Full pipeline | Notes |
|---------|-------------|---------------|-------|
| CPU (default) | ~100-200ms | ~130-270ms | Fine for development |
| CUDA (Linux+GPU) | ~15ms | ~45ms | Production |
| CoreML (macOS) | ~30-50ms | ~60-90ms | Optional Mac acceleration |

### Check container resource usage

```bash
docker stats --no-stream
```

### Check if the model is running on CPU vs GPU

```bash
docker compose exec iris-engine python3 -c "
import onnxruntime as ort
print('Available providers:', ort.get_available_providers())
print('Current device:', ort.get_device())
"
```

### Memory usage is high

Open-IRIS + ONNX Runtime + OpenCV typically use 300-500MB.

**Check memory inside container:**
```bash
docker compose exec iris-engine python3 -c "
import psutil
mem = psutil.virtual_memory()
print(f'Total: {mem.total / 1e9:.1f} GB')
print(f'Used: {mem.used / 1e9:.1f} GB ({mem.percent}%)')
print(f'Available: {mem.available / 1e9:.1f} GB')
"
```

---

## Network & Connectivity

### Can't reach iris-engine from another machine

By default, the service binds to `0.0.0.0:7000` inside Docker, mapped to `localhost:7000` on the host.

**To access from another machine on the LAN:**
```bash
# Find your IP
ifconfig | grep "inet " | grep -v 127.0.0.1

# Access from another machine
curl http://<your-ip>:7000/health/alive
```

### Test NATS pub/sub manually

**Install NATS CLI:**
```bash
# macOS
brew install nats-io/nats-tools/nats

# Or download from https://github.com/nats-io/natscli/releases
```

**Subscribe to results:**
```bash
nats sub "eyed.result" --server=nats://localhost:7002
```

**Publish a test analyze request:**
```bash
# First, base64-encode an image
B64=$(base64 -i /tmp/test_eye.jpg)

# Publish to NATS
nats pub "eyed.analyze" "{\"frame_id\":\"nats-test-001\",\"device_id\":\"cli\",\"jpeg_b64\":\"$B64\",\"eye_side\":\"left\"}" --server=nats://localhost:7002
```

**Check NATS subject subscriptions:**
```bash
nats sub --server=nats://localhost:7002 ">"    # Subscribe to ALL subjects
```

---

## Useful Commands Reference

### Docker Compose

```bash
# Start all services
docker compose up

# Start in background
docker compose up -d

# Start with hot reload (development)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Rebuild a specific service
docker compose build iris-engine

# Rebuild without cache
docker compose build --no-cache iris-engine

# View logs (follow)
docker compose logs -f

# View logs for one service
docker compose logs -f iris-engine

# View last N lines of logs
docker compose logs --tail=100 iris-engine

# Stop all services
docker compose down

# Stop and remove volumes (clean slate)
docker compose down -v

# Restart a single service
docker compose restart iris-engine

# Check running containers
docker compose ps

# Get a shell into a running container
docker compose exec iris-engine /bin/bash

# Run a one-off command in a new container
docker compose run --rm iris-engine python3 -c "print('hello')"
```

### Health & Status

```bash
# Liveness check
curl -s http://localhost:7000/health/alive | python3 -m json.tool

# Readiness check (pipeline + NATS)
curl -s http://localhost:7000/health/ready | python3 -m json.tool

# Gallery size
curl -s http://localhost:7000/gallery/size | python3 -m json.tool

# NATS server info
curl -s http://localhost:7001/ | python3 -m json.tool

# NATS connections
curl -s http://localhost:7001/connz | python3 -m json.tool

# NATS subscriptions
curl -s http://localhost:7001/subsz | python3 -m json.tool

# NATS server variables (detailed stats)
curl -s http://localhost:7001/varz | python3 -m json.tool
```

### Analysis & Enrollment

```bash
# Analyze via file upload
curl -s -X POST http://localhost:7000/analyze \
  -F "file=@eye.jpg" \
  -F "eye_side=left" | python3 -m json.tool

# Analyze via JSON (base64)
B64=$(base64 -i eye.jpg)
curl -s -X POST http://localhost:7000/analyze/json \
  -H "Content-Type: application/json" \
  -d "{\"frame_id\":\"test\",\"jpeg_b64\":\"$B64\",\"eye_side\":\"left\"}" \
  | python3 -m json.tool

# Enroll a new identity
B64=$(base64 -i eye.jpg)
curl -s -X POST http://localhost:7000/enroll \
  -H "Content-Type: application/json" \
  -d "{\"identity_id\":\"person-001\",\"identity_name\":\"Jane\",\"jpeg_b64\":\"$B64\",\"eye_side\":\"left\"}" \
  | python3 -m json.tool

# Batch test multiple images
for img in eyes/*.jpg; do
  echo "--- $img ---"
  curl -s -X POST http://localhost:7000/analyze \
    -F "file=@$img" -F "eye_side=left" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('error'):
    print(f'ERROR: {d[\"error\"][:80]}')
else:
    print(f'OK latency={d[\"latency_ms\"]:.0f}ms match={d.get(\"match\")}')
"
done
```

### Debugging Inside Container

```bash
# Interactive Python with Open-IRIS
docker compose exec iris-engine python3 -c "
import iris
print(dir(iris))
"

# Check ONNX Runtime providers
docker compose exec iris-engine python3 -c "
import onnxruntime as ort
print('Providers:', ort.get_available_providers())
"

# Check Open-IRIS version
docker compose exec iris-engine python3 -c "
import iris; print(iris.__version__)
"

# List all installed packages
docker compose exec iris-engine pip list

# Check disk usage inside container
docker compose exec iris-engine df -h

# Check running processes
docker compose exec iris-engine ps aux
```

### Docker Diagnostics

```bash
# Container resource usage (CPU, memory, network)
docker stats --no-stream

# Inspect container configuration
docker inspect eyed-iris-engine-1

# Check container IP address
docker inspect eyed-iris-engine-1 --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

# Check Docker network
docker network inspect eyed_default

# View Docker events (real-time)
docker events --filter container=eyed-iris-engine-1

# Export container filesystem for inspection
docker export eyed-iris-engine-1 > container.tar

# Check image layers
docker history eyed-iris-engine
```

### Cleanup

```bash
# Stop everything
docker compose down

# Stop and delete volumes (gallery data, NATS state)
docker compose down -v

# Remove built images
docker compose down --rmi local

# Remove everything (containers, volumes, images, networks)
docker compose down -v --rmi all --remove-orphans

# System-wide Docker cleanup
docker system prune          # Remove stopped containers, dangling images
docker system prune -a       # Remove ALL unused images (aggressive)
docker volume prune          # Remove unused volumes
```
