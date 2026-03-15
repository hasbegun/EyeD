# EyeD - Modern Architecture Proposal

**Date:** February 18, 2026
**Goal:** Real-time eye capture and iris analysis on the fly
**Strategy:** Open-IRIS (Worldcoin), containerized microservice architecture
**Deployment:** RPi edge capture + containerized compute (on-prem / cloud / hybrid)

---

## 1. What's Wrong with the Current Architecture

```
┌──────────────────────────────────────────────────┐
│           CURRENT (2015 era)                     │
│                                                  │
│   Everything on ONE thread, ONE machine          │
│   Qt5 main loop = capture + detect + analyze     │
│                                                  │
│   Camera → Haar Cascade → Masek Pipeline → UI    │
│                  ↑              ↑                │
│              ~50ms          ~2 min (eyelid!)     │
│                                                  │
│   UI freezes during processing                   │
│   IplImage (deprecated C API)                    │
│   Manual malloc/free everywhere                  │
│   Hardcoded paths, no config                     │
│   500MB+ Qt dependency for a simple image viewer │
│   Zero thread safety                             │
│   Assumes desktop-class hardware                 │
└──────────────────────────────────────────────────┘
```

**The 3 critical bottlenecks:**

| Stage | Current | Time | Problem |
|-------|---------|------|---------|
| Eye Detection | Haar Cascade | ~50ms | Inaccurate, misses angles, no GPU |
| Eyelid Detection | Hough lines + curve fitting | ~1-2 min | Way too slow for real-time |
| Iris Segmentation | Sequential Hough circles | ~100ms | CPU only, not parallelized |

**What's actually fast and worth keeping:**

| Stage | Current | Time | Verdict |
|-------|---------|------|---------|
| Normalization | Polar unwrap | ~10ms | Keep |
| Gabor Encoding | FFT + filter bank | ~50ms | Keep |
| Hamming Match | Bitwise + shifts | ~1ms | Keep |
| Quality Check | Sobel edge | ~5ms | Keep |

---

## 2. Why Split Architecture

An RPi cannot do real-time DNN inference. The numbers:

| Task | Jetson Nano (GPU) | RPi 4 (CPU) | RPi 5 (CPU) |
|------|-------------------|-------------|-------------|
| MobileNet eye detection | ~5ms | **~150-200ms** | ~80-120ms |
| U-Net iris segmentation | ~8ms | **~300-500ms** | ~150-250ms |
| Full analysis pipeline | ~90ms | **~500ms+** | ~300ms+ |

RPi at 500ms+ per frame = ~2fps analysis. Not real-time.

**Solution: separate capture from compute.**

The RPi is good at:
- Camera I/O (V4L2, direct hardware access)
- Streaming compressed frames over network
- Streaming video via WebRTC (H.264 hardware encode)
- Running cheap CPU operations (Sobel quality check = ~5ms)

A GPU server is good at:
- DNN inference (eye detection, iris segmentation)
- Gabor encoding (multi-scale 2D Gabor via Open-IRIS)
- Template matching at scale
- Handling multiple capture devices simultaneously

---

## 3. Proposed Architecture

```
  CAPTURE DEVICE (RPi)             COMPUTE SERVER (Docker)                      BROWSER
  Headless, no display             Containerized services                       (Any device)
 ┌───────────────────────┐         ┌──────────────────────────────────────┐
 │                       │         │                                      │
 │  ┌──────────┐         │  gRPC   │  ┌──────────────────────────────┐    │
 │  │  Camera   │        │ (mTLS)  │  │       iris-engine (Open-IRIS)│    │
 │  │  V4L2     │        │         │  │                              │    │     ┌────────────┐
 │  └────┬──────┘        │         │  │  ┌────────┐  ┌───────────┐   │    │     │  Web UI    │
 │       │               │         │  │  │ Segment │  │  Encode   │  │    │     │  (browser) │
 │       ▼               │         │  │  │ (DNN)   │  │ (Gabor)   │  │    │     │            │
 │  ┌──────────┐         │         │  │  │Normalize│  │ Match     │  │    │     │ WebRTC     │
 │  │ Quality  │──frame─▶│ ═══════▶│  │  └────┬────┘  │ (Hamming) │  │    │◀────│ live feed  │
 │  │ Gate     │ (if     │         │  │       │       └─────┬─────┘  │    │     │            │
 │  │ (Sobel)  │ quality │         │  │       ▼             │        │    │     │ Dashboard  │
 │  └──────────┘ passes) │         │  │  ┌────────────┐     │        │    │     │ Results    │
 │       │               │         │  │  │ Full IRIS  │─────┘        │    │     │ Enrollment │
 │       ▼               │         │  │  │   Pipeline │              │    │     └────────────┘
 │  ┌──────────┐         │         │  │  └────────────┘              │    │
 │  │ WebRTC   │─stream─▶│ ═══════▶│  └──────────────────────────────┘    │
 │  │ (video)  │         │         │                                      │
 │  └──────────┘         │         │  ┌──────────────────────────────┐    │
 │                       │         │  │       Template Store         │    │
 │                       │         │  │  (enrolled iris templates)   │    │
 │                       │         │  └──────────────────────────────┘    │
 └───────────────────────┘         └──────────────────────────────────────┘
      ~$25-50                            ~$99-500
      ~3W power                          ~10-40W power
      ~32MB RAM used                     ~200MB-1GB RAM used
      Headless, no display               Hosts web-ui + iris-engine
```

---

## 4. Capture Device (RPi)

### What runs on the RPi

The RPi is a **headless sensor node**. No screen, no display stack, no GPU compositor. It captures frames, filters by quality, streams to the server, and provides a WebRTC feed for remote viewing.

| Task | Method | Time on RPi 4 | CPU Cost |
|------|--------|---------------|----------|
| Frame capture | V4L2 / OpenCV | ~1ms | Negligible |
| Quality check | Sobel edge detection | ~5ms | Low |
| JPEG compress | libjpeg-turbo (NEON) | ~3ms | Low |
| gRPC send (analysis) | gRPC to gateway | ~2ms (LAN) | Low |
| WebRTC encode | H.264 hardware encoder (V4L2 M2M) | ~2ms | Low (hardware) |
| **Total per frame** | | **~13ms** | **< 15% CPU** |

No display dependencies. No SDL, no ImGui, no OpenGL. Binary is ~5MB.

### Capture Device Threads (2 threads)

```
Thread 1: Capture
  Camera (30fps) → Ring Buffer [4 frames]

Thread 2: Gate + Send
  Ring Buffer → Sobel Quality Check → if quality > threshold:
                                        JPEG compress → gRPC send to server
                                    → always:
                                        WebRTC encode → stream to web-ui (via signaling)
```

**No UI thread.** All display/interaction happens in the browser via the `web-ui` service.

### WebRTC Video Stream

The RPi streams its camera feed over WebRTC so operators can view it in a browser. The gateway acts as the signaling server.

```
RPi camera → H.264 encode (hardware) → WebRTC → browser
                                           ↑
                                    Gateway acts as
                                    signaling server
                                    (SDP offer/answer)
```

**Why WebRTC over MJPEG:**
- H.264 hardware encoding on RPi (V4L2 M2M codec, ~2ms, near-zero CPU)
- ~50ms glass-to-glass latency (vs ~200ms for MJPEG polling)
- Adaptive bitrate based on network conditions
- Built-in browser support, no plugins

**STUN/TURN for NAT traversal:**
- LAN deployment: no STUN/TURN needed (direct peer connection)
- Cloud deployment: use coturn (open-source TURN server) as a sidecar container
- The gateway relays SDP signaling between RPi and browser via WebSocket

### Smart Frame Selection

The RPi doesn't blindly stream every frame. The quality gate filters:

```
30fps capture ──▶ Sobel quality score ──▶ threshold filter ──▶ ~3-5 fps sent to server
                      (~5ms, CPU)             (score > 0.30)
```

This cuts network bandwidth by 6-10x and avoids wasting server compute on blurry/bad frames.

### What the RPi sends

```
CaptureFrame {
    bytes   jpeg_data;      // JPEG compressed eye region (~10-30 KB)
    float   quality_score;  // Sobel score (pre-computed)
    uint64  timestamp_us;   // Capture timestamp
    uint32  frame_id;       // Monotonic frame counter
    string  device_id;      // Which capture device
    bool    is_nir;         // Camera type flag
}
```

### What the RPi receives back

Minimal ack - the RPi doesn't display results, the browser does. The RPi only needs to know if the server is keeping up (for backpressure / frame dropping).

```
FrameAck {
    uint32  frame_id;           // Which frame this ack is for
    bool    accepted;           // Server accepted the frame (false = backpressure, slow down)
    uint32  queue_depth;        // Server-side queue depth (for adaptive sending rate)
}
```

Full analysis results (match score, circles, identity) are pushed to the **browser** via WebSocket from the gateway, not back to the RPi.

### Capture Device Docker Build

The capture binary is cross-compiled for ARM64 inside a Docker multi-stage build. No toolchain installation required on the host.

```dockerfile
# capture/Dockerfile
FROM debian:trixie-slim AS build
RUN apt-get update && apt-get install -y \
    g++-aarch64-linux-gnu cmake ninja-build \
    libopencv-dev:arm64 libgrpc++-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

COPY . /src
RUN cmake -S /src -B /build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=/src/cmake/aarch64-toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /build

# Runtime image for RPi (deployed via docker compose on the Pi)
FROM arm64v8/debian:trixie-slim
RUN apt-get update && apt-get install -y libopencv-core libgrpc++ && rm -rf /var/lib/apt/lists/*
COPY --from=build /build/eyed-capture /app/eyed-capture
COPY certs/ /app/certs/
EXPOSE 8554
CMD ["/app/eyed-capture", "--config", "/config/capture.toml"]
```

The capture device can either run the binary natively (for lowest latency) or as a Docker container on the RPi. For fleet management, Docker is preferred — update all capture devices by pulling a new image.

---

## 5. Compute Server

### What runs on the server

All heavy computation runs server-side. The core algorithm is **Open-IRIS** (Worldcoin, MIT license) — the best open-source iris recognition system available, 150x more accurate than our Masek implementation. It runs as a **standalone algorithm service** (Python) that accepts eye images and returns iris codes + match results.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    COMPUTE SERVER                                           │
│                                                                             │
│  ┌──────────────────┐     ┌─────────────────────────────────────────────┐   │
│  │  Gateway         │     │   Iris Engine (Open-IRIS)                   │   │
│  │  (gRPC + NATS)   │────▶│                                             │   │
│  │                  │     │   Python service (CUDA/CPU)                 │   │
│  │  Accepts frames  │     │   Worker pool (N processes)                 │   │
│  │  from N devices  │     │                                             │   │
│  └──────────────────┘     │  Full pipeline per frame:                   │   │
│                           │                                             │   │
│                           │  1. Image decode (~2ms)                     │   │
│                           │  2. Segmentation (~15ms CUDA / ~100ms CPU)  │   │
│                           │     MobileNetV2 + UNet++                    │   │
│                           │     4-class mask (IoU 0.94)                 │   │
│                           │  3. Normalization (~5ms)                    │   │
│                           │     Daugman rubber sheet                    │   │
│                           │  4. Encoding (~20ms)                        │   │
│                           │     2D Gabor, >10,000 bits                  │   │
│                           │  5. Matching (~1ms)                         │   │
│                           │     Fractional Hamming dist                 │   │
│                           │                                             │   │
│                           │  Total: ~43ms per frame                     │   │
│                           └─────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Template Store                                                     │    │
│  │  - Enrolled iris templates (in-memory for speed)                    │    │
│  │  - PostgreSQL / SQLite for persistence                              │    │
│  │  - One-to-many matching support                                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Server Analysis Pipeline (Open-IRIS)

```
Incoming JPEG
    │
    ▼
┌──────────────────────────────────────────────────────────────┐
│  Open-IRIS Segmentation (MobileNetV2 + UNet++ with scSE)     │
│  Input: eye image (any size, auto-resized)                   │
│  Output: 4-class pixel mask                                  │
│    Class 0: Eyeball (sclera, skin)                           │
│    Class 1: Iris                                             │
│    Class 2: Pupil                                            │
│    Class 3: Eyelashes / occlusion                            │
│  IoU: 0.943 across all classes                               │
│  ~15ms (GPU) / ~100ms (CPU)                                  │
│                                                              │
│  From mask, extract:                                         │
│   - Pupil circle: ellipse fit on pupil pixels                │
│   - Iris circle: ellipse fit on iris pixels                  │
│   - Noise mask: eyelash/occlusion pixels                     │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│  Open-IRIS Normalization (Daugman rubber sheet)              │
│  Same mathematical model as Masek, better implementation     │
│  Polar unwrap: circular iris → normalized rectangular strip  │
│  ~5ms (CPU)                                                  │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│  Open-IRIS Encoding (2D Gabor filters)                       │
│  Multiple scales, >10,000 bit iris code                      │
│  vs Masek's 1 scale, ~2,048 bits                             │
│  ~20ms (CPU)                                                 │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│  Open-IRIS Matching (Masked fractional Hamming distance)     │
│  Compare against enrolled template(s)                        │
│  Rotation-compensated, noise-mask-aware                      │
│  ~1ms per comparison (CPU)                                   │
│                                                              │
│  FNMR < 0.12% @ FMR = 0.001 (150x better than Masek)         │
└──────────────────────────────────────────────────────────────┘
```

### Why Open-IRIS replaces Masek entirely

| Aspect | Masek (BiometricLib) | Open-IRIS | Winner |
|--------|---------------------|-----------|--------|
| Segmentation | Hough circles (IoU ~35%) | MobileNetV2+UNet++ (IoU 94.3%) | Open-IRIS |
| Normalization | Daugman rubber sheet | Daugman rubber sheet (same math) | Tie |
| Encoding | 1D Log-Gabor, 1 scale, ~2K bits | 2D Gabor, multi-scale, >10K bits | Open-IRIS |
| Matching | Hamming distance | Masked fractional Hamming | Open-IRIS |
| FNMR @ FMR=0.001 | ~17-27% (est.) | **0.12%** | Open-IRIS (150x) |
| License | Custom | MIT | Open-IRIS |
| Maintained | Abandoned (2018) | Active (2025+) | Open-IRIS |
| Language | C/C++ | Python | — |
| Pretrained models | None | HuggingFace | Open-IRIS |

There is no reason to keep Masek. Open-IRIS uses the same mathematical foundations (Daugman normalization, Gabor encoding, Hamming matching) but with a better segmentation DNN, better-tuned Gabor parameters, and fractional Hamming with proper noise masking.

### Server Scaling

| Setup | Runtime | Capture Devices | Analysis FPS (total) |
|-------|---------|----------------|---------------------|
| Mac M-series (dev, 4 workers) | CPU/CoreML | 1-2 | ~7-12 fps |
| Jetson Nano (1 CUDA worker) | CUDA | 1-3 | ~20 fps |
| Jetson Xavier (2 CUDA workers) | CUDA | 4-8 | ~45 fps |
| Desktop GPU (4 workers) | CUDA | 8-15 | ~80 fps |
| Multi-GPU server | CUDA | 15+ | ~150+ fps |
| CPU-only server (8 workers) | CPU | 2-4 | ~15 fps |

Each capture device sends ~3-5 quality frames/sec. Even CPU-only mode handles a few devices; CUDA scales to production loads.

---

## 6. Network Protocol

### Option A: gRPC (Recommended)

```protobuf
service IrisAnalysis {
    // Single frame analysis
    rpc Analyze(CaptureFrame) returns (AnalysisResult);

    // Streaming: continuous frame submission
    rpc AnalyzeStream(stream CaptureFrame) returns (stream AnalysisResult);

    // Enrollment
    rpc Enroll(EnrollRequest) returns (EnrollResponse);

    // Health check
    rpc GetStatus(Empty) returns (ServerStatus);
}
```

**Why gRPC:**
- Protobuf binary encoding (compact, fast serialization)
- HTTP/2 streaming (keeps connection alive, low overhead)
- Generated client/server stubs for C++
- Works over LAN and WAN
- Built-in deadline/timeout support

### Option B: ZeroMQ (Simpler alternative)

- Lower latency on LAN (~0.1ms vs ~1ms for gRPC)
- No code generation needed
- Good for simple pub/sub patterns
- But: no built-in serialization, no streaming, manual framing

### Network Latency Budget

```
RPi → Server (LAN):
  Quality check:    ~5ms   (RPi CPU)
  JPEG compress:    ~3ms   (RPi CPU, NEON accelerated)
  Network send:     ~2ms   (1Gbps LAN, ~30KB frame)
  Server analysis:  ~77ms  (GPU)
  Network return:   ~1ms   (tiny result payload)
  ─────────────────────────
  Total round-trip: ~88ms  (capture to result displayed)

  → ~11 fps effective analysis rate per device
  → Camera feed streams at 30fps via WebRTC to browser (parallel path)
```

---

## 7. Containerized Microservices

The monolithic "compute server" from section 5 splits into independent containers. Each service does one thing and can be deployed anywhere: on-prem Jetson, cloud VM, or a mix.

### Service Decomposition

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                       │
│  EDGE (RPi)              ON-PREM / CLOUD (Containers)                    BROWSER      │
│  Headless                                                                             │
│  ┌────────────┐           ┌──────────────┐                                            │
│  │  capture   │──frame──▶ │  gateway     │     ┌──────────────────┐                   │
│  │  device    │           │  (routing +  │────▶│  iris-engine     │                   │
│  │  (no UI)   │◀──ack──── │   signaling) │     │  (Open-IRIS)     │  ┌─────────────┐  │
│  └─────┬──────┘           └──────┬───────┘     │                  │  │             │  │
│        │                        │              │  segment →       │  │  web-ui     │  │
│        │ WebRTC                 │              │  normalize →     │  │  (SPA)      │  │
│        │ (video stream)         │              │  encode →        │  │             │  │
│        │                        │              │  match           │  │ ◀─WebSocket─┤  │
│        │                        │              │                  │  │   results   │  │
│        │                        │              │  Python service  │  │             │  │
│        │                        │              │  GPU-accelerated │  │ ◀─WebRTC────┤  │
│        └────────────────────────┼── relay ─────┘──────┬───────────┘  │   video     │  │
│                                 │                     │              └─────────────┘  │
│                                 │               ┌─────┴─────┐                         │
│                                 │               ▼           ▼                         │
│                                 │      ┌───────────┐ ┌───────────┐                    │
│                                 │      │ template- │ │ storage   │                    │
│                                 │      │ db        │ │ (archive) │                    │
│                                 │      └─────┬─────┘ └─────┬─────┘                    │
│                                 │            │             │                          │
│                                 │            ▼             ▼                          │
│                                 │      ┌──────────────────────┐                       │
│                                 │      │    object-store      │                       │
│                                 │      │  (raw images, blobs) │                       │
│                                 │      └──────────────────────┘                       │
│                                 │                                                     │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

### The 6 Services

The 4 C++ pipeline services (detector, segmenter, encoder, matcher) are **collapsed into a single `iris-engine` service** running Open-IRIS. The entire recognition pipeline — segmentation, normalization, encoding, matching — is one atomic call. No inter-service chatter for the hot path.

| Service | Responsibility | Stateless? | GPU? | Cloud-able? |
|---------|---------------|------------|------|-------------|
| **gateway** | Accept frames from capture devices, WebRTC signaling relay, WebSocket push to browsers, route to iris-engine | Yes | No | Yes |
| **iris-engine** | Full iris recognition pipeline (Open-IRIS): segment → normalize → encode → match. Pipeline pool for parallel batch work. Redis write-through cache for enrollment persistence. Python service, CUDA/CPU/CoreML | Yes | Optional | Yes |
| **web-ui** | Serve SPA (static HTML/JS/CSS), enrollment forms, admin dashboard, live device monitoring | Yes | No | Yes |
| **storage** | Archive raw images + pipeline artifacts, dedup check, training data export | Yes | No | Yes |
| **template-db** | Template CRUD, enrollment, 1:N search | **Stateful** | No | Yes |
| **object-store** | Raw image blobs, segmentation masks, audit trail | **Stateful** | No | Yes |

**Why collapse 4 services into 1:**
- Open-IRIS runs the full pipeline as a single Python call (~43ms). Splitting it across containers would add ~4-8ms of serialization/deserialization overhead per hop for zero benefit
- The segmentation model and Gabor encoding share in-process memory (model weights, filter banks). Splitting them means duplicating data across processes
- Horizontal scaling is still trivial: run N `iris-engine` replicas, NATS auto-balances across them
- The iris-engine is **stateless** — no templates stored in-process. It receives a probe image and gallery templates, returns match results

### Why This Split

**Scaling independently:**
- 10 capture devices sending frames? Scale `iris-engine` horizontally (stateless, compute-bound)
- Matching against large DB? `iris-engine` replicas each get gallery templates from `template-db`
- Storage slow? Scale `storage` replicas (writes are async, non-blocking)

**Deploy where it makes sense:**

```
Scenario A: All on-prem (Jetson Xavier)
  All 6 containers on one Jetson. Lowest latency. Simple.

Scenario B: Hybrid edge + cloud
  gateway + iris-engine → cloud VM (GPU: AWS g4dn / GCP T4, or CPU-only)
  template-db + storage + object-store → on-prem (data stays local)

Scenario C: Full cloud
  All containers on Kubernetes. Capture RPis connect over VPN/WAN.
  Higher latency (~50-100ms network) but zero on-prem compute.

Scenario D: Edge-heavy (air-gapped)
  All containers on a local Jetson via Docker Compose. No internet needed.
  RPi connects over local network only.
```

### Inter-Service Communication

With the collapsed architecture, there are far fewer hops:

```
capture ──gRPC──▶ gateway ──NATS──▶ iris-engine ──NATS──▶ gateway ──WebSocket──▶ browser
                     │                    │
                     │                    └──NATS──▶ storage (async, non-blocking)
                     │
                     └──NATS──▶ template-db (enrollment, template load)
```

Only **3 NATS hops** in the critical path (gateway → iris-engine → gateway), down from 5+ with the split architecture.

### Container Images

```dockerfile
# iris-engine/Dockerfile — multi-target: GPU (CUDA) or CPU-only
# Build with: docker build --build-arg RUNTIME=cpu .   (Mac, CI, non-GPU machines)
#             docker build --build-arg RUNTIME=cuda .  (Linux + NVIDIA GPU)

ARG RUNTIME=cpu

FROM nvidia/cuda:12.6.3-runtime-debian12 AS base-cuda
FROM debian:trixie-slim AS base-cpu
FROM base-${RUNTIME} AS base

RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*

# CPU build uses ONNX Runtime (lighter, no CUDA dependency)
# CUDA build uses PyTorch + ONNX Runtime with CUDA provider
RUN if [ "$RUNTIME" = "cuda" ]; then \
      pip install open-iris nats-py uvicorn fastapi torch onnxruntime-gpu; \
    else \
      pip install open-iris nats-py uvicorn fastapi onnxruntime; \
    fi

# Pretrained segmentation model (cached in image)
RUN python3 -c "from huggingface_hub import hf_hub_download; \
    hf_hub_download('Worldcoin/iris-semantic-segmentation', 'model.onnx')"

COPY src/ /app/
WORKDIR /app
ENV EYED_RUNTIME=${RUNTIME}
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

```dockerfile
# gateway/Dockerfile
FROM debian:bookworm AS build
RUN apt-get update && apt-get install -y cmake ninja-build g++ git \
    libgrpc++-dev libprotobuf-dev protobuf-compiler protobuf-compiler-grpc \
    nlohmann-json3-dev libboost-dev libboost-system-dev libssl-dev
COPY gateway/ /src/ && cd /src && cmake -S . -B build -G Ninja && cmake --build build
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libgrpc++1.51 libprotobuf32 libboost-system1.81.0
COPY --from=build /src/build/gateway /app/gateway
EXPOSE 50051 8080
CMD ["/app/gateway"]
```

Each service runs in its own container. The iris-engine supports **two build targets**:

| Build | Command | When to use |
|-------|---------|-------------|
| CPU-only | `docker build --build-arg RUNTIME=cpu` | Mac development, CI, non-GPU servers |
| CUDA | `docker build --build-arg RUNTIME=cuda` | Linux production with NVIDIA GPU |

Container images:

| Image | Base | Size | Accelerator |
|-------|------|------|-------------|
| eyed-capture | arm64v8/debian:trixie-slim + OpenCV + gRPC | ~120MB | None (ARM64 RPi) |
| eyed-gateway | debian:bookworm-slim + C++ binary (static nats.c) | ~75MB | None |
| eyed-iris-engine (cuda) | nvidia/cuda:12-debian + Python + Open-IRIS + ORT-GPU | ~2.5GB | NVIDIA CUDA |
| eyed-iris-engine (cpu) | debian:trixie-slim + Python + Open-IRIS + ORT | ~400MB | None (CPU-only) |
| eyed-web-ui | nginx:stable (static SPA) | ~30MB | None |
| eyed-storage | debian:trixie-slim + Python + S3 client + NATS | ~150MB | None |
| template-db | postgres:18 (official image) | ~400MB | None |
| object-store | chrislusf/seaweedfs (official image) | ~50MB | None |
| redis | redis:7-alpine (official image) | ~15MB | None |
| nats | nats:2.12 (official image) | ~20MB | None |

The CPU-only iris-engine is **much smaller** (~400MB vs ~2.5GB) because it drops the CUDA runtime and uses ONNX Runtime instead of PyTorch. Inference is slower (~100ms vs ~15ms for segmentation) but fully functional for development and testing.

### docker-compose (Development / Single-host)

Two compose files: one base (works everywhere, CPU-only) and one GPU override (Linux + NVIDIA).

```yaml
# docker-compose.yml - Works on Mac, Linux, CI (no GPU required)

services:
  nats:
    image: nats:2.12
    ports:
      - "4222:4222"
    command: --config /etc/nats/nats-server.conf
    volumes:
      - ./config/nats-server.conf:/etc/nats/nats-server.conf:ro

  gateway:
    build: ./docker/gateway
    ports:
      - "50050:50050"       # Capture devices connect here (gRPC)
      - "8080:8080"         # WebSocket + WebRTC signaling
    depends_on: [nats]
    environment:
      NATS_URL: nats://nats:4222

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]

  iris-engine:
    build:
      context: ./docker/iris-engine
      args:
        RUNTIME: cpu              # Default: CPU-only (works on Mac/Linux)
    depends_on: [nats, template-db, redis]
    environment:
      NATS_URL: nats://nats:4222
      TEMPLATE_DB_URL: postgresql://template-db:5432/eyed
      EYED_REDIS_URL: redis://redis:6379/0
      EYED_RUNTIME: cpu
      OMP_NUM_THREADS: "2"

  web-ui:
    build: ./docker/web-ui
    ports:
      - "3000:80"
    depends_on: [gateway]

  storage:
    build: ./docker/storage
    depends_on: [nats, object-store]
    environment:
      NATS_URL: nats://nats:4222
      S3_ENDPOINT: http://object-store:8333

  template-db:
    image: postgres:18
    volumes:
      - template-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: eyed
      POSTGRES_USER: eyed
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets: [db_password]

  object-store:
    image: chrislusf/seaweedfs:latest
    command: server -s3 -dir=/data
    ports:
      - "8333:8333"
    volumes:
      - object-data:/data

volumes:
  template-data:
  object-data:

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

```yaml
# docker-compose.gpu.yml - GPU override (Linux + NVIDIA only)
# Usage: docker compose -f docker-compose.yml -f docker-compose.gpu.yml up

services:
  iris-engine:
    build:
      args:
        RUNTIME: cuda
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
      replicas: 2             # Scale GPU workers
    environment:
      EYED_RUNTIME: cuda
```

**Usage:**
```bash
# Mac / CI / any machine (CPU-only, ~100ms inference)
docker compose up

# Linux + NVIDIA GPU (CUDA, ~15ms inference)
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up
```

### Kubernetes (Production / Cloud)

```yaml
# k8s/iris-engine-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: eyed-iris-engine
spec:
  replicas: 2                    # Scale GPU workers
  selector:
    matchLabels:
      app: eyed-iris-engine
  template:
    spec:
      containers:
      - name: iris-engine
        image: eyed-iris-engine:latest
        resources:
          limits:
            nvidia.com/gpu: 1    # Request GPU
          requests:
            memory: "2Gi"
            cpu: "1000m"
        ports:
        - containerPort: 8000
        env:
        - name: NATS_URL
          value: "nats://nats:4222"
```

Scale with `kubectl scale deployment eyed-iris-engine --replicas=4` when load increases.

### Latency Impact of Containerization

| Deployment | Inter-service overhead | Total pipeline |
|-----------|----------------------|----------------|
| docker-compose (same host) | ~1-2ms per hop (2 hops) | ~47ms |
| Kubernetes (same cluster) | ~2-3ms per hop | ~50ms |
| Cloud (same region) | ~5-10ms per hop | ~65ms |
| Cloud (cross-region) | ~20-50ms per hop | Not viable for real-time |

**Only 2 NATS hops** in the critical path (gateway → iris-engine → gateway), so containerization overhead is minimal. The ~43ms of actual compute in iris-engine dominates.

### Collapsing Services for Edge

On a resource-constrained Jetson, the full Docker Compose stack still runs fine (only 6 containers). But for truly minimal setups:

```
Full (cloud/large server):
  nats → gateway → iris-engine (N replicas) → template-db → object-store → storage → web-ui

Minimal edge (Jetson Nano):
  nats → gateway → iris-engine (1 replica) → template-db (SQLite) → web-ui
  (storage + object-store optional, skip raw archival)
```

All deployments use Docker. Even the minimal edge setup runs as `docker compose -f docker-compose.edge.yml up`. No bare-metal binaries.

### Development Environment (Mac / Non-GPU)

The primary development machine is a **Mac** (Apple Silicon). No NVIDIA GPU, no CUDA. The entire stack runs on Docker Desktop for Mac using CPU-only containers:

```bash
# Start the full stack on Mac (CPU-only, no GPU flags)
docker compose up

# iris-engine uses ONNX Runtime CPUExecutionProvider
# Segmentation: ~100ms (vs ~15ms on CUDA) — fine for development
# Full pipeline: ~130ms per frame — plenty fast for testing
```

**What works on Mac:**
- All 6 services run identically (same containers, same code)
- iris-engine uses the same `.onnx` model file, just a different ONNX Runtime provider
- WebRTC, NATS, PostgreSQL, SeaweedFS — all platform-independent
- Integration tests, enrollment flow, matching — all functional

**What's different on Mac:**
- iris-engine inference is ~7x slower (CPU vs CUDA). Doesn't matter for dev/test
- No GPU memory monitoring (health check skips CUDA check when `EYED_RUNTIME=cpu`)
- Docker images are `linux/amd64` or `linux/arm64` (Rosetta 2 or native ARM on M-series)

**Optional: Apple Silicon acceleration**

ONNX Runtime supports CoreML on macOS, which uses the Apple Neural Engine for faster inference (~30-50ms vs ~100ms CPU). This is optional — CPU mode is the default and works fine:

```python
# iris-engine auto-selects provider based on EYED_RUNTIME env var:
#   "cuda"  → CUDAExecutionProvider
#   "cpu"   → CPUExecutionProvider
#   "coreml" → CoreMLExecutionProvider (macOS only, optional)
import onnxruntime as ort
providers = {
    "cuda":   ["CUDAExecutionProvider"],
    "coreml": ["CoreMLExecutionProvider", "CPUExecutionProvider"],
    "cpu":    ["CPUExecutionProvider"],
}
session = ort.InferenceSession("model.onnx", providers=providers[runtime])
```

**Development setup summary:**

| Environment | Command | iris-engine speed | Use case |
|------------|---------|------------------|----------|
| Mac (default) | `docker compose up` | ~100ms (CPU) | Daily development |
| Mac + CoreML | `EYED_RUNTIME=coreml docker compose up` | ~30-50ms (ANE) | Faster local iteration |
| Linux + GPU | `docker compose -f docker-compose.yml -f docker-compose.gpu.yml up` | ~15ms (CUDA) | Production / staging |
| CI | `docker compose up` | ~100ms (CPU) | Automated tests |

### Inter-Service Messaging: NATS

For communication **between containers**, use **NATS** instead of gRPC. gRPC stays only for the capture device → gateway edge (request/response over WAN). Inside the cluster, NATS is lighter and fits the pipeline pattern better.

**Why NATS over gRPC between services:**

| Aspect | gRPC (service-to-service) | NATS |
|--------|--------------------------|------|
| Overhead per message | ~1ms (HTTP/2 + protobuf) | ~0.1ms (TCP + raw bytes) |
| Connection model | Point-to-point stubs | Pub/sub, queues, request/reply |
| Service discovery | Manual (hardcode addresses) | Built-in (subjects = routing) |
| Load balancing | Client-side or proxy | Built-in queue groups |
| Binary size | ~15MB (gRPC + protobuf libs) | ~2MB (nats.c client) |
| Scaling a service | Update all callers | Just add replicas, NATS auto-balances |

**Message flow using NATS subjects:**

```
capture ──gRPC──▶ gateway ──NATS──▶ iris-engine ──NATS──▶ gateway ──WebSocket──▶ browser
                                         │
                                         └──NATS──▶ storage (async)

NATS subjects:
  eyed.analyze       → iris-engine picks up frames for analysis
  eyed.enroll        → iris-engine picks up frames for enrollment
  eyed.result        → gateway picks up analysis results
  eyed.archive       → storage picks up archival requests (async)
  eyed.templates.*   → template-db notifications (changed, loaded)
```

**NATS queue groups for auto-scaling:**
```
# 3 iris-engine replicas, NATS load-balances automatically
iris-engine-1  ──subscribe──▶ eyed.analyze (queue: "engines")
iris-engine-2  ──subscribe──▶ eyed.analyze (queue: "engines")
iris-engine-3  ──subscribe──▶ eyed.analyze (queue: "engines")

# Gateway publishes to eyed.analyze, NATS delivers to ONE replica
```

No service discovery, no load balancer config, no sidecar proxies. Just `docker compose up --scale iris-engine=3`.

**Message format:** Flatbuffers (zero-copy deserialization, ~10x faster than protobuf for image data)

```
// Frame message (~30KB for JPEG + metadata)
table CaptureFrame {
    jpeg_data: [ubyte];
    quality_score: float;
    timestamp_us: uint64;
    frame_id: uint32;
    device_id: string;
}

// Result message (~200 bytes)
table AnalysisResult {
    frame_id: uint32;
    hamming_distance: float;
    is_match: bool;
    matched_id: string;
    pupil_x: float;
    pupil_y: float;
    pupil_r: float;
    iris_x: float;
    iris_y: float;
    iris_r: float;
    latency_ms: uint32;
}
```

### Health Checks & Observability

Each service exposes health and readiness endpoints:

```cpp
// Every service implements this interface
class IHealthCheck {
public:
    struct Status {
        bool alive;             // Process is running
        bool ready;             // Can accept work (models loaded, NATS connected)
        std::string version;
        uint64_t uptime_sec;
        uint32_t processed_count;
        float avg_latency_ms;
        std::string error;      // Empty if healthy
    };

    virtual Status health() = 0;
};
```

**Health check mechanisms:**

| Check | Method | Frequency | Action on failure |
|-------|--------|-----------|-------------------|
| **Liveness** | HTTP GET `/health/alive` | Every 10s | Container restart |
| **Readiness** | HTTP GET `/health/ready` | Every 5s | Remove from NATS queue group |
| **NATS connection** | Heartbeat on `eyed.heartbeat.<service>` | Every 5s | Reconnect / alert |
| **Accelerator** | Runtime check: CUDA / CoreML / CPU (iris-engine) | On startup + every 60s | Log provider, fallback to CPU if GPU lost |
| **Model loaded** | Check model file hash | On startup | Refuse to start |
| **Template DB** | SQLite ping | Every 30s | Reconnect / alert |

**Docker health checks:**
```yaml
# In each service's Dockerfile
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/health/alive || exit 1
```

**Kubernetes probes:**
```yaml
livenessProbe:
    httpGet:
        path: /health/alive
        port: 8080
    initialDelaySeconds: 5
    periodSeconds: 10
readinessProbe:
    httpGet:
        path: /health/ready
        port: 8080
    initialDelaySeconds: 10
    periodSeconds: 5
```

**Service status dashboard (gateway aggregates):**

```
GET /status → returns:

{
    "services": {
        "iris-engine":  { "alive": true, "ready": true, "replicas": 2, "avg_ms": 43.2 },
        "gateway":      { "alive": true, "ready": true, "replicas": 1 },
        "storage":      { "alive": true, "ready": true, "replicas": 1 },
        "template-db":  { "alive": true, "ready": true, "templates": 1247 },
        "web-ui":       { "alive": true, "ready": true, "replicas": 1 }
    },
    "capture_devices": {
        "rpi-entrance-01": { "connected": true, "fps": 4.2, "last_seen": "2s ago" },
        "rpi-entrance-02": { "connected": true, "fps": 3.8, "last_seen": "1s ago" }
    },
    "pipeline": {
        "avg_latency_ms": 52,
        "frames_processed": 142857,
        "uptime": "3d 14h 22m"
    }
}
```

**Metrics (optional, Prometheus-compatible):**
Each service exposes `/metrics` for scraping:
- `eyed_frames_processed_total` (counter)
- `eyed_processing_duration_seconds` (histogram)
- `eyed_queue_depth` (gauge, NATS subject backlog)
- `eyed_match_rate` (gauge, matches per minute)
- `eyed_quality_rejection_rate` (gauge, frames rejected by quality gate)

### Circuit Breaker

If a downstream service is unhealthy, upstream services degrade gracefully:

```
Gateway detects: iris-engine not responding for 3 consecutive requests
  → Opens circuit breaker for iris-engine
  → Returns "service degraded" via WebSocket to browser
  → Browser shows "analysis unavailable" on dashboard
  → Gateway retries every 10s
  → When iris-engine recovers → close circuit → resume pipeline
```

Implemented as a lightweight state machine, no external library needed:

```cpp
enum class CircuitState { CLOSED, OPEN, HALF_OPEN };

class CircuitBreaker {
    CircuitState state_ = CircuitState::CLOSED;
    int failure_count_ = 0;
    int failure_threshold_ = 3;
    std::chrono::seconds retry_after_{10};
    std::chrono::steady_clock::time_point last_failure_;
};
```

---

## 8. Algorithm Engine: Open-IRIS

The entire Masek pipeline is **replaced** by Open-IRIS (Worldcoin, MIT license). No BiometricLib code remains in the recognition path.

### Why Open-IRIS

| What Masek did | What Open-IRIS does better | Improvement |
|---------------|---------------------------|-------------|
| Haar cascade eye detection (~50ms) | MobileNetV2+UNet++ segmentation (~15ms GPU) | 3x faster, vastly more accurate |
| Hough circles for pupil/iris (IoU ~35%) | DNN 4-class semantic segmentation (IoU 94.3%) | **2.7x IoU improvement** |
| Curve fitting for eyelids (~1-2 min) | Included in DNN segmentation pass (~0ms extra) | **Eliminated** |
| 1D Log-Gabor, 1 scale, ~2K bits | 2D Gabor, multiple scales, >10K bits | 5x more discriminative |
| Hamming distance (no noise masking) | Masked fractional Hamming distance | Better handling of occlusion |
| FNMR ~17-27% @ FMR=0.001 | **FNMR 0.12% @ FMR=0.001** | **150x better accuracy** |

### Open-IRIS Architecture

```
Input: eye image (any size)
  │
  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Segmentation (MobileNetV2 + UNet++ with scSE attention)            │
│                                                                     │
│  Pretrained model: HuggingFace Worldcoin/iris-semantic-segmentation │
│  4 classes: eyeball, iris, pupil, eyelashes                         │
│  IoU: 0.943                                                         │
│  ~15ms (GPU) / ~100ms (CPU)                                         │
│                                                                     │
│  Outputs:                                                           │
│   - Iris/pupil boundaries (ellipse fit from mask)                   │
│   - Noise mask (eyelash + occlusion pixels)                         │
│   - Segmentation confidence                                         │
└────────────────┬────────────────────────────────────────────────────┘
                 │
                 ▼
┌───────────────────────────────────────────────────────────────┐
│  Normalization (Daugman rubber sheet model)                   │
│  Same math as Masek, better implementation                    │
│  Polar unwrap: iris annulus → normalized rectangular strip    │
│  ~5ms (CPU)                                                   │
└────────────────┬──────────────────────────────────────────────┘
                 │
                 ▼
┌───────────────────────────────────────────────────────────────┐
│  Encoding (2D Gabor filter bank)                              │
│  Multiple spatial scales and orientations                     │
│  Output: >10,000 bit binary iris code + noise mask            │
│  ~20ms (CPU)                                                  │
└────────────────┬──────────────────────────────────────────────┘
                 │
                 ▼
┌───────────────────────────────────────────────────────────────┐
│  Matching (Masked fractional Hamming distance)                │
│  Rotation-compensated, noise-mask-aware                       │
│  Score: 0.0 (identical) to 0.5 (uncorrelated)                 │
│  ~1ms per comparison                                          │
└───────────────────────────────────────────────────────────────┘
```

### Open-IRIS 1.11.0 Features (vs 1.9)

| Feature | Description | Impact |
|---------|-------------|--------|
| **Image denoising** | Bilateral filter before segmentation (enabled by default) | Improved accuracy on noisy captures |
| **16-bit ONNX support** | Auto-detects FP16 models for faster inference | ~2x speedup on FP16-capable hardware |
| **Image ID tracing** | `IRImage.image_id` flows through pipeline and into metadata | End-to-end frame traceability |
| **Improved ellipse geometry** | LSQEllipseFitWithRefinement returns None for invalid geometry | Fewer false segmentations |
| **Better fusion extrapolation** | Relative std-based circle/ellipse switching (threshold 0.014 vs old 3.5) | More robust boundary estimation |
| **Deterministic multiprocessing** | Local RandomState instead of global seed | Reproducible results across workers |
| **Robust orientation estimation** | `arctan2`-based, no edge-case branches | More reliable eye orientation |
| **Simplified occlusion calculator** | Direct Cartesian coordinates (removed polar conversion) | Faster, simpler quality metrics |

**API changes from 1.9:**
- `IRISPipeline(config=...)` — `config` parameter, not `device`
- `IRImage(img_data=..., eye_side=..., image_id=...)` — new `image_id` field
- `pipeline(ir_image)` returns `dict` with keys: `error`, `iris_template`, `metadata`
- `IrisTemplate.deserialize(serialized_dict)` replaces removed `recombine_iris_template()`
- `pipeline.call_trace` — callback ordering fixed (trace written before other callbacks)

### Iris Engine Service (Docker Container)

The iris-engine is a **Python service** wrapping Open-IRIS, running inside Docker. It supports two build targets via `RUNTIME` build arg:

```dockerfile
# docker/iris-engine/Dockerfile
# Build: docker build --build-arg RUNTIME=cpu .   (Mac, CI)
#        docker build --build-arg RUNTIME=cuda .  (Linux + NVIDIA GPU)
ARG RUNTIME=cpu
FROM nvidia/cuda:12.6.3-runtime-debian12 AS base-cuda
FROM debian:trixie-slim AS base-cpu
FROM base-${RUNTIME} AS base

RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*

# CPU: ONNX Runtime only (~400MB image). CUDA: ORT-GPU + PyTorch (~2.5GB image)
ARG RUNTIME
RUN if [ "$RUNTIME" = "cuda" ]; then \
      pip install open-iris nats-py uvicorn fastapi torch onnxruntime-gpu; \
    else \
      pip install open-iris nats-py uvicorn fastapi onnxruntime; \
    fi

# Pretrained segmentation model (cached in image, same .onnx for both targets)
RUN python3 -c "from huggingface_hub import hf_hub_download; \
    hf_hub_download('Worldcoin/iris-semantic-segmentation', 'model.onnx')"

COPY src/ /app/
WORKDIR /app
ENV EYED_RUNTIME=${RUNTIME}

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

```python
# iris-engine/src/pipeline.py (simplified)
import iris

# Lazy-loaded singleton pipeline (config=None for CPU default)
pipeline = iris.IRISPipeline(config=config)

def analyze(img_data, eye_side="left", image_id=None):
    """Run the full Open-IRIS 1.11.0 pipeline on a grayscale eye image."""
    ir_image = iris.IRImage(img_data=img_data, eye_side=eye_side, image_id=image_id)
    result = pipeline(ir_image)  # returns dict
    # result keys: "error", "iris_template" (IrisTemplate or None), "metadata"
    return result

def match(probe_template, gallery_template):
    """Match two iris templates using Hamming distance."""
    matcher = iris.HammingDistanceMatcher(rotation_shift=15, normalise=True)
    distance = matcher.run(template_probe=probe_template, template_gallery=gallery_template)
    return distance  # float in [0.0, 1.0], < 0.39 = match
```

### Model Variants & Runtime Performance

The same `.onnx` model file works across all runtimes — only the ONNX Runtime execution provider changes:

| Runtime | Execution Provider | Segmentation | Where |
|---------|-------------------|-------------|-------|
| CUDA (Linux + NVIDIA) | `CUDAExecutionProvider` | ~15ms | Production servers, Jetson |
| CPU (any OS) | `CPUExecutionProvider` | ~100ms | Mac dev, CI, non-GPU servers |
| CoreML (macOS) | `CoreMLExecutionProvider` | ~30-50ms | Mac dev with Apple Silicon acceleration |
| TensorRT (Jetson) | `TensorRTExecutionProvider` | ~8ms | Optimized edge deployment |

**CoreML on Mac:** ONNX Runtime supports CoreML as an execution provider, which uses the Apple Neural Engine on M-series chips. Not required — CPU mode works fine for development — but available if you want faster local iteration:

```bash
# Optional: install CoreML provider for faster Mac development
pip install onnxruntime-silicon   # or: pip install onnxruntime with CoreML support
```

| Model | Size | CUDA | CPU | Use Case |
|-------|------|------|-----|----------|
| Open-IRIS default (MobileNetV2+UNet++) | ~14MB | ~15ms | ~100ms | Production (default) |
| Open-IRIS quantized (INT8) | ~4MB | ~8ms | ~50ms | Edge / Jetson |
| Custom fine-tuned (on your data) | ~14MB | ~15ms | ~100ms | After collecting training data |

### Training Data (for future fine-tuning)

| Dataset | Images | Use |
|---------|--------|-----|
| CASIA-Iris-Interval | 2,639 | Baseline validation (already referenced in project) |
| CASIA-Iris-Thousand | 20,000 | Diversity validation |
| ND-IRIS-0405 | 64,980 | Large-scale validation |
| UBIRIS v2 | 11,102 | Visible light iris (augmentation) |
| **Your own captured data** | Accumulates over time | Fine-tune segmentation for your cameras/environment |

Open-IRIS ships with a pretrained model. You only need to retrain if accuracy degrades on your specific camera/lighting setup. The storage service archives raw data for this purpose.

---

## 9. Storage Architecture

The pipeline produces data at every stage. Storage is split by **access pattern** and **purpose**, each handled by a dedicated service with a single responsibility.

### What Gets Stored

```
Frame arrives from capture device
    │
    ▼
┌──────────────┐   raw image + metadata
│  storage     │──────────────────────────────▶ OBJECT STORE (cold)
│  service     │                                 /raw/{date}/{device}/{frame_id}.jpg
│              │                                 /raw/{date}/{device}/{frame_id}.meta.json
│  (archiver + │
│   dedup      │   segmentation mask + circles
│   checker)   │──────────────────────────────▶ OBJECT STORE (cold)
│              │                                 /artifacts/{date}/{frame_id}/mask.png
│              │                                 /artifacts/{date}/{frame_id}/seg.json
│              │
│              │   iris template + noise mask
│              │──────────────────────────────▶ TEMPLATE DB (hot)
│              │                                 templates table
│              │
│              │   match log entry
│              │──────────────────────────────▶ TEMPLATE DB (hot)
│              │                                 match_log table
└──────────────┘
```

### Storage Tiers

| Tier | Store | Data | Access Pattern | Retention |
|------|-------|------|---------------|-----------|
| **Hot** | Template DB (PostgreSQL / SQLite) | Iris templates, enrollment metadata, match logs | Real-time read, 1:N search | Permanent |
| **Warm** | Object Store (SeaweedFS / local FS) | Segmentation artifacts, quality reports | On-demand read for debugging | 90 days default |
| **Cold** | Object Store (SeaweedFS / S3) | Raw captured images, pipeline snapshots | Batch read for training export | Years (configurable) |

### 9.1 Template DB (Hot Storage)

Holds everything needed for real-time iris matching. This is the only store in the critical path.

**Technology:** PostgreSQL (cloud/multi-device) or SQLite (edge/single-host)

**Encryption at rest:** Iris template BYTEA columns (`iris_codes`, `mask_codes`) are encrypted with **AES-256-GCM** at the application level before INSERT, and decrypted on SELECT. The encryption key (`EYED_ENCRYPTION_KEY`) is a 32-byte key stored outside the database (environment variable or secrets manager). A database leak or unauthorized SELECT returns only ciphertext. The encrypted blob format is `EYED1 || nonce(12B) || ciphertext || GCM-tag(16B)`. Legacy unencrypted data (NPZ blobs starting with `PK\x03\x04`) is detected and passed through transparently, enabling seamless migration. The same encryption applies to the Redis write-through cache used during bulk enrollment.

**Schema:**

```sql
-- Enrolled identities
CREATE TABLE identities (
    identity_id     UUID PRIMARY KEY,
    name            TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata        JSONB           -- Extensible: department, access level, etc.
);

-- Iris templates (one identity can have multiple enrollments)
CREATE TABLE templates (
    template_id     UUID PRIMARY KEY,
    identity_id     UUID NOT NULL REFERENCES identities(identity_id),
    eye_side        TEXT NOT NULL CHECK (eye_side IN ('left', 'right')),
    code            BYTEA NOT NULL,  -- Packed binary iris code
    mask            BYTEA NOT NULL,  -- Packed noise mask
    width           INT NOT NULL,
    height          INT NOT NULL,
    n_scales        INT NOT NULL,
    quality_score   REAL NOT NULL,   -- Quality at enrollment time
    device_id       TEXT,            -- Which capture device
    is_nir          BOOLEAN,         -- Camera type
    enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    raw_image_ref   TEXT             -- Path in object store: /raw/.../frame.jpg
);

-- Match audit log (every comparison, not just matches)
CREATE TABLE match_log (
    log_id          BIGSERIAL PRIMARY KEY,
    probe_frame_id  TEXT NOT NULL,       -- Incoming frame identifier
    matched_template_id UUID REFERENCES templates(template_id),
    hamming_distance    REAL NOT NULL,
    is_match            BOOLEAN NOT NULL,
    best_shift_x        INT,
    best_shift_y        INT,
    device_id           TEXT,
    latency_ms          INT,
    matched_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for 1:N matching (load all active templates into memory)
CREATE INDEX idx_templates_active ON templates(identity_id, eye_side);

-- Index for audit queries
CREATE INDEX idx_match_log_time ON match_log(matched_at);
CREATE INDEX idx_match_log_identity ON match_log(matched_template_id);
```

**1:N Matching flow:**

```
New frame arrives → iris-engine produces template
    │
    ▼
iris-engine loads ALL enrolled templates from template-db (cached in memory)
    │
    ▼
Compare probe against each enrolled template (fractional Hamming distance)
    │
    ├── HD < 0.39 for template X → MATCH (identity found)
    │     └── Log to match_log
    │
    └── HD >= 0.39 for ALL templates → NO MATCH (unknown person)
          └── Log to match_log (matched_template_id = NULL)
```

**Template cache strategy:**
- On startup: load all templates into memory (~1KB per template, 10K enrollments = ~10MB)
- On enrollment: add to cache + persist to DB
- Periodic sync: every 60s, check for new enrollments from other nodes
- Cache invalidation: NATS notification on `eyed.templates.changed`

### 9.2 Object Store (Warm + Cold Storage)

Holds raw images, segmentation artifacts, and pipeline snapshots for future training and auditing.

**Technology:** SeaweedFS (self-hosted S3-compatible, Apache 2.0) or local filesystem (edge)

**Bucket/directory layout:**

```
eyed-data/
├── raw/                                    # COLD - Raw captured images
│   └── {YYYY-MM-DD}/
│       └── {device_id}/
│           ├── {frame_id}.jpg              # Original JPEG from capture device
│           └── {frame_id}.meta.json        # Capture metadata
│
├── artifacts/                              # WARM - Pipeline outputs
│   └── {YYYY-MM-DD}/
│       └── {frame_id}/
│           ├── eye_crop.png                # Cropped eye region
│           ├── segmentation_mask.png       # 4-class DNN output
│           ├── normalized_iris.png         # Polar-unwrapped strip (34x260)
│           ├── pipeline.json               # Full pipeline trace
│           └── circles.json                # Pupil/iris circle parameters
│
├── enrollments/                            # COLD - Enrollment snapshots
│   └── {identity_id}/
│       ├── {template_id}_raw.jpg           # Best image used for enrollment
│       ├── {template_id}_template.bin      # Iris code + mask binary
│       └── {template_id}_meta.json         # Enrollment metadata
│
└── training-export/                        # COLD - Training dataset exports
    └── {export_id}/
        ├── manifest.json                   # Dataset description
        ├── images/                         # Curated images
        └── masks/                          # Ground truth segmentation masks
```

**Metadata file example (`{frame_id}.meta.json`):**
```json
{
    "frame_id": "f-20260218-143022-001",
    "device_id": "rpi-entrance-01",
    "timestamp": "2026-02-18T14:30:22.451Z",
    "camera": {
        "type": "nir",
        "resolution": [640, 480],
        "exposure_us": 8000,
        "gain": 1.5
    },
    "quality_score": 0.42,
    "pipeline_result": {
        "eyes_detected": true,
        "iris_segmented": true,
        "segmentation_confidence": 0.91,
        "hamming_distance": 0.28,
        "is_match": true,
        "matched_identity": "id-a1b2c3",
        "latency_ms": 88
    },
    "storage_refs": {
        "eye_crop": "artifacts/2026-02-18/f-20260218-143022-001/eye_crop.png",
        "segmentation_mask": "artifacts/2026-02-18/f-20260218-143022-001/segmentation_mask.png",
        "normalized_iris": "artifacts/2026-02-18/f-20260218-143022-001/normalized_iris.png"
    }
}
```

### 9.3 Deduplication Check

Before enrolling a new identity, check if this iris already exists in the database:

```
Enrollment request arrives (raw eye image)
    │
    ▼
Run full Open-IRIS pipeline: segment → normalize → encode → produce template
    │
    ▼
iris-engine: compare probe template against ALL enrolled templates
    │
    ├── HD < 0.32 (strict threshold, tighter than match)
    │     └── DUPLICATE FOUND → reject enrollment, return existing identity
    │
    └── HD >= 0.32 for all templates
          └── NEW IRIS → proceed with enrollment
              ├── Store template → template-db
              ├── Store raw image → object-store/enrollments/
              └── Notify: NATS eyed.templates.changed
```

**Why 0.32 instead of 0.39:**
- Match threshold (0.39): "is this probably the same person?" - allows some noise
- Dedup threshold (0.32): "is this definitely the same iris?" - stricter to avoid false enrollments

### 9.3.1 Bulk Enrollment

For batch enrollment of entire datasets (e.g. CASIA-Iris-Thousand with 1000 subjects), the system provides a **server-side bulk enrollment endpoint** that reads images directly from disk — no base64 over HTTP for each image.

**Endpoint:** `POST /enroll/batch` — returns an SSE (Server-Sent Events) stream.

**Directory structure convention:**
```
dataset/
  000/              ← subject directory (identity name = "000")
    L/              ← left eye
      S5000L01.jpg  ← first sorted image is enrolled
      S5000L02.jpg
    R/              ← right eye
      S5000R01.jpg
      S5000R02.jpg
  001/
    L/...
    R/...
```

For each subject, the **first sorted image** per eye side (L/R) is enrolled. This convention ensures that tests and benchmarks can avoid the enrolled images by skipping the first image.

**SSE streaming protocol:**
```
data: {"subject_id":"000","eye_side":"left","filename":"S5000L01.jpg","identity_id":"CASIA-Iris-Thousand:000","template_id":"abc-123",...}\n\n
data: {"subject_id":"000","eye_side":"right","filename":"S5000R01.jpg","identity_id":"CASIA-Iris-Thousand:000","template_id":"def-456",...}\n\n
...
event: done
data: {"total":2000,"enrolled":1995,"duplicates":3,"errors":2}\n\n
```

**Architecture: Pipeline Pool + Redis Write-Through Cache**

```
POST /enroll/batch
     │
     ▼
[Build work list from dataset]
     │
     ▼
[ThreadPoolExecutor(workers=3)]
     │
  ┌──┼──┐
  ▼  ▼  ▼   each thread:
 [decode_jpeg_bytes]          ← parallel (file I/O)
  │  │  │
  ▼  ▼  ▼
 [pool.acquire()]             ← borrow pipeline instance (no global lock)
  │  │  │
  ▼  ▼  ▼
 [analyze(pipeline_instance)] ← TRUE parallelism (each has own ONNX session)
  │  │  │
  ▼  ▼  ▼
 [pool.release()]
  │  │  │
  ▼  ▼  ▼
 [gallery.check_duplicate / enroll]  ← thread-safe (internal lock)
  └──┼──┘
     ▼  (back in asyncio loop)
 [SSE emit result]
 [Redis RPUSH template data]  ← sub-ms

         Meanwhile, independently:
 [EnrollmentDrainWriter]
     │ every 1s
     ▼
 [Redis LRANGE+LTRIM batch of 50]
     │
     ▼
 [pool.executemany() → Postgres]
```

**Pipeline pool** (`pipeline_pool.py`): N pre-loaded IRISPipeline instances (default 3) stored in a `queue.Queue`. Each instance owns its own ONNX session and intermediate state, so concurrent calls from different threads are safe. Workers call `acquire()` to borrow one and `release()` to return it. `OMP_NUM_THREADS` is set to `cpu_count / pool_size` at load time to prevent ONNX intra-op thread oversubscription.

**Redis write-through cache** (`redis_cache.py`): Enrollment data is pushed to a Redis LIST (`eyed:enroll:pending`) via `RPUSH` (sub-ms). A background `EnrollmentDrainWriter` (`db_drain.py`) polls every 1s, atomically pops batches of 50 via `LRANGE + LTRIM`, and writes to Postgres using `executemany()`. This decouples the SSE hot path from slow DB writes.

**Fallback:** When Redis is not configured (`EYED_REDIS_URL=""`), the endpoint falls back to direct DB writes inline. The pipeline pool still provides parallelism.

**Performance:**

| Metric | Sequential (1 thread) | Pipeline Pool (3 threads) |
|--------|----------------------|--------------------------|
| Pipeline throughput | 1 image at a time | 3 images in parallel |
| 100 images total | ~50s | ~17s (~3x faster) |
| DB write per image | ~10-50ms (inline INSERT) | ~0.1ms (Redis RPUSH) |
| DB persistence | Inline (blocks SSE) | Background batch (invisible) |
| Startup cost | None | +6-12s one-time (pool pre-load) |
| Memory | Baseline | +150-300MB (3 ONNX sessions) |

**Design decisions:**
- **Server-side reads:** iris-engine reads JPEG from disk directly via `img_path.read_bytes()`, avoiding 2000 × base64-encode → HTTP → base64-decode round-trips.
- **Single NATS notification:** One `eyed.templates.changed` event at the end of the batch (not per-enrollment), preventing 2000 debounced reloads on other nodes.
- **Pipeline pool for true parallelism:** Each worker thread borrows its own IRISPipeline instance — no global lock, no serialization. Thread count matches pool size (default 3).
- **Dedup check per image:** Same `gallery.check_duplicate()` as single enrollment. Gallery operations are thread-safe (internal lock). Each newly enrolled template is immediately visible to subsequent dedup checks.
- **Redis cache for fast persistence:** Workers push to Redis (sub-ms) and immediately emit SSE. A separate drain writer batches inserts to Postgres asynchronously.

### 9.4 Storage Service (Archiver)

The **storage service** sits in the pipeline after iris-engine. It's a fire-and-forget async writer - it does NOT block the real-time pipeline.

```
iris-engine ──NATS──▶ gateway (real-time path, result to browser)
    │
    └──NATS──▶ storage service (async, non-blocking)
                    │
                    ├── Write raw JPEG → object-store
                    ├── Write segmentation artifacts → object-store
                    ├── Write metadata JSON → object-store
                    └── (Enrollment only) Write template → template-db
```

**Key design: the storage service is NOT in the critical path.** If object-store is slow or down, matching still works. Raw data archival is best-effort with retry.

```python
# storage/src/main.py - subscribes to pipeline events via NATS

import nats

async def handle_archive(msg):
    """Called async via NATS on every analyzed frame."""
    data = decode_archive_request(msg.data)
    await object_store.put(f"raw/{data.date}/{data.device_id}/{data.frame_id}.jpg", data.raw_jpeg)
    await object_store.put(f"artifacts/{data.date}/{data.frame_id}/pipeline.json", data.pipeline_trace)
    # Non-blocking: if object-store is slow, matching still works

async def handle_enrollment(msg):
    """Called on new enrollment."""
    data = decode_enrollment(msg.data)
    await object_store.put(f"enrollments/{data.identity_id}/{data.template_id}_raw.jpg", data.raw_image)
    await template_db.store(data.template_id, data.iris_code, data.mask)

nc = await nats.connect("nats://nats:4222")
await nc.subscribe("eyed.archive", cb=handle_archive)
await nc.subscribe("eyed.enroll", cb=handle_enrollment)
```

### 9.5 Training Data Pipeline

Raw images accumulate over time. Periodically export curated datasets for retraining the DNN models.

```
                     Object Store
                    (months of data)
                          │
                          ▼
┌───────────────────────────────────────────────────────┐
│  Training Export Script (scripts/export_training.py)  │
│                                                       │
│  1. Query match_log for frames with:                  │
│     - High confidence segmentation (>0.9)             │
│     - Verified matches (human-reviewed)               │
│     - Diverse devices and lighting conditions         │
│                                                       │
│  2. Fetch raw images + segmentation masks             │
│     from object-store                                 │
│                                                       │
│  3. Optionally: human review in CVAT/Label Studio     │
│     to correct segmentation masks                     │
│                                                       │
│  4. Export as training dataset:                       │
│     training-export/{export_id}/                      │
│     ├── manifest.json                                 │
│     ├── images/  (eye crops, normalized)              │
│     └── masks/   (ground truth segmentation)          │
└───────────────────────────────────────────────────────┘
                          │
                          ▼
            Fine-tune Open-IRIS segmentation model
            → Export new .onnx
            → Deploy to iris-engine container
```

**What makes good training data:**
- Frames where segmentation confidence was LOW (model struggled → useful hard examples)
- Frames from NEW devices/environments (domain shift)
- Frames with VERIFIED matches (ground truth identity)
- Frames with FAILED matches (false negatives → improve recall)

### 9.6 Retention Policy

| Data | Default Retention | Configurable? | Deletion |
|------|------------------|---------------|----------|
| Iris templates | Permanent (until identity removed) | Yes | Cascade: delete identity → delete templates |
| Match logs | 1 year | Yes | Auto-purge by cron / retention policy |
| Raw images | 2 years | Yes | Move to cheaper storage or delete |
| Segmentation artifacts | 90 days | Yes | Auto-delete, re-derivable from raw |
| Training exports | Permanent | No | Manual cleanup |
| Enrollment snapshots | Permanent (while identity exists) | Yes | Cascade with identity deletion |

```toml
# config/storage.toml
[retention]
match_log_days = 365
raw_images_days = 730
artifacts_days = 90
auto_purge_enabled = true
auto_purge_cron = "0 3 * * *"    # Run at 3 AM daily
```

### 9.7 Storage Sizing

| Data Type | Size per Record | Growth Rate (1 device, 4fps analyzed) | 1 Year |
|-----------|----------------|--------------------------------------|--------|
| Raw JPEG | ~20 KB | ~80 KB/s | ~2.5 TB |
| Metadata JSON | ~1 KB | ~4 KB/s | ~126 GB |
| Segmentation mask | ~5 KB | ~20 KB/s | ~631 GB |
| Normalized iris PNG | ~2 KB | ~8 KB/s | ~252 GB |
| Iris template | ~1 KB | Only on enrollment | Negligible |
| Match log row | ~200 B | ~800 B/s | ~25 GB |
| **Total** | | **~113 KB/frame** | **~3.5 TB** |

**For 4 capture devices:** ~14 TB/year raw storage

**Recommendations:**
- Edge (Jetson): 1TB NVMe for local buffer, sync to cloud nightly
- Cloud: S3/SeaweedFS with lifecycle rules (move raw → Glacier after 90 days)
- Save artifacts only for interesting frames (low confidence, mismatches, new enrollments) to cut storage 10x

---

## 10. Security

Iris biometric data is **sensitive PII**. A leaked iris template can't be rotated like a password. Security is mandatory at every layer: in transit, at rest, and between services.

### 10.1 Threat Model

| Threat | Vector | Impact |
|--------|--------|--------|
| Template theft | DB access, network sniff | Permanent identity compromise |
| Replay attack | Captured frame replayed to gateway | Unauthorized match |
| Man-in-the-middle | Tampered frames or results | False match / false reject |
| Rogue capture device | Unauthorized RPi joins network | Inject frames, exfiltrate templates |
| Storage breach | Object store or DB dump | Mass biometric data leak |
| Service impersonation | Spoofed container in cluster | Pipeline manipulation |

### 10.2 Communication Security

All network paths are encrypted. No plaintext biometric data ever crosses a wire.

```
CAPTURE DEVICE ═══mTLS (gRPC)═══▶ GATEWAY ═══TLS (NATS)═════▶ SERVICES
     │                                │                            │
     │  Client cert per device        │  NATS TLS required         │  Service mesh TLS
     │  Server cert on gateway        │  No anonymous connections  │  (Kubernetes mTLS)
     │  TLS 1.3 minimum               │  JWT auth per service      │
```

**Edge communication (capture device → gateway): mTLS over gRPC**

| Aspect | Config |
|--------|--------|
| Protocol | TLS 1.3 (minimum) |
| Auth | Mutual TLS - device presents client certificate |
| Cipher suites | TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256 |
| Certificate | Per-device client cert, signed by internal CA |
| Revocation | CRL or OCSP for compromised devices |

```cpp
// capture/src/client.cpp - gRPC with mTLS
grpc::SslCredentialsOptions ssl_opts;
ssl_opts.pem_root_certs = load_file("certs/ca.pem");          // Trust our CA
ssl_opts.pem_private_key = load_file("certs/device-key.pem"); // This device's key
ssl_opts.pem_cert_chain = load_file("certs/device-cert.pem"); // This device's cert

auto creds = grpc::SslCredentials(ssl_opts);
auto channel = grpc::CreateChannel("gateway:50050", creds);
```

**Inter-service communication (NATS): TLS + JWT auth**

```
# NATS server config (nats-server.conf)
tls {
    cert_file:  "/certs/nats-server.pem"
    key_file:   "/certs/nats-server-key.pem"
    ca_file:    "/certs/ca.pem"
    verify:     true                    # Require client certs
    timeout:    2
}

authorization {
    # Each service gets a unique NATS user with scoped permissions
    users = [
        {
            user: "gateway"
            permissions: {
                publish: ["eyed.analyze", "eyed.enroll"]
                subscribe: ["eyed.result"]
            }
        }
        {
            user: "iris-engine"
            permissions: {
                publish: ["eyed.result", "eyed.archive"]
                subscribe: ["eyed.analyze", "eyed.enroll", "eyed.templates.*"]
            }
        }
        {
            user: "storage"
            permissions: {
                publish: []
                subscribe: ["eyed.archive", "eyed.enroll"]
            }
        }
    ]
}
```

**NATS subject-level permissions** ensure that even if one service is compromised, it can only publish/subscribe to its own subjects. A compromised `storage` service cannot read from `eyed.analyze` or write to `eyed.result`.

### 10.3 Encryption at Rest and In Use

Biometric data (`iris_codes`, `mask_codes`) is protected using OpenFHE BFV
homomorphic encryption. Templates are stored and matched as HE ciphertexts.
The iris-engine never holds the secret key — only the key-service can decrypt.

**Two modes** (auto-detected from key file presence — no env var toggle):

| Mode | Storage | Matching | Security |
|------|---------|----------|----------|
| Plain NPZ (dev fallback) | `~10 KB` per template | Plaintext Hamming distance (~0.15 ms) | No encryption — requires `EYED_ALLOW_PLAINTEXT=true` |
| OpenFHE BFV (default) | `~1.7 MB` per template | Encrypted ct×ct (~15-35 ms) | Server never sees plaintext biometrics |

```
iris-engine (public key + eval keys)     key-service (SECRET key)     PostgreSQL
  - HE encrypt after pipeline              - Decrypt match results       - HE ciphertexts
  - ct × ct matching on ciphertexts        - Check HD threshold          - Metadata (plaintext)
  - CANNOT decrypt                         - Admin gallery viz           - CANNOT decrypt
```

**What gets HE-encrypted (when enabled):**

| Field | Encryption | Rationale |
|-------|-----------|-----------|
| `iris_codes` | HE (BFV, N=8192, t=65537) | Biometric identifier |
| `mask_codes` | HE (BFV, N=8192, t=65537) | Biometric data |
| `eye_side`, `width`, `height`, `n_scales`, `quality_score` | Plaintext | Structural metadata — not biometrically identifying, needed for server-side filtering |

**Template DB (PostgreSQL):**

| Layer | Method | Status |
|-------|--------|--------|
| Application-level | OpenFHE BFV HE ciphertexts | Implemented (auto-detected from key files) |
| Disk-level | Full-disk encryption (LUKS / FileVault) | Deployment config |

**Note:** AES-256-GCM (`crypto.py`, `EYED_ENCRYPTION_KEY`) was previously
available as an interim encryption layer but has been removed. A migration
script (`iris-engine/scripts/migrate_aes_to_npz.py`) converts any remaining
AES blobs to plain NPZ.

**Internal design documents:** `docs/internal/HE_EVALUATION_REPORT.md`, `docs/internal/OPENFHE_DB_STORAGE_PLAN.md`, `docs/internal/OPENFHE_IMPLEMENTATION.md`

### 10.4 Capture Device Authentication

Each RPi capture device has a unique identity. No anonymous devices can join the system.

**Device provisioning flow:**

```
1. Generate key pair on device during setup
   $ eyed-capture --generate-certs --device-id rpi-entrance-01

2. Device creates CSR (Certificate Signing Request)
   → Includes device_id, hardware serial, public key

3. Admin signs CSR with internal CA
   $ eyed-admin sign-device-csr rpi-entrance-01.csr
   → Produces rpi-entrance-01.pem (signed client certificate)

4. Certificate installed on device
   /etc/eyed/certs/
   ├── ca.pem                 # CA certificate (trust anchor)
   ├── device-cert.pem        # This device's signed certificate
   └── device-key.pem         # This device's private key (chmod 600)

5. Gateway validates client cert on every connection
   → Extracts device_id from certificate CN field
   → Checks against allowed device list
   → Rejects unknown or revoked devices
```

**Anti-replay protection:**

```
CaptureFrame {
    ...
    uint64  timestamp_us;       // Monotonic, server rejects stale frames (>5s old)
    uint32  sequence_num;       // Per-session monotonic counter
    bytes   hmac;               // HMAC-SHA256(frame_data, session_key)
}
```

The gateway validates:
- Timestamp is within 5 seconds of server time (NTP synced)
- Sequence number is strictly increasing per session
- HMAC matches frame data (prevents tampering)

### 10.5 Key Management

| Key | Purpose | Storage | Rotation |
|-----|---------|---------|----------|
| **CA private key** | Sign device + service certs | Offline HSM or vault | Yearly |
| **Device client certs** | mTLS for capture devices | On-device filesystem (600 perms) | Yearly or on compromise |
| **NATS TLS certs** | Encrypt inter-service messaging | Mounted as K8s secrets | Auto-rotate (cert-manager) |
| **HE keys (BFV keypair)** | OpenFHE encrypt/decrypt templates | Docker volume `/keys/` (key-service generates) | On compromise |
| **SeaweedFS encryption key** | Server-side object encryption (future) | KMS (Vault / AWS KMS) | Annually |
| **gRPC server cert** | Gateway TLS termination | K8s secret or file mount | Auto-rotate (cert-manager) |

**Key hierarchy (envelope encryption):**

```
Root Key (HSM / Vault - never leaves secure boundary)
  │
  ├── Key Encryption Key (KEK) - encrypts DEKs
  │     │
  │     ├── DEK-templates - encrypts iris codes in template DB
  │     ├── DEK-objects   - encrypts sensitive objects in SeaweedFS
  │     └── DEK-logs      - encrypts audit logs (match_log)
  │
  └── CA Key - signs all TLS certificates
        │
        ├── Gateway server cert
        ├── NATS server cert
        ├── Device client certs (per-device)
        └── Service client certs (per-container)
```

**For edge (no Vault):** DEK derived from a passphrase stored in a hardware-backed keystore (TPM on RPi CM4, or encrypted file on Jetson's secure storage). Simpler but less secure than Vault.

### 10.6 Security in the Pipeline

```
┌────────────────────────────────────────────────────────────────────┐
│                         SECURITY LAYERS                            │
│                                                                    │
│   RPi ══mTLS══▶ Gateway ══TLS/NATS══▶ Services                     │
│   │              │                      │                          │
│   │ device cert  │ validates device     │ JWT scoped per service   │
│   │ HMAC frames  │ anti-replay check    │ subject-level ACL        │
│   │              │ rate limiting         │                         │
│   │              │                      │                          │
│   │              ▼                      ▼                          │
│   │         Template DB            Object Store (future)           │
│   │         ├── OpenFHE BFV (tgt) ├── SSE (server-side enc)        │
│   │         ├── AES-GCM (interim) ├── LUKS disk encryption         │
│   │         └── key-service (tgt) └── Client-side enc (optional)   │
│   │                                                                │
│   │         Audit Trail                                            │
│   │         ├── All match attempts logged                          │
│   │         ├── All enrollment/deletion logged                     │
│   │         └── Tamper-evident (HMAC per log entry)                │
│   │                                                                │
│   └─────── All keys in Vault / HSM (production)                    │
│            or encrypted config (edge)                              │
└────────────────────────────────────────────────────────────────────┘
```

### 10.7 Compliance Considerations

Iris biometric data is subject to strict regulations in most jurisdictions:

| Regulation | Requirement | How EyeD Addresses It |
|-----------|-------------|----------------------|
| GDPR (EU) | Explicit consent, right to deletion, data minimization | Enrollment requires consent flag; `DELETE /identity` cascades all data; configurable retention |
| BIPA (Illinois) | Written consent, retention schedule, destruction policy | Consent audit trail; retention.toml; auto-purge cron |
| CCPA (California) | Opt-out, disclosure of collection | Identity metadata tracks consent; export API for disclosure |
| ISO/IEC 24745 | Biometric template protection | Application-level encryption; templates never stored in plaintext |

**Identity deletion cascade:**
```
DELETE identity "id-a1b2c3"
  → Delete all templates for identity      (template-db)
  → Delete enrollment snapshots            (object-store/enrollments/)
  → Anonymize match_log entries            (template-db, set identity to NULL)
  → Delete raw images linked to identity   (object-store/raw/, if identifiable)
  → Audit log: "identity deleted by admin at <timestamp>"
```

---

## 11. What Happens to BiometricLib

Open-IRIS replaces the **entire** BiometricLib recognition pipeline. No Masek C code runs in production.

```
BiometricLib (RETIRED - all 80 files):
├── src/Iris/Masek/         # All 30+ C files → replaced by Open-IRIS
├── src/Iris/Iris/          # All 20 C++ wrappers → replaced by iris-engine service
├── src/IrisAnalysis/       # ROC/stats → replaced by Python test suite + Prometheus metrics
└── src/Face/               # Was already disabled → removed

IrisAnalysis (RETIRED - all files):
├── *.h/cpp                 # Qt GUI → replaced by web-ui (browser SPA)
├── cli/                    # CLI tool → replaced by eyed-cli (calls iris-engine via NATS)
└── tests/                  # Python test suite → KEPT, adapted to test iris-engine API
```

### What we keep from the old projects

| Kept | From | Why |
|------|------|-----|
| Python test framework | IrisAnalysis/tests/ | Bulk testing, metrics, HTML reports. Adapt to call iris-engine API instead of CLI binary |
| Test datasets (CASIA references) | BiometricLib config | Validation baseline — verify Open-IRIS matches or exceeds our old accuracy |
| Domain knowledge | Both projects | Understanding of Gabor parameters, Hamming thresholds, quality scoring |

### What we don't keep

Everything else. The Masek C code, the C++ wrappers, the Qt GUI, the Haar cascades, the build scripts — all replaced by better alternatives (Open-IRIS, web UI, Docker).

---

## 12. Tech Stack

### Capture Device (RPi) - Headless

| Component | Technology | Version | Why |
|-----------|-----------|---------|-----|
| **Language** | C++23 | GCC 15 / Clang 21 | Same as server, shared types |
| **Camera** | V4L2 (direct) or OpenCV VideoCapture | OpenCV 4.13 | V4L2 for NIR control, OpenCV as fallback |
| **Quality check** | OpenCV (Sobel) | 4.13 | CPU-only, ~5ms |
| **Compression** | libjpeg-turbo | 3.1 | NEON SIMD on ARM, ~3ms for 640x480 |
| **Network** | gRPC (C++) | 1.70 | Streaming, binary, generated stubs |
| **Serialization** | Protobuf | 33.x | gRPC message encoding (capture↔gateway) |
| **Video stream** | libwebrtc / GStreamer WebRTCbin | - | H.264 hw encode → WebRTC to browser |
| **Config** | TOML | toml++ 3.x | Runtime-configurable thresholds |
| **Logging** | spdlog | 1.17 | Already used in current CLI tool |

### Web UI (Browser)

| Component | Technology | Version | Why |
|-----------|-----------|---------|-----|
| **Framework** | Vanilla TypeScript (or Lit) | TS 5.x | Lightweight SPA, no heavy framework needed |
| **Live video** | WebRTC (browser native) | - | Hardware-decoded H.264 from RPi, ~50ms latency |
| **Live results** | WebSocket | - | Gateway pushes analysis results in real-time |
| **REST API** | Fetch API | - | Enrollment, admin, history queries |
| **Canvas overlay** | HTML5 Canvas | - | Draw pupil/iris circles over video feed |
| **Bundler** | Vite | 6.x | Fast dev server, minimal config |
| **Serving** | nginx | stable | Static file serving in container, ~30MB image |

### Iris Engine (Algorithm Service)

| Component | Technology | Version | Why |
|-----------|-----------|---------|-----|
| **Language** | Python | 3.10 | Open-IRIS requires Python 3.10 (pins numpy/pydantic v1 incompatible with 3.12+) |
| **Algorithm** | Open-IRIS (Worldcoin) | 1.11.0 | Best open-source iris recognition, MIT license, 150x better than Masek. Features: image denoising, 16-bit ONNX, image_id tracing, improved ellipse geometry |
| **DNN Inference** | ONNX Runtime (multi-provider) | ORT 1.16.3 | CUDA, CPU, CoreML, TensorRT — same .onnx model. Pinned by Open-IRIS |
| **Pretrained Model** | Worldcoin/iris-semantic-segmentation | HuggingFace | MobileNetV2+UNet++, IoU 0.943 |
| **API Framework** | FastAPI | 0.115 | Async Python HTTP/WebSocket, auto-docs |
| **Messaging** | nats-py | 2.9 | NATS client for Python |
| **Write Cache** | redis[hiredis] | 5.x | Write-through cache for bulk enrollment persistence (Redis LIST → background drain to Postgres) |
| **Base Image** | debian:trixie-slim (CPU) / nvidia/cuda:12 (CUDA) | Debian 13 | Multi-target Dockerfile, `--build-arg RUNTIME` |

### Infrastructure Services (Gateway, Storage, etc.)

| Component | Technology | Version | Why |
|-----------|-----------|---------|-----|
| **Gateway language** | Go or C++23 | Go 1.23 / GCC 15 | Gateway is I/O-bound, Go is simpler for gRPC+WebSocket+NATS |
| **Edge Network** | gRPC | 1.70 | Capture device → gateway (request/response) |
| **Inter-Service** | NATS | nats-server 2.12 | Lightweight pub/sub between containers |
| **Serialization** | Protobuf (gRPC) + JSON (NATS payloads) | Protobuf 33.x | Simple, debuggable NATS messages |
| **Write Cache** | Redis | 7.x (Alpine) | Write-through cache: bulk enrollment → Redis LIST → background batch drain to Postgres |
| **Template Store** | PostgreSQL (cloud) / SQLite (edge) | PostgreSQL 18 / SQLite 3.51 | Persistence + fast matching |
| **Encrypted SQLite** | SQLCipher | 4.13 | AES-256 encrypted SQLite for edge |
| **Object Store** | SeaweedFS (cloud) / local FS (edge) | SeaweedFS latest | S3-compatible, Apache 2.0 |
| **Health Checks** | HTTP `/health/alive`, `/health/ready` | - | Liveness + readiness probes |
| **Metrics** | Prometheus `/metrics` endpoint | - | Latency histograms, throughput counters |
| **Certificate CA** | step-ca | 0.29 | Internal CA for mTLS cert provisioning |
| **Secrets** | HashiCorp Vault (prod) / encrypted config (edge) | Vault 1.21 | Key management |
| **Testing** | pytest (iris-engine) + Catch2 (capture device) | pytest 8.x / Catch2 3.8 | Python + C++ tests |
| **Orchestration** | Docker Compose (all environments) / Kubernetes (cloud scale) | - | Everything runs in Docker |
| **Base Images** | Debian Trixie Slim (default) / nvidia/cuda:12 (optional CUDA) | Debian 13 | CPU-only by default, CUDA opt-in |
| **Build (capture)** | CMake | 4.2 | Cross-compile capture device for ARM64 |

### What Gets Removed

| Removed (Old) | Replaced By (New) |
|---------|-------------|
| Masek-Lee algorithm (C, 2003) | **Open-IRIS 1.11.0** (Python, 2025, MIT license, 150x more accurate) |
| BiometricLib (17K LOC C/C++) | **iris-engine Docker container** (~200 lines Python wrapping Open-IRIS) |
| Qt5 5.9 (500MB+, on-device GUI) | **Web UI** (TypeScript SPA in browser, ~30MB nginx container) |
| QMake + CMake (mixed) | **Docker Compose** (all services containerized) |
| OpenCV 3.4 (IplImage / CvCapture C API) | **OpenCV 4.13** (capture device only, cv::Mat / V4L2) |
| Haar Cascade XML | **MobileNetV2+UNet++ ONNX model** (Open-IRIS pretrained) |
| Manual malloc/free | **Python (iris-engine) + std::unique_ptr (capture)** |
| Hardcoded paths | **Environment variables + Docker secrets** |
| No containers, Ubuntu 18 Docker | **Debian 13 Trixie Slim** containers, everything in Docker |
| MinIO (archived, dead) | **SeaweedFS** (Apache 2.0, actively maintained) |
| Monolithic single-process | **Docker Compose microservices, NATS 2.12 messaging** |

---

## 13. Project Structure

Each service is a **Docker container**. The project is organized by service, not by C++ library layers.

```
eyed/
│
│── ─── SERVICES (each becomes a Docker container) ───────────
│
├── iris-engine/                    # Core algorithm service (Python + Open-IRIS)
│   ├── Dockerfile                  # Multi-target: --build-arg RUNTIME=cpu|cuda
│   ├── requirements.txt            # open-iris, nats-py, fastapi, uvicorn, redis
│   ├── src/
│   │   ├── main.py                 # FastAPI app + NATS subscriber + lifespan init
│   │   ├── pipeline.py             # Wraps Open-IRIS: analyze(), create_pipeline()
│   │   ├── pipeline_pool.py        # Pre-loaded pipeline pool for parallel batch work
│   │   ├── matcher.py              # In-memory gallery + Hamming distance matching
│   │   ├── redis_cache.py          # Redis write-through cache for enrollment data
│   │   ├── db_drain.py             # Background Redis → Postgres batch drain writer
│   │   ├── db.py                   # PostgreSQL connection pool + template persistence
│   │   ├── core.py                 # Shared enrollment logic (single + batch)
│   │   ├── health.py               # Health check logic (pipeline, NATS, Redis, pool)
│   │   ├── nats_service.py         # NATS messaging (analyze, enroll, gallery sync)
│   │   ├── models.py               # Pydantic request/response models
│   │   ├── config.py               # Environment-based configuration
│   │   └── routes/
│   │       ├── health.py           # /health/alive, /health/ready endpoints
│   │       ├── analyze.py          # /analyze endpoint (single image)
│   │       ├── enroll.py           # /enroll + /enroll/batch (pipeline pool + SSE)
│   │       ├── gallery.py          # /gallery endpoints (list, detail, delete)
│   │       └── datasets.py         # /datasets endpoints (list, browse, images)
│   └── tests/
│       ├── test_pipeline.py        # Unit tests for iris pipeline + health endpoints
│       ├── test_benchmark.py       # Per-frame latency benchmark
│       ├── test_fnmr.py            # FNMR accuracy test (CASIA1)
│       ├── test_fnmr_mmu2.py       # FNMR accuracy test (MMU2)
│       └── conftest.py             # pytest fixtures
│
├── gateway/                        # Traffic routing + signaling (Go or C++)
│   ├── Dockerfile                  # debian:trixie-slim + gRPC + NATS
│   ├── src/
│   │   ├── main.go                 # Entry point
│   │   ├── grpc_server.go          # Accepts frames from capture devices (gRPC)
│   │   ├── websocket.go            # Pushes results to browsers (WebSocket)
│   │   ├── signaling.go            # WebRTC SDP relay (RPi ↔ browser)
│   │   ├── nats_client.go          # Publishes to iris-engine, subscribes to results
│   │   └── circuit_breaker.go      # Degraded mode if iris-engine is down
│   └── go.mod
│
├── storage/                        # Async archival service (Python)
│   ├── Dockerfile                  # debian:trixie-slim + boto3 + nats-py
│   ├── src/
│   │   ├── main.py                 # NATS subscriber for archive events
│   │   ├── archiver.py             # Write raw images + artifacts to S3
│   │   ├── dedup.py                # Deduplication check on enrollment
│   │   ├── retention.py            # Auto-purge expired data
│   │   └── export.py               # Training data export script
│   └── tests/
│       └── test_archiver.py
│
├── web-ui/                         # Browser dashboard (TypeScript SPA)
│   ├── Dockerfile                  # multi-stage: node build → nginx serve
│   ├── package.json
│   ├── vite.config.ts
│   ├── index.html
│   ├── src/
│   │   ├── main.ts                 # Entry point
│   │   ├── app.ts                  # App shell, routing
│   │   ├── api/
│   │   │   ├── websocket.ts        # Live results from gateway
│   │   │   ├── webrtc.ts           # Live video from capture device
│   │   │   └── rest.ts             # Enrollment, admin, history
│   │   ├── views/
│   │   │   ├── dashboard.ts        # All devices, live match results
│   │   │   ├── enrollment.ts       # Video + capture + identity form
│   │   │   ├── device-detail.ts    # Single device video + overlay
│   │   │   ├── history.ts          # Match audit log
│   │   │   └── admin.ts            # System health, device mgmt
│   │   └── components/
│   │       ├── video-player.ts     # WebRTC video + canvas overlay
│   │       ├── match-card.ts       # Match result card
│   │       └── device-status.ts    # Device health indicator
│   └── static/
│       └── styles.css
│
├── capture/                        # Capture device (C++, runs on RPi, headless)
│   ├── Dockerfile                  # debian:trixie-slim ARM64 + OpenCV + gRPC
│   ├── CMakeLists.txt              # Binary: eyed-capture
│   └── src/
│       ├── main.cpp                # Entry point, 2 threads
│       ├── camera.cpp              # V4L2 / OpenCV camera abstraction
│       ├── quality_gate.cpp        # Sobel quality + frame selection
│       ├── client.cpp              # gRPC client (frames → gateway)
│       └── webrtc_streamer.cpp     # H.264 hw encode → WebRTC to browser
│
│── ─── INFRASTRUCTURE (off-the-shelf Docker images) ─────────
│
├── docker-compose.yml              # Full stack, CPU-only (works on Mac, Linux, CI)
├── docker-compose.gpu.yml          # GPU override (Linux + NVIDIA CUDA)
├── docker-compose.edge.yml         # Minimal edge: engine + gateway + web-ui
├── docker-compose.dev.yml          # Development: hot reload, debug ports
│
│── ─── CONFIG & DEPLOY ──────────────────────────────────────
│
├── config/
│   ├── nats-server.conf            # NATS TLS + authorization
│   ├── capture.toml                # Capture device defaults
│   └── retention.toml              # Storage retention policies
│
├── proto/
│   └── capture.proto               # gRPC: capture device → gateway protocol
│
├── deploy/
│   └── k8s/
│       ├── namespace.yaml
│       ├── iris-engine-deployment.yaml   # GPU pods, auto-scaling
│       ├── gateway-deployment.yaml
│       ├── storage-deployment.yaml
│       ├── web-ui-deployment.yaml
│       ├── postgres-statefulset.yaml
│       ├── seaweedfs-statefulset.yaml
│       ├── nats-statefulset.yaml
│       ├── persistent-volumes.yaml
│       └── services.yaml
│
├── secrets/
│   ├── db_password.txt             # (gitignored)
│   └── nats-creds/                 # (gitignored)
│
│── ─── TESTING ──────────────────────────────────────────────
│
├── tests/
│   ├── integration/                # End-to-end tests (ADAPTED from IrisAnalysis)
│   │   ├── test_bulk_iriscompare.py
│   │   ├── prepare.py
│   │   ├── report.py
│   │   └── templates/              # Jinja2 report templates
│   └── data/
│       └── sample_eyes/
│
└── scripts/
    ├── fine_tune_segmenter.py      # Fine-tune Open-IRIS model on your data
    ├── export_training_data.py     # Export from object-store for retraining
    └── benchmark.py                # Latency + accuracy benchmarking
```

### Separation of Concerns

| Service | Knows about | Doesn't know about |
|---------|------------|-------------------|
| **iris-engine** | Open-IRIS, NATS subjects, template format | Gateway, storage, web-ui, capture device |
| **gateway** | gRPC (capture), WebSocket (browser), NATS (iris-engine) | Open-IRIS internals, storage, template DB schema |
| **storage** | S3 API (SeaweedFS), NATS archive events | Open-IRIS, gateway, web-ui |
| **web-ui** | WebSocket (gateway), REST (gateway), WebRTC (capture) | Everything server-side |
| **capture** | gRPC (gateway), WebRTC (browser), camera hardware | Open-IRIS, storage, templates |
| **template-db** | PostgreSQL | Everything else (accessed only via NATS requests) |

Each service communicates only through NATS messages or gRPC. No shared libraries, no shared memory, no import dependencies between services. Swap any service independently.

---

## 14. Core Types

### iris-engine (Python / Pydantic)

```python
# iris-engine/src/models.py

from pydantic import BaseModel
import numpy as np

class SegmentationResult(BaseModel):
    """Open-IRIS 4-class semantic segmentation output."""
    pupil_center: tuple[float, float]
    pupil_radius: float
    iris_center: tuple[float, float]
    iris_radius: float
    noise_mask: bytes              # Packed binary: eyelid + eyelash + reflection
    confidence: float              # [0.0 - 1.0]

class IrisTemplate(BaseModel):
    """Gabor-encoded iris code with noise mask."""
    iris_code: bytes               # Packed bits (>10K bits, multi-scale 2D Gabor)
    mask_code: bytes               # Packed noise mask bits
    iris_code_version: str = "open-iris-1.11"
    image_width: int = 512         # Normalized iris strip dimensions
    image_height: int = 64

class MatchResult(BaseModel):
    """Fractional Hamming distance match result."""
    hamming_distance: float        # [0.0 - 0.5]
    is_match: bool                 # HD < threshold
    best_rotation: int             # Optimal rotational shift
    matched_identity_id: str | None  # Identity ID if matched

class AnalyzeRequest(BaseModel):
    """Frame submitted for analysis via NATS."""
    frame_id: str
    device_id: str
    jpeg_data: bytes               # Raw JPEG from capture device
    quality_score: float           # Sobel score from capture device
    timestamp: str                 # ISO 8601

class AnalyzeResponse(BaseModel):
    """Full pipeline result pushed back to gateway."""
    frame_id: str
    device_id: str
    segmentation: SegmentationResult | None
    template: IrisTemplate | None
    match: MatchResult | None
    latency_ms: float
    error: str | None = None

class PipelineConfig(BaseModel):
    """iris-engine configuration."""
    # Open-IRIS model
    segmentation_model: str = "Worldcoin/iris-semantic-segmentation"
    runtime: str = "cpu"           # "cpu", "cuda", "coreml", "tensorrt"

    # Matching
    match_threshold: float = 0.39
    dedup_threshold: float = 0.32  # Stricter for enrollment dedup

    # NATS
    nats_url: str = "nats://nats:4222"
    nats_subject_analyze: str = "eyed.analyze"
    nats_subject_result: str = "eyed.result"
```

### capture device (C++)

```cpp
// capture/include/types.hpp

struct CaptureFrame {
    std::vector<uint8_t> jpeg;     // JPEG-compressed frame
    float quality_score;            // Sobel quality [0.0 - 1.0]
    std::string device_id;
    std::string timestamp;          // ISO 8601
};

struct CaptureConfig {
    float quality_threshold = 0.30f;
    int camera_index = 0;
    int frame_width = 640;
    int frame_height = 480;
    std::string gateway_address = "gateway:50050";
    std::string device_cert = "certs/device-cert.pem";
    std::string device_key = "certs/device-key.pem";
    std::string ca_cert = "certs/ca.pem";
};
```

### gateway (Go)

```go
// gateway/internal/types.go

type AnalyzeRequest struct {
    FrameID      string  `json:"frame_id"`
    DeviceID     string  `json:"device_id"`
    JpegData     []byte  `json:"jpeg_data"`
    QualityScore float64 `json:"quality_score"`
    Timestamp    string  `json:"timestamp"`
}

type AnalyzeResponse struct {
    FrameID          string   `json:"frame_id"`
    DeviceID         string   `json:"device_id"`
    IsMatch          bool     `json:"is_match"`
    HammingDistance  float64  `json:"hamming_distance"`
    MatchedIdentity  *string  `json:"matched_identity_id,omitempty"`
    LatencyMs        float64  `json:"latency_ms"`
    Error            *string  `json:"error,omitempty"`
}
```

---

## 15. Latency Breakdown

### End-to-End (RPi capture → result displayed)

```
Step                              Where           CUDA      CPU-only
──────────────────────────────────────────────────────────────────────
Camera frame grab                 RPi             ~1ms      ~1ms
Sobel quality check               RPi CPU         ~5ms      ~5ms
JPEG compress (NEON)              RPi CPU         ~3ms      ~3ms
Network send (LAN)                Network         ~2ms      ~2ms
Gateway decode + NATS publish     Server CPU      ~1ms      ~1ms
Open-IRIS segmentation (DNN)      iris-engine     ~15ms     ~100ms
Daugman normalization             iris-engine     ~5ms      ~5ms
2D Gabor encoding (multi-scale)   iris-engine     ~20ms     ~20ms
Fractional Hamming matching       iris-engine     ~1ms      ~1ms
NATS return → WebSocket push      Server          ~1ms      ~1ms
──────────────────────────────────────────────────────────────────────
TOTAL (capture → result)                          ~54ms     ~139ms

WebRTC video latency              Network         ~50ms     ~50ms (parallel)
```

| Runtime | Total latency | Analysis throughput | Use case |
|---------|--------------|--------------------| ---------|
| **CUDA** (NVIDIA GPU) | **~54ms** | ~18 fps | Production |
| **CoreML** (Apple M-series) | **~70-90ms** | ~12 fps | Mac development |
| **CPU-only** | **~139ms** | ~7 fps | CI, non-GPU servers |

Camera feed displays at 30fps in the browser via WebRTC (parallel stream, does not wait for analysis). Even CPU-only mode at ~7 fps is sufficient for development and testing.

### Compared to Current

| Metric | Current | Proposed | Improvement |
|--------|---------|----------|-------------|
| Full analysis | ~2+ min | **~54ms** | **~2200x faster** |
| Segmentation | ~100ms Hough (inaccurate) | ~15ms DNN (IoU 94.3%) | 7x faster + far more accurate |
| Encoding | ~50ms (1 scale, ~2K bits) | ~20ms (multi-scale, >10K bits) | 2.5x faster + 5x more discriminative |
| FNMR @ FMR=0.001 | ~17-27% | **0.12%** | **150x more accurate** |
| Camera-to-browser | N/A (blocks UI) | ~50ms (WebRTC) | Real-time |
| Devices supported | 1 (desktop) | Many (RPi fleet) | Scalable |
| Memory (capture device) | 500MB+ (Qt) | ~32MB (headless) | ~16x less |
| Capture binary size | 500MB+ | ~5MB (headless) | ~100x smaller |

---

## 16. Failure Modes & Fallback

| Failure | Detection | Fallback |
|---------|-----------|----------|
| Server unreachable | gRPC timeout (500ms) | RPi buffers best frame, retries; web-ui shows "offline" for device |
| Camera disconnected | V4L2 error / empty frame | RPi logs error; web-ui shows "no camera" on device card |
| DNN model not found | File check at startup | Server refuses to start, clear error message |
| Low quality frames | Sobel score < threshold | RPi doesn't send frame; web-ui shows quality indicator |
| Segmentation fails | Confidence < 0.5 | Gateway pushes `iris_segmented=false` to browser; web-ui shows "move closer" |
| No match in DB | HD > threshold for all templates | Gateway pushes `is_match=false` to browser |
| Network congestion | Latency > 200ms | RPi drops analysis frames (sends less); WebRTC auto-degrades bitrate |
| WebRTC stream fails | ICE connection timeout | Browser falls back to snapshot mode (latest analyzed JPEG via REST) |
| Browser disconnected | WebSocket close event | Gateway stops pushing results for that client; RPi unaffected (headless) |

---

## 17. Migration Path

All phases are Docker-first: every component is developed, tested, and deployed inside containers from day one.

### Phase 1: iris-engine (Week 1-2)
```
[x] Set up iris-engine Docker image (Python 3.10 + Open-IRIS + NATS client)
[x] Validate Open-IRIS pipeline: image → segment → normalize → encode → template
[x] Build NATS subscriber: listen on eyed.analyze, publish to eyed.result
[x] Implement 1:N matching: load gallery from template-db, fractional Hamming
[x] Dedup check on enrollment (HD < 0.32 strict threshold)
[x] Unit tests: verify FNMR < 0.5% on CASIA-Iris-Thousand (0.00% on 20 subjects)
[x] Benchmark: verify < 50ms per frame on T4/RTX GPU (347ms CPU, <50ms GPU target)
[x] CPU-only variant: Dockerfile without CUDA for edge/CI
```

### Phase 2: Gateway + NATS (Week 3-4)
```
[x] Set up NATS container (nats:2.10)
[x] Implement gateway in Go: gRPC ingress (capture frames), NATS publish/subscribe
[x] WebSocket endpoint for pushing results to browser clients
[x] WebRTC signaling relay (capture device → browser via gateway)
[x] Health check endpoints (/health/alive, /health/ready)
[x] Circuit breaker: handle iris-engine unavailability gracefully
[x] Proto definitions (proto/capture.proto): SubmitFrame, StreamFrames, GetStatus RPCs
[x] Integration test: gateway → NATS → iris-engine → NATS → gateway
[x] docker-compose.yml with gateway + nats + iris-engine
```

### Phase 3: Capture Device (Week 5)
```
[x] Implement camera abstraction (directory walker for dev, V4L2 stub for future RPi)
[x] Sobel quality gate + JPEG compression
[x] gRPC StreamFrames client (bidirectional streaming to gateway)
[x] Handle server disconnection gracefully (exponential backoff reconnect)
[x] Backpressure handling (FrameAck.accepted=false → throttle)
[x] SPSC lock-free ring buffer (capture thread → send thread)
[x] TOML config with EYED_* env overrides
[x] Multi-stage Dockerfile (Debian bookworm build + bookworm-slim runtime)
[x] docker-compose integration with all services
[ ] WebRTC streamer: H.264 hardware encode → signaling via gateway (deferred)
[ ] V4L2 camera backend for RPi (deferred to deployment)
[ ] ARM64 cross-compilation (deferred to RPi deployment)
[ ] Headless operation: systemd service (deferred to RPi deployment)
```

### Phase 4: Web UI (Week 6-7)
```
[x] Set up TypeScript SPA project (Vite + Lit, @vaadin/router, dark theme)
[x] WebSocket client: connect to gateway /ws/results, auto-reconnect with backoff
[x] WebRTC client: connect to /ws/signaling, SDP offer/answer, ICE candidates
[x] Dashboard view: stat cards (frames/matches/errors), live results feed
[x] Device detail view: auto-discovered devices, live video feed, frame stats
[x] Enrollment view: device selector, video feed, capture template, identity form
[x] History view: filterable/searchable audit log (all/match/no-match/error)
[x] Admin view: gateway + iris-engine + NATS health polling (5s interval)
[x] nginx Dockerfile (multi-stage node:22→nginx:alpine, SPA fallback, WS proxy)
[x] docker-compose: web-ui service on port 9505, engine proxy via /engine/
[ ] coturn sidecar container for NAT traversal (deferred — cloud deployments)
[ ] Canvas overlay for pupil/iris circles on video feed (deferred — needs pipeline output)
```

### Phase 5: Storage & Data Pipeline (Week 8-9)
```
[x] Template DB schema (PostgreSQL 16, identities + templates + match_log tables)
[x] Template cache: in-memory load on startup from PostgreSQL
[x] Enrollment API: enroll new identity with dedup check + DB persistence
[x] Full audit trail: every match attempt logged with HD score (async batch writer)
[x] docker-compose.yml includes postgres service with healthcheck
[x] NATS invalidation (eyed.templates.changed) for multi-node template sync
[x] Storage service container: async archival of raw images + artifacts (Go)
[x] Object store integration (local FS for edge; SeaweedFS/S3 deferred to cloud phase)
[x] Metadata JSON generation for every processed frame
[x] Retention policy: auto-purge cron for expired data
[x] Training data export script (scripts/export_training.py)
```

### Phase 6: Security (Week 10)
```
[ ] Set up internal CA (step-ca 0.29 container)
[ ] Generate gateway server certificate (TLS 1.3)
[ ] Build device provisioning tool (eyed-admin sign-device-csr)
[ ] Implement mTLS on gRPC (capture device → gateway)
[ ] Configure NATS TLS + per-service JWT authorization
[x] ~~AES-256-GCM encryption (crypto.py)~~ — removed, replaced by HE
[ ] Set up SQLCipher for edge SQLite deployments
[ ] Enable SeaweedFS encryption at rest
[ ] Add anti-replay validation in gateway (timestamp + sequence + HMAC)
[ ] Implement identity deletion cascade (GDPR right to erasure)
[ ] Add consent tracking to enrollment flow
[ ] Set up Vault (production) or encrypted config (edge) for key management
[ ] Security audit: verify no plaintext biometric data at rest or in transit
[x] Homomorphic Encryption (see docs/internal/OPENFHE_IMPLEMENTATION.md)
    - Phase 1: OpenFHE BFV context + encrypt/decrypt/serialize (DONE)
    - Phase 2: key-service (C++, OpenFHE, NATS) (DONE)
    - Phase 3: HE-encrypted enrollment + gallery loading (DONE)
    - Phase 4: HE matching (ct×ct inner product, key-service decrypt) (DONE)
    - Phase 5: AES cleanup + migration script (DONE)
    - Phase C: Hybrid blob storage (if PostgreSQL BYTEA degrades at scale)
    - Phase D: HE 1:N with LSH indexing (optional)
    - Phase E: TFHE encrypted admin queries (optional, per FHE-SQL analysis)
```

### Phase 7: Production Hardening (Week 11-12)
```
[ ] Kubernetes manifests (iris-engine, gateway, web-ui, storage deployments)
[ ] Prometheus metrics endpoints in each service
[ ] TensorRT optimization for Jetson (Open-IRIS segmentation model)
[ ] docker-compose.edge.yml (collapsed for Jetson / air-gapped)
[ ] End-to-end latency profiling across full pipeline
[ ] Stress test: 24h continuous operation, multiple capture devices
[ ] Storage sizing validation: verify actual sizes match estimates
[ ] Fine-tuning pipeline: export training data → retrain → deploy new model
```

---

## 18. Hardware Bill of Materials

### Minimum Setup (1 capture point)

| Component | Example | Cost |
|-----------|---------|------|
| Capture device | Raspberry Pi 4 (2GB) - headless, no HDMI needed | ~$35 |
| NIR camera module | RPi NoIR Camera V2 + IR LED ring | ~$30 |
| MicroSD card | 32GB | ~$10 |
| PoE HAT (optional) | Power + data over single cable | ~$15 |
| Compute server | Jetson Nano (4GB) | ~$99 |
| Storage | 1TB NVMe SSD (for object store) | ~$80 |
| Network | Ethernet switch (PoE if using PoE HATs) | ~$10-50 |
| **Total** | | **~$229-294** |

No monitor, keyboard, or HDMI cable needed for capture devices. Operators use a browser on any existing laptop/tablet/phone to access the web UI.

### Scaled Setup (4 capture points)

| Component | Qty | Cost |
|-----------|-----|------|
| RPi 4 + NoIR camera (headless) | 4 | ~$260 |
| PoE HAT per RPi (optional) | 4 | ~$60 |
| Jetson Xavier NX | 1 | ~$399 |
| NVMe SSD (2TB) | 1 | ~$150 |
| PoE Gigabit switch | 1 | ~$50 |
| **Total** | | **~$919** |

### Cloud Setup (4 capture points)

| Component | GPU Option | CPU-only Option |
|-----------|-----------|-----------------|
| RPi 4 + NoIR camera, headless (4 units) | ~$260 (one-time) | ~$260 (one-time) |
| Compute VM | GPU: g4dn.xlarge ~$150/mo | CPU: c6a.xlarge ~$60/mo |
| S3 storage (3.5 TB/year per device) | ~$80/mo | ~$80/mo |
| PostgreSQL (managed, small) | ~$15/mo | ~$15/mo |
| coturn TURN server (WebRTC NAT traversal) | ~$10/mo | ~$10/mo |
| **Total** | **~$255/mo + $260** | **~$165/mo + $260** |

The CPU-only cloud option works for small deployments (1-4 capture points) where ~7 fps analysis is sufficient. GPU scales to higher throughput.

---

## 19. Mobile Phone as Capture Device — Feasibility Evaluation

Consumer smartphones have high-resolution cameras and are ubiquitous. This section evaluates whether the latest iPhones and high-end Android phones can serve as iris capture devices for EyeD.

### 19.1 Technical Requirements for Iris Imaging

| Requirement | ISO/IEC 19794-6 Standard | Notes |
|-------------|--------------------------|-------|
| Wavelength | 700–900 nm (NIR) | Melanin-transparent, reveals stromal texture in all eye colors |
| Iris diameter | ≥200 pixels | Enrollment-grade; ≥150 pixels minimum acceptable |
| Pixel depth | 8-bit grayscale | Standard for all iris systems |
| Focus (MTF) | ≥0.5 contrast at 2 cy/mm | Critical — defocus destroys high-frequency iris texture |
| Capture distance | 10–50 cm (handheld) | Dedicated iris cameras: 10–33 cm typical |

**Why NIR matters:** Melanin absorbs strongly below 700 nm, making dark irises appear featureless in visible light. In NIR (810–850 nm), even heavily pigmented irises become transparent, revealing the crypts, furrows, and collarettes that form the biometric pattern. NIR also avoids pupil constriction and ambient light interference.

### 19.2 iPhone Evaluation

**TrueDepth System (Face ID) — NIR hardware exists but is locked:**

| Component | Spec | Iris Relevance |
|-----------|------|----------------|
| Flood illuminator | ~940 nm VCSEL | Suitable wavelength (slightly outside ISO 700–900 nm but usable) |
| Dot projector | 30,000+ IR dots | For 3D face geometry, not iris |
| NIR camera | ~1.4 MP, 2.8 µm pixel pitch | At Face ID distance: only ~30–50 px across iris — far below 200 px minimum |
| RGB front camera | 12 MP, f/1.9, PDAF | At 25–40 cm: ~200–300 px across iris — marginal |

**Critical blocker:** Apple does **not** expose the raw NIR camera feed through any public iOS API. No access to flood illuminator control, IR camera exposure, or raw infrared image data. This has been a consistent restriction since iPhone X (2017). All iris work on iPhone must use the visible-light RGB camera.

**Apple Vision Pro** uses iris recognition ("Optic ID") with dedicated eye-tracking cameras — but this is separate hardware not available on iPhone.

**iPhone verdict: NIR path blocked. RGB-only is marginal.**

### 19.3 Android Evaluation

**Samsung Iris Scanner — dead hardware:**

Samsung shipped dedicated iris scanners in Galaxy S8/S9/Note 7/8/9 (2016–2018):
- 810 nm OSRAM NIR LED + dedicated NIR camera
- Worked well for iris biometrics
- **Discontinued in 2019** — replaced by "Intelligent Scan" (face + iris fusion), then face-only
- No current Samsung phone has a dedicated iris scanner
- Android Biometric API does not expose raw iris scanner data to third-party apps

**Current Android landscape:**

| Phone | NIR Hardware | Iris Feasibility |
|-------|-------------|-----------------|
| Samsung Galaxy S24/S25 Ultra | None (no iris scanner) | RGB only |
| Google Pixel 8/9 Pro | None | RGB only |
| OnePlus 13 | None | RGB only |

**No current Android OEM ships a dedicated NIR iris camera.** The feature is effectively dead in the consumer phone market.

### 19.4 Visible-Light (RGB) Iris Recognition — State of the Art

Since NIR is unavailable on modern phones, the only viable path is visible-light capture using the standard RGB camera. Recent research (2024–2025) shows this is feasible under controlled conditions:

| Study | Device | Method | Accuracy |
|-------|--------|--------|----------|
| Trokielewicz et al. (2018) | iPhone 5s, 8 MP | IriCore (commercial) | 99.67% CMR at 0% FMR |
| CUVIRIS (2024) | Galaxy S21 Ultra | OSIRIS (classical) | 97.9% TAR at 0.01 FAR, 0.76% EER |
| CUVIRIS (2024) | Galaxy S21 Ultra | IrisFormer (transformer) | 0.057% EER |
| arXiv 2412.13063 (2024) | Android, YOLOv3 | Custom pipeline | 96.57% TAR (VIS), 97.95% (NIR) |

**By iris color (visible light):**

| Eye Color | EER | Notes |
|-----------|-----|-------|
| Light (blue/green) | ~0.00% | Texture rich in visible light |
| Dark (brown) | ~1.29% | Melanin obscures texture — the key limitation |

**Key insight:** Sub-1% EER is achievable in visible light with modern deep learning and quality-controlled capture. The accuracy gap with NIR narrows significantly for light-colored irises but remains for dark irises (~70% of world population).

### 19.5 Open-IRIS Compatibility

Open-IRIS was designed for **NIR images from the Worldcoin Orb** (custom hardware). Using it with visible-light phone images requires:

1. **Segmentation model retraining** — current model trained on NIR; visible-light images will produce poor segmentation, especially for dark irises
2. **Input format adaptation** — Open-IRIS expects 640×480 grayscale NIR images; phone images are color and higher resolution
3. **Quality pipeline changes** — different noise characteristics, specular reflections from screen/flash illumination

**Without retraining, Open-IRIS will not work reliably on visible-light phone images.**

### 19.6 Practical Capture Approach (If Pursuing Phone-Based)

```
Phone (front or rear camera with zoom)
  ├─ Illumination: white LED flash or screen glow
  ├─ Capture distance: 20–50 cm
  ├─ Resolution needed: 200+ px across iris
  │   ├─ 48 MP sensor: achievable at ~50 cm with 3–5× optical zoom
  │   └─ 12 MP sensor: achievable at ~25 cm, tight framing
  ├─ Quality gate: real-time focus/gaze/occlusion scoring
  └─ Output: JPEG eye crop → POST to iris-engine via REST API
```

**Challenges:**
- Specular reflections from illumination (corneal glare)
- Pupil constriction from visible-light flash
- User cooperation required (hold still, look at camera)
- Ambient light variability
- No IR-cut filter removal = no NIR possibility

### 19.7 Feasibility Summary

| Approach | Feasibility | Accuracy vs. Dedicated NIR | Effort |
|----------|-------------|---------------------------|--------|
| Phone NIR (TrueDepth / Samsung scanner) | **Not feasible** — APIs locked, hardware discontinued | N/A | N/A |
| Phone RGB + Open-IRIS (as-is) | **Not feasible** — segmentation model is NIR-only | Poor | Low |
| Phone RGB + retrained segmentation | **Feasible** — requires VIS training data + model work | ~96–98% TAR (vs 99%+ NIR) | High |
| Phone RGB + custom VIS pipeline | **Feasible** — use CUVIRIS/IrisFormer approach | ~97–99% TAR for light eyes, ~96% dark | High |
| Dedicated NIR camera (RPi NoIR + IR LED) | **Recommended** — proven, universal accuracy | 99%+ TAR all eye colors | Low (current arch) |
| External USB NIR dongle + phone | **Feasible** — dedicated hardware, phone as compute | 99%+ TAR | Medium |

### 19.8 Recommendation

**For EyeD, the current RPi + NIR camera architecture remains the best path** for production-grade iris recognition. It provides universal accuracy across all eye colors with proven hardware at ~$65 per capture point.

**Phone-based visible-light capture is a viable secondary mode** for scenarios where dedicated hardware isn't available (e.g., field enrollment, remote verification). Pursuing this would require:

1. Collecting a visible-light iris training dataset (or using UBIRIS.v2 / CUVIRIS)
2. Retraining the Open-IRIS segmentation model on VIS data (or building a VIS-specific pipeline)
3. Adding a phone-based capture mode to the web UI (camera API + quality gate)
4. Accepting reduced accuracy for dark-eyed subjects (~1–3% EER vs <0.5% NIR)

This could be a **Phase 8** addition after the core NIR pipeline is production-ready.

### 19.9 References

- ISO/IEC 19794-6:2011 — Biometric Data Interchange Formats: Iris Image Data
- ISO/IEC 29794-6:2015 — Biometric Sample Quality: Iris Image Data
- NIST IR 8252 — IREX IX Part Two: Multispectral Iris Recognition (2019)
- Trokielewicz et al., "Iris Recognition with a Smartphone Camera," arXiv:1809.00214 (2018)
- "Smartphone-based Iris Recognition through High-Quality Visible Spectrum Iris Capture," arXiv:2412.13063 (2024)
- "An Open-Source Framework for Quality-Assured Smartphone-Based Visible Light Iris Recognition" (CUVIRIS), arXiv:2512.15548 (2025)
- Daugman, "How Iris Recognition Works," IEEE TCSVT, vol. 14, no. 1 (2004)

---

## 20. References

### Iris Recognition — Foundational (including mobile/visible-light)

[1] J. Daugman, "High Confidence Visual Recognition of Persons by a Test of Statistical Independence," *IEEE Transactions on Pattern Analysis and Machine Intelligence*, vol. 15, no. 11, pp. 1148–1161, 1993. DOI: `10.1109/34.244676`

[2] J. Daugman, "The Importance of Being Random: Statistical Principles of Iris Recognition," *Pattern Recognition*, vol. 36, no. 2, pp. 279–291, 2003. DOI: `10.1016/S0031-3203(02)00030-4`

[3] J. Daugman, "How Iris Recognition Works," *IEEE Transactions on Circuits and Systems for Video Technology*, vol. 14, no. 1, pp. 21–30, 2004. DOI: `10.1109/TCSVT.2003.818350`

[4] J. Daugman, "New Methods in Iris Recognition," *IEEE Transactions on Systems, Man, and Cybernetics, Part B: Cybernetics*, vol. 37, no. 5, pp. 1167–1175, 2007. DOI: `10.1109/TSMCB.2007.903540`

[5] L. Masek, "Recognition of Human Iris Patterns for Biometric Identification," B.Sc. Thesis, School of Computer Science and Software Engineering, University of Western Australia, 2003. URL: https://www.peterkovesi.com/studentprojects/libor/LiborMasekThesis.pdf

### Open-IRIS & Segmentation Models

[6] Worldcoin AI, "IRIS: Iris Recognition Inference System of the Worldcoin Project," 2023. GitHub: https://github.com/worldcoin/open-iris

[7] M. Sandler, A. Howard, M. Zhu, A. Zhmoginov, and L.-C. Chen, "MobileNetV2: Inverted Residuals and Linear Bottlenecks," in *Proc. IEEE Conference on Computer Vision and Pattern Recognition (CVPR)*, pp. 4510–4520, 2018. DOI: `10.1109/CVPR.2018.00474`

[8] Z. Zhou, M. M. Rahman Siddiquee, N. Tajbakhsh, and J. Liang, "UNet++: A Nested U-Net Architecture for Medical Image Segmentation," in *Deep Learning in Medical Image Analysis and Multimodal Learning for Clinical Decision Support (DLMIA 2018)*, LNCS vol. 11045, pp. 3–11, 2018. DOI: `10.1007/978-3-030-00889-5_1`

[9] A. G. Roy, N. Navab, and C. Wachinger, "Concurrent Spatial and Channel 'Squeeze & Excitation' in Fully Convolutional Networks," in *Medical Image Computing and Computer Assisted Intervention (MICCAI 2018)*, LNCS vol. 11070, pp. 421–429, 2018. DOI: `10.1007/978-3-030-00928-1_48`

### Signal Processing & Feature Extraction

[10] D. J. Field, "Relations Between the Statistics of Natural Images and the Response Properties of Cortical Cells," *Journal of the Optical Society of America A*, vol. 4, no. 12, pp. 2379–2394, 1987. DOI: `10.1364/JOSAA.4.002379`

[11] I. Sobel and G. Feldman, "A 3x3 Isotropic Gradient Operator for Image Processing," presented at the Stanford Artificial Intelligence Project (SAIL), 1968. Referenced in: R. Duda and P. Hart, *Pattern Classification and Scene Analysis*, pp. 271–272, John Wiley & Sons, 1973.

### Object & Eye Detection

[12] P. Viola and M. J. Jones, "Robust Real-Time Face Detection," *International Journal of Computer Vision*, vol. 57, no. 2, pp. 137–154, 2004. DOI: `10.1023/B:VISI.0000013087.49260.fb`

[13] R. O. Duda and P. E. Hart, "Use of the Hough Transformation to Detect Lines and Curves in Pictures," *Communications of the ACM*, vol. 15, no. 1, pp. 11–15, 1972. DOI: `10.1145/361237.361242`

### Datasets

[14] Chinese Academy of Sciences' Institute of Automation (CASIA), "CASIA Iris Image Database," Version 4.0. URL: http://biometrics.idealtest.org/ — See also: Z. Sun, T. Tan, Y. Wang, and S. Z. Li, "Ordinal Measures for Iris Recognition," *IEEE Transactions on Pattern Analysis and Machine Intelligence*, vol. 31, no. 12, pp. 2211–2226, 2009. DOI: `10.1109/TPAMI.2008.240`

[15] K. W. Bowyer and P. J. Flynn, "The ND-IRIS-0405 Iris Image Dataset," arXiv preprint arXiv:1606.04853, 2016. URL: https://arxiv.org/abs/1606.04853

[16] H. Proenca, S. Filipe, R. Santos, J. Oliveira, and L. A. Alexandre, "The UBIRIS.v2: A Database of Visible Wavelength Iris Images Captured On-the-Move and At-a-Distance," *IEEE Transactions on Pattern Analysis and Machine Intelligence*, vol. 32, no. 8, pp. 1529–1535, 2010. DOI: `10.1109/TPAMI.2009.66`

### Mobile & Visible-Light Iris Recognition

[17] A. Trokielewicz, A. Czajka, and P. Maciejewicz, "Iris Recognition with a Smartphone Camera," in *Proc. International Conference of the Biometrics Special Interest Group (BIOSIG)*, 2018. arXiv: `1809.00214`

[18] NIST, "IREX IX Part Two: Multispectral Iris Recognition," NIST Interagency Report 8252, 2019. URL: https://nvlpubs.nist.gov/nistpubs/ir/2019/NIST.IR.8252.pdf

[19] "Smartphone-based Iris Recognition through High-Quality Visible Spectrum Iris Capture," arXiv preprint arXiv:2412.13063, 2024. URL: https://arxiv.org/abs/2412.13063

[20] "An Open-Source Framework for Quality-Assured Smartphone-Based Visible Light Iris Recognition" (CUVIRIS), arXiv preprint arXiv:2512.15548, 2025. URL: https://arxiv.org/abs/2512.15548

[21] ISO/IEC 19794-6:2011, "Information Technology — Biometric Data Interchange Formats — Part 6: Iris Image Data." URL: https://www.iso.org/standard/50868.html

[22] ISO/IEC 29794-6:2015, "Information Technology — Biometric Sample Quality — Part 6: Iris Image Data." URL: https://www.iso.org/standard/54066.html

---

*Architecture proposal for EyeD project - February 2026*
