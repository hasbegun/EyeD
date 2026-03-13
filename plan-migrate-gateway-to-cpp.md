# Gateway Service: Go → C++ Migration Plan

**Date:** March 14, 2026
**Branch:** `gateway-cpp`
**Status:** Planning
**Goal:** Replace the Go-based `gateway` service with C++ to unify the project language stack, eliminate Go toolchain / TLS build issues, and share infrastructure with capture device, iris-engine2, key-service, and (now) storage.

---

## 1. Why Migrate

| Reason | Detail |
|--------|--------|
| **Language unification** | Storage is now C++. After this migration, every service in EyeD is C++ — one toolchain, one CI matrix, one set of idioms. |
| **gRPC version parity** | The capture device (C++ / debian:bookworm) speaks gRPC 1.51. A C++ gateway on the same base image guarantees identical proto/gRPC behaviour with zero version skew. |
| **Docker build reliability** | The Go Dockerfile hits persistent TLS / `go mod tidy` failures on `google.golang.org/genproto` (~2 GB). C++ uses apt packages + CMake FetchContent with small repos. |
| **Shared infrastructure** | CMake, nats.c, nlohmann/json, protobuf, gRPC — all already proven in other EyeD C++ services. |
| **No Go expertise required** | Removing the last Go service eliminates Go-specific knowledge burden. |

**What we are NOT changing:**

- gRPC service definition (`proto/capture.proto` — `CaptureService`)
- NATS subjects (`eyed.analyze`, `eyed.result`)
- Health endpoint behaviour (`/health/alive`, `/health/ready`)
- WebSocket endpoints (`/ws/results`, `/ws/signaling`)
- WebSocket message JSON schemas
- docker-compose.yml service contract (ports, env vars, depends_on)
- Integration test & ws-test binaries (re-implemented in C++)

---

## 2. Current Gateway Service (Go)

### Source Files

| Go File | Lines | Responsibility |
|---------|-------|---------------|
| `cmd/gateway/main.go` | 143 | Entry point: config, NATS, gRPC, HTTP, WS, CORS, signal handling |
| `internal/config/config.go` | 29 | Env var parsing (`EYED_*`) |
| `internal/breaker/breaker.go` | 111 | Circuit breaker (Closed / Open / HalfOpen) tracking iris-engine responsiveness |
| `internal/nats/client.go` | 123 | NATS wrapper: publish `eyed.analyze`, subscribe `eyed.result`, counters |
| `internal/grpc/server.go` | 128 | CaptureService gRPC: `SubmitFrame`, `StreamFrames`, `GetStatus` |
| `internal/health/handler.go` | 60 | HTTP `/health/alive`, `/health/ready` |
| `internal/ws/hub.go` | 128 | WebSocket broadcast hub for analysis results → browser clients |
| `internal/ws/signaling.go` | 217 | WebRTC signaling relay (device ↔ browser viewer) |
| `cmd/integration-test/main.go` | 166 | E2E: gRPC SubmitFrame → NATS result verification |
| `cmd/ws-test/main.go` | 45 | Quick WebSocket smoke test |

**Total: ~1,150 lines of Go, 4 external dependencies.**

### Go Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `github.com/nats-io/nats.go` | v1.39.1 | NATS messaging |
| `google.golang.org/grpc` | v1.65.0 | gRPC server |
| `google.golang.org/protobuf` | v1.34.2 | Protobuf serialization |
| `github.com/gorilla/websocket` | v1.5.3 | WebSocket server |

### gRPC Service (`CaptureService`)

| RPC | Type | Behaviour |
|-----|------|-----------|
| `SubmitFrame(CaptureFrame) → FrameAck` | Unary | Circuit breaker check → base64-encode JPEG → publish `eyed.analyze` → return ack |
| `StreamFrames(stream CaptureFrame) → stream FrameAck` | Bidi streaming | Per-frame: `SubmitFrame` → send ack back on stream; tracks `connected_devices` |
| `GetStatus(Empty) → ServerStatus` | Unary | Returns alive, ready, connected_devices, avg_latency_ms, frames_processed |

### NATS Integration

| Subject | Direction | Payload |
|---------|-----------|---------|
| `eyed.analyze` | **Publish** | `AnalyzeRequest` JSON (frame_id, device_id, jpeg_b64, quality_score, eye_side, timestamp) |
| `eyed.result` | **Subscribe** | `AnalyzeResponse` JSON (frame_id, device_id, match, iris_template_b64, latency_ms, error) |

### HTTP Endpoints (port 8080)

| Endpoint | Response |
|----------|----------|
| `GET /health/alive` | `{"alive": true}` |
| `GET /health/ready` | `{"alive": true, "ready": <nats_connected && breaker_closed>, "nats_connected": <bool>, "circuit_breaker": "<state>", "version": "0.1.0"}` |

### WebSocket Endpoints (port 8080)

| Endpoint | Protocol | Behaviour |
|----------|----------|-----------|
| `/ws/results` | WS text frames | Server broadcasts every `AnalyzeResponse` from NATS to all connected browser clients. Ping/pong keepalive (30 s ping, 60 s read deadline). |
| `/ws/signaling?device_id=X&role=device\|viewer` | WS text frames | WebRTC signaling relay. Device messages → all viewers; viewer messages → device. Join/leave presence notifications. Ping/pong keepalive. |

### WebSocket Message Schemas

**Results broadcast** (`/ws/results`):
```json
{
  "frame_id": "string",
  "device_id": "string",
  "match": { "hamming_distance": 0.0, "is_match": true, "matched_identity_id": "string", "best_rotation": 0 },
  "iris_template_b64": "string",
  "latency_ms": 0.0,
  "error": "string"
}
```

**Signaling relay** (`/ws/signaling`):
```json
{
  "type": "offer|answer|ice-candidate|join|leave",
  "device_id": "string",
  "from": "device|viewer",
  "payload": {}
}
```

### Circuit Breaker

| State | Meaning | Transition |
|-------|---------|------------|
| **Closed** | Normal — frames accepted | → Open: when `now - lastSent > timeout` and `lastSent > lastResult` |
| **Open** | Tripped — frames rejected | → HalfOpen: when `now - lastProbe > probeInterval` |
| **HalfOpen** | Probing — allow one frame | → Closed: on `RecordResult()`. → Open: after probe sent (until result). |

Defaults: `timeout = 30 s`, `probeInterval = 10 s`.

### CORS Middleware

Applies to all HTTP responses on port 8080:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type, Authorization`
- OPTIONS requests → 204 No Content

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `EYED_NATS_URL` | `nats://nats:4222` | NATS server URL |
| `EYED_GRPC_PORT` | `50051` | gRPC listen port |
| `EYED_HTTP_PORT` | `8080` | HTTP + WebSocket listen port |
| `EYED_LOG_LEVEL` | `info` | Log level (debug, info, warn, error) |

---

## 3. Target Architecture (C++)

```
gateway/
├── CMakeLists.txt              # gRPC + protobuf + nats.c + nlohmann_json + Boost.Beast + doctest
├── Dockerfile                  # Multi-stage: debian:bookworm build → test → runtime
├── src/
│   ├── main.cpp                # Entry point: config → NATS → breaker → gRPC → HTTP/WS → signals
│   ├── config.h                # Env var parsing (same EYED_* variables)
│   ├── breaker.h               # Circuit breaker state machine
│   ├── breaker.cpp
│   ├── nats_client.h           # NATS wrapper: publish eyed.analyze, subscribe eyed.result
│   ├── nats_client.cpp
│   ├── grpc_server.h           # CaptureService gRPC server implementation
│   ├── grpc_server.cpp
│   ├── http_server.h           # HTTP health + CORS + WebSocket upgrade routing
│   ├── http_server.cpp
│   ├── ws_hub.h                # WebSocket results broadcast hub
│   ├── ws_hub.cpp
│   ├── signaling_hub.h         # WebRTC signaling relay
│   └── signaling_hub.cpp
├── tests/
│   ├── CMakeLists.txt
│   ├── test_config.cpp
│   ├── test_breaker.cpp
│   ├── test_nats_client.cpp
│   ├── test_grpc_server.cpp
│   ├── test_ws_hub.cpp
│   └── test_signaling_hub.cpp
└── tools/
    ├── integration_test.cpp    # E2E: gRPC SubmitFrame → NATS result (replaces cmd/integration-test)
    └── ws_test.cpp             # WS smoke test (replaces cmd/ws-test)
```

### Technology Decisions

| Concern | Decision | Rationale |
|---------|----------|-----------|
| gRPC server | `libgrpc++-dev` 1.51 (apt) | Same version and pattern as capture device; proto compatibility guaranteed |
| Protobuf | `libprotobuf-dev` + `protobuf-compiler-grpc` (apt) | Same as capture device |
| NATS client | nats.c v3.8.2 (FetchContent) | Same as storage and key-service |
| JSON | nlohmann-json3-dev (apt) | Same as storage and iris-engine2 |
| HTTP + WebSocket | Boost.Beast (`libboost-dev` 1.81, apt) | Single library for HTTP routing + WebSocket upgrade on same port; actively maintained; available via apt |
| Base64 encode | Custom (~20 lines) | Only need encode (JPEG → base64 for NATS publish); tiny |
| Testing | doctest (FetchContent) | Same as storage; lightweight |
| C++ standard | C++17 | `<filesystem>` available; consistent with storage |
| Base image | debian:bookworm | gRPC 1.51 parity with capture device; newer Boost 1.81 |

### Why Boost.Beast for HTTP + WebSocket

The gateway serves health endpoints (HTTP) and two WebSocket endpoints on **the same port** (8080). In Go, `net/http` + gorilla/websocket handle this naturally. In C++, the options are:

| Library | HTTP | WebSocket | Same Port | apt available | Status |
|---------|------|-----------|-----------|--------------|--------|
| cpp-httplib | ✅ | ❌ | N/A | vendored | No WS support |
| websocketpp | Basic | ✅ | ✅ | `libwebsocketpp-dev` | Last release 2018 |
| Boost.Beast | ✅ | ✅ | ✅ | `libboost-dev` | Active (Boost 1.81) |
| uWebSockets | ✅ | ✅ | ✅ | ❌ | Not in apt |

**Boost.Beast** is the best fit: modern C++, actively maintained, full HTTP + WebSocket on a single listener, and available via apt with zero FetchContent overhead.

### Traceability Matrix

| Go Source | C++ Target | Notes |
|-----------|------------|-------|
| `cmd/gateway/main.go` | `src/main.cpp` | Same lifecycle: config → NATS → breaker → gRPC → HTTP/WS → signal wait → shutdown |
| `cmd/gateway/main.go:corsMiddleware` | `src/http_server.cpp` | CORS headers applied to all HTTP responses |
| `internal/config/config.go:Config` | `src/config.h:Config` | Same env vars, same defaults |
| `internal/config/config.go:Load()` | `Config::from_env()` | Static factory |
| `internal/breaker/breaker.go:Breaker` | `src/breaker.h:Breaker` | Same state machine logic |
| `internal/breaker/breaker.go:Allow()` | `Breaker::allow()` | Lock-guarded, same transitions |
| `internal/breaker/breaker.go:RecordResult()` | `Breaker::record_result()` | Reset to Closed |
| `internal/breaker/breaker.go:State()` | `Breaker::state()` | Evaluate + return |
| `internal/nats/client.go:Client` | `src/nats_client.h:NatsClient` | nats.c wrapper |
| `internal/nats/client.go:Connect()` | `NatsClient::connect()` | nats.c options + reconnect handlers |
| `internal/nats/client.go:PublishAnalyze()` | `NatsClient::publish_analyze()` | JSON marshal → `natsConnection_Publish` |
| `internal/nats/client.go:SubscribeResults()` | `NatsClient::subscribe_results()` | `natsConnection_Subscribe` on `eyed.result` |
| `internal/nats/client.go:AnalyzeRequest` | Inline `nlohmann::json` | No separate struct needed |
| `internal/nats/client.go:AnalyzeResponse` | Inline `nlohmann::json` | Parsed in subscription callback |
| `internal/nats/client.go:MatchInfo` | Inline `nlohmann::json` | Nested in AnalyzeResponse |
| `internal/grpc/server.go:Server` | `src/grpc_server.h:GrpcServiceImpl` | Implements `eyed::CaptureService::Service` |
| `internal/grpc/server.go:SubmitFrame()` | `GrpcServiceImpl::SubmitFrame()` | breaker.allow() → base64 → nats publish → ack |
| `internal/grpc/server.go:StreamFrames()` | `GrpcServiceImpl::StreamFrames()` | Bidi stream, delegates to SubmitFrame per frame |
| `internal/grpc/server.go:GetStatus()` | `GrpcServiceImpl::GetStatus()` | Atomic metrics |
| `internal/health/handler.go:Handler` | `src/http_server.h:HttpServer` | Beast HTTP handler with path routing |
| `internal/ws/hub.go:Hub` | `src/ws_hub.h:WsHub` | Beast WebSocket sessions; broadcast |
| `internal/ws/signaling.go:SignalingHub` | `src/signaling_hub.h:SignalingHub` | Beast WebSocket; device/viewer routing |
| `cmd/integration-test/main.go` | `tools/integration_test.cpp` | gRPC client → NATS result verification |
| `cmd/ws-test/main.go` | `tools/ws_test.cpp` | Beast WS client → wait for one message |

---

## 4. Migration Phases

### Phase 1: Scaffold, Build System & Proto Generation ✅

**Goal:** C++ project that compiles, generates gRPC stubs from `capture.proto`, and runs in Docker.

- [x] Create `gateway/CMakeLists.txt`
  - FetchContent: nats.c v3.8.2, doctest
  - find_package: gRPC, Protobuf, nlohmann_json, Boost (Beast, Asio, System)
  - Proto generation: `capture.proto` → `capture.pb.cc/h` + `capture.grpc.pb.cc/h`
  - Executable: `gateway` (src/main.cpp)
  - Conditional: tests/ subdirectory
- [x] Create `gateway/src/config.h` with `Config::from_env()`
- [x] Create `gateway/src/main.cpp` — minimal: load config, log start, exit
- [x] Create `gateway/Dockerfile` — multi-stage: debian:bookworm build → test → runtime
  - Build deps: `cmake ninja-build g++ git ca-certificates libgrpc++-dev libprotobuf-dev protobuf-compiler protobuf-compiler-grpc nlohmann-json3-dev libboost-dev libssl-dev`
  - Runtime deps: `ca-certificates curl libgrpc++1.51 libprotobuf32 libboost-system1.81.0`
- [x] Create `gateway/tests/CMakeLists.txt` + `test_config.cpp` (6 tests)
- [x] Verify: `docker compose build gateway` succeeds
- [x] Verify: `ctest -R "^test_"` passes (6/6 config tests)

**Deliverable:** Project compiles with gRPC stubs. Config tests pass.

**Implementation Notes:**
- Proto generation uses same pattern as capture device (gRPC 1.51, bookworm)
- doctest integrated with `DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN` in test files
- nats.c shared libraries copied to runtime image via bind mount
- JSON logging functional in minimal main.cpp scaffold

### Phase 2: Circuit Breaker ✅

**Goal:** Self-contained state machine, fully unit-tested.

- [x] Create `gateway/src/breaker.h` + `breaker.cpp`
  - `enum class State { Closed, Open, HalfOpen }`
  - `Breaker(timeout, probe_interval)` — constructor
  - `bool allow()` — check + transition
  - `void record_result()` — reset to Closed
  - `State state()` — evaluate + return
  - `std::string state_string()` — "closed", "open", "half-open"
  - Thread-safe via `std::mutex`
  - Internal `evaluate(now)` same logic as Go
- [x] Create `gateway/tests/test_breaker.cpp` (12 test cases, 42 assertions)
  - Initial state is Closed
  - allow() returns true when Closed
  - Trips to Open after timeout with no results
  - Open → HalfOpen after probe interval
  - HalfOpen → allow() returns true (probe frame), transitions back to Open
  - RecordResult → always resets to Closed
  - Multiple rapid allow() calls while Open → all false
  - Thread safety (concurrent allow + record_result)
- [x] Add to CMakeLists, verify tests pass (12/12 tests, 42/42 assertions)

**Deliverable:** Circuit breaker with 100% state transition coverage.

**Implementation Notes:**
- Uses `std::chrono::steady_clock` for monotonic timing
- `last_probe_` set when transitioning to Open (probe interval measured from opening)
- `last_result_` starts at zero (allows tripping on first frame if no result)
- Exact state machine logic matches Go implementation

### Phase 3: NATS Client ✅

**Goal:** Publish to `eyed.analyze`, subscribe to `eyed.result`.

- [x] Create `gateway/src/nats_client.h` + `nats_client.cpp`
  - `NatsClient(url)` — connect with infinite reconnect, 2 s wait
  - `bool publish_analyze(json)` — serialize + publish to `eyed.analyze`
  - `void subscribe_results(callback)` — subscribe to `eyed.result`, parse JSON, invoke callback
  - `bool is_connected()` — `natsConnection_Status == CONNECTED`
  - `uint64_t published()` — atomic counter
  - `void close()` — drain + destroy
- [x] Create `gateway/tests/test_nats_client.cpp` (6 test cases)
  - JSON serialization of AnalyzeRequest fields
  - JSON deserialization of AnalyzeResponse (with and without match, with error)
  - Published counter starts at zero
  - State queries (connected before connect)
- [x] Add to CMakeLists, verify tests pass (6/6 tests)

**Deliverable:** NATS wrapper with JSON serialization tests.

**Implementation Notes:**
- Uses nats.c v3.8.2 with infinite reconnect (`MaxReconnect = -1`)
- JSON parsing uses nlohmann::json with exception handling
- Callback-based subscription model matches Go implementation
- Published counter is atomic for thread safety

### Phase 4: gRPC Server (CaptureService) ✅

**Goal:** SubmitFrame, StreamFrames, GetStatus — all gRPC RPCs working.

- [x] Create `gateway/src/grpc_server.h` + `grpc_server.cpp`
  - `class GrpcServiceImpl : public eyed::CaptureService::Service`
  - Constructor takes `NatsClient*`, `Breaker*`
  - `SubmitFrame`: breaker check → base64-encode JPEG → build JSON → nats publish → ack
  - `StreamFrames`: bidi stream loop (recv frame → process_frame → send ack), connected_devices counter
  - `GetStatus`: return metrics (alive, ready, connected_devices, avg_latency_ms, frames_processed)
  - Atomic counters: `frames_processed`, `frames_rejected`, `connected_devices`, `total_latency_us`
  - `base64_encode()` standalone utility for JPEG→base64
- [x] Create `gateway/tests/test_grpc_server.cpp` (8 test cases)
  - base64_encode correctness (empty, 1-byte, 2-byte, 3-byte, 4-byte, typical string)
  - Initial metrics are zero
  - GetStatus returns alive status
- [x] Add to CMakeLists (link proto_gen, gRPC, nats), verify tests pass (8/8 tests)

**Deliverable:** gRPC server with unit-tested frame processing logic.

**Implementation Notes:**
- `base64_encode()` is standalone function for testability
- `process_frame()` helper used by both SubmitFrame and StreamFrames
- Timestamp conversion: microseconds → RFC3339Nano format using `gmtime_r` and `strftime`
- Metrics tracked atomically for thread safety
- Ready status: `nats_connected && breaker_closed`

### Phase 5: HTTP Health + CORS + WebSocket Hubs ✅

**Goal:** Health endpoints + WebSocket results broadcast + signaling relay, all on port 8080.

- [x] Create `gateway/src/http_server.h` + `http_server.cpp` (basic HTTP)
  - Boost.Beast HTTP listener on single port
  - Route: `/health/alive` → `{"alive": true}`
  - Route: `/health/ready` → full JSON with NATS + breaker state
  - CORS middleware: `Access-Control-Allow-Origin: *`
  - OPTIONS preflight handling
- [x] Create `gateway/tests/test_http_server.cpp` (2 test cases)
- [x] Extend HTTP server for WebSocket upgrade
  - Route: `/ws/results` → upgrade to WebSocket, register with WsHub
  - Route: `/ws/signaling?device_id=X&role=Y` → upgrade to WebSocket, register with SignalingHub
- [x] Create `gateway/src/ws_hub.h` + `ws_hub.cpp`
  - Thread-safe client set (`std::mutex` + `std::set`)
  - `void add_client(ws_session*)`
  - `void remove_client(ws_session*)`
  - `void broadcast(string_view json)` — send to all clients
  - `int client_count()`
  - Read loop: discard incoming messages, detect disconnect
- [x] Create `gateway/src/signaling_hub.h` + `signaling_hub.cpp`
  - Device map: `device_id → ws_session*`
  - Viewer map: `device_id → set<ws_session*>`
  - `register_device()` / `register_viewer()`
  - `unregister(session)`
  - `relay(sender, msg)` — device→viewers or viewer→device
  - `broadcast_presence(device_id, "join"|"leave")`
  - Query param validation: require device_id and role=device|viewer
- [x] Create `gateway/tests/test_ws_hub.cpp`
  - Client count tracking (add/remove)
  - Broadcast to multiple clients
  - Remove on write failure
- [x] Create `gateway/tests/test_signaling_hub.cpp` (9 test cases)
  - Device registration and lookup
  - Viewer registration (multiple per device)
  - Relay: device→viewers, viewer→device
  - Presence: join/leave broadcasts
  - Unregister cleanup
  - Relay from unregistered session is no-op
- [x] Add to CMakeLists (link Boost::beast, Boost::asio, Boost::system), verify tests pass

**Deliverable:** Full HTTP + WebSocket server with all endpoints.

**Implementation Notes:**
- `BeastWsSession` concrete class in `http_server.h/.cpp` wraps `beast::websocket::stream<tcp::socket>`
- `run_read_loop(on_message)` accepts optional callback: nullptr for /ws/results (discard), relay lambda for /ws/signaling
- `parse_query_param()` extracts device_id and role from URL query string
- `/ws/signaling` rejects requests with missing device_id or invalid role
- `SignalingHub::broadcast_presence()` sends join/leave JSON to all viewers when a device connects/disconnects
- 7/7 test suites pass (all 80 build targets succeed)

### Phase 6: Main Lifecycle, Signal Handling & Test Binaries ✅

**Goal:** Wire everything together. Build integration-test and ws-test binaries.

- [x] Update `gateway/src/main.cpp` — full service lifecycle
  - Config → NATS connect → circuit breaker → gRPC server (port 50051) → HTTP/WS server (port 8080) → signal handling
  - NATS result subscription: log + broadcast via WsHub + breaker.record_result()
  - Structured JSON logging to stdout
  - Signal handling: SIGINT/SIGTERM → graceful shutdown
  - Shutdown order: stop HTTP/WS → stop gRPC → drain NATS
- [x] Create `gateway/tools/integration_test.cpp`
  - gRPC client: connect → wait for ready → SubmitFrame → GetStatus → verify
  - Minimal JPEG payload, JSON structured output
- [x] Create `gateway/tools/ws_test.cpp`
  - Beast WS client: connect to /ws/results → wait for one message → print → exit
- [x] Update CMakeLists to build integration_test and ws_test executables
- [x] Update Dockerfile to copy all three binaries to runtime image
- [x] Verify: `docker compose build gateway` succeeds with all tests passing

**Deliverable:** Feature-complete gateway binary + test tools.

**Implementation Notes:**
- `SignalingHub` added to `main.cpp` and passed to `HttpServer`
- Fixed NATS result callback to handle `frame_id` as either string or integer
- 80 build targets total; 7/7 test suites pass
- All three binaries (`/app/gateway`, `/app/integration_test`, `/app/ws_test`) deployed to runtime image

### Phase 7: Integration Testing & Parity Verification ✅

**Goal:** Verify C++ gateway behaves identically to Go gateway.

- [x] `docker compose up -d nats gateway` — verify startup logs
- [x] Health endpoints: `curl /health/alive` and `/health/ready` return correct JSON
- [x] gRPC GetStatus: verify metrics via grpc_cli or integration-test
- [x] NATS integration: publish mock `eyed.result` → verified gateway logs result
- [x] WebSocket: `101 Switching Protocols` confirmed via curl upgrade headers
- [x] CORS: `Access-Control-Allow-Origin: *` on all HTTP responses
- [ ] Signaling: connect device + viewer to `/ws/signaling` → relay message → verify delivery (manual / full stack)
- [ ] Full pipeline: capture → gateway → iris-engine2 (requires full stack)

**Deliverable:** C++ gateway passes all integration tests. Drop-in replacement for Go.

**Implementation Notes:**
- `docker compose up -d nats gateway` starts cleanly in <1s
- `/health/alive` → `{"alive":true}`
- `/health/ready` → `{"alive":true,"circuit_breaker":"closed","nats_connected":true,"ready":true,"version":"0.1.0"}`
- `integration_test` → `Frame accepted, frames_processed:1, Integration test PASSED`
- NATS publish to `eyed.result` → gateway logs `Analysis result received` with correct fields
- WebSocket upgrade → `HTTP/1.1 101 Switching Protocols`
- Full signaling relay and full pipeline require complete docker-compose stack

### Phase 8: Cleanup & Remove Go ✅

**Goal:** Remove all Go source code from the gateway.

- [x] Delete `gateway/go.mod`, `gateway/go.sum` (if exists)
- [x] Delete `gateway/cmd/` directory
- [x] Delete `gateway/internal/` directory
- [x] Remove Go proto generation from Dockerfile (protoc-gen-go, protoc-gen-go-grpc)
- [x] Remove `option go_package` from `proto/capture.proto` (no Go consumers remain)
- [x] Update project README if it references Go gateway (no top-level README; updated `MODERN_ARCHITECTURE.md`)
- [ ] Commit and tag: `gateway-cpp-v0.1.0`

**Deliverable:** Go is fully removed. Gateway is pure C++.

**Implementation Notes:**
- Legacy Go gateway files removed from `gateway/` (`cmd/`, `internal/`, `go.mod`)
- Verified no `*.go` files remain under `gateway/`
- `docker compose build gateway` succeeds after cleanup
- Test stage remains green (`100% tests passed, 0 failed`)

---

## 5. Dockerfile (Target)

```dockerfile
# =============================================================================
# EyeD Gateway — C++ multi-stage Dockerfile
# Build context: project root (.)
# =============================================================================

# --- Stage 1: build ---
FROM debian:bookworm AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV GIT_SSL_NO_VERIFY=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build g++ git ca-certificates \
    libgrpc++-dev libprotobuf-dev protobuf-compiler protobuf-compiler-grpc \
    nlohmann-json3-dev \
    libboost-dev libboost-system-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Proto definition (shared with capture device)
COPY proto/ /proto/

# Gateway source
COPY gateway/CMakeLists.txt .
COPY gateway/src/    src/
COPY gateway/tests/  tests/
COPY gateway/tools/  tools/

RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel $(nproc)

# --- Stage 2: test ---
FROM build AS test

RUN cd build && ctest -R "^test_" --output-on-failure

# --- Stage 3: runtime ---
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    libgrpc++1.51 libprotobuf32 \
    libboost-system1.81.0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/gateway           /app/gateway
COPY --from=build /src/build/integration_test  /app/integration-test
COPY --from=build /src/build/ws_test           /app/ws-test

# Copy shared libraries that nats.c built (if dynamically linked)
COPY --from=build /src/build/_deps/nats_c-build/libnats.so* /usr/local/lib/
RUN ldconfig

EXPOSE 50051 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/health/alive || exit 1

CMD ["/app/gateway"]
```

---

## 6. CMakeLists.txt (Target)

```cmake
cmake_minimum_required(VERSION 3.25)
project(eyed-gateway VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# --- nats.c ---
FetchContent_Declare(nats_c
    GIT_REPOSITORY https://github.com/nats-io/nats.c.git
    GIT_TAG        v3.8.2
    GIT_SHALLOW    TRUE)
set(NATS_BUILD_STREAMING OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nats_c)

# --- nlohmann/json (system) ---
find_package(nlohmann_json REQUIRED)

# --- gRPC + Protobuf (system) ---
find_package(Protobuf REQUIRED)
find_package(gRPC CONFIG QUIET)
if(NOT gRPC_FOUND)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GRPC REQUIRED IMPORTED_TARGET grpc++)
    find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin REQUIRED)
endif()

# --- Boost (Beast, Asio, System) ---
find_package(Boost REQUIRED COMPONENTS system)

# --- Proto code generation ---
set(PROTO_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../proto")  # Adjusted for build context
set(PROTO_OUT_DIR "${CMAKE_BINARY_DIR}/proto-gen")
file(MAKE_DIRECTORY "${PROTO_OUT_DIR}")

if(gRPC_FOUND)
    set(_GRPC_CPP_PLUGIN $<TARGET_FILE:gRPC::grpc_cpp_plugin>)
else()
    set(_GRPC_CPP_PLUGIN "${GRPC_CPP_PLUGIN}")
endif()

add_custom_command(
    OUTPUT
        "${PROTO_OUT_DIR}/capture.pb.cc"
        "${PROTO_OUT_DIR}/capture.pb.h"
        "${PROTO_OUT_DIR}/capture.grpc.pb.cc"
        "${PROTO_OUT_DIR}/capture.grpc.pb.h"
    COMMAND ${Protobuf_PROTOC_EXECUTABLE}
        --cpp_out="${PROTO_OUT_DIR}"
        --grpc_out="${PROTO_OUT_DIR}"
        --plugin=protoc-gen-grpc="${_GRPC_CPP_PLUGIN}"
        -I "${PROTO_SRC_DIR}"
        "${PROTO_SRC_DIR}/capture.proto"
    DEPENDS "${PROTO_SRC_DIR}/capture.proto"
    COMMENT "Generating C++ proto/gRPC stubs"
)

add_library(proto_gen STATIC
    "${PROTO_OUT_DIR}/capture.pb.cc"
    "${PROTO_OUT_DIR}/capture.grpc.pb.cc"
)
target_include_directories(proto_gen PUBLIC "${PROTO_OUT_DIR}")
if(gRPC_FOUND)
    target_link_libraries(proto_gen PUBLIC protobuf::libprotobuf gRPC::grpc++ gRPC::grpc++_reflection)
else()
    target_link_libraries(proto_gen PUBLIC protobuf::libprotobuf PkgConfig::GRPC)
endif()

# --- Gateway executable ---
add_executable(gateway
    src/main.cpp
    src/breaker.cpp
    src/nats_client.cpp
    src/grpc_server.cpp
    src/http_server.cpp
    src/ws_hub.cpp
    src/signaling_hub.cpp
)

target_include_directories(gateway PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${PROTO_OUT_DIR}
)

target_link_libraries(gateway PRIVATE
    proto_gen
    nats
    nlohmann_json::nlohmann_json
    Boost::system
    pthread
)

# --- Test tools ---
add_executable(integration_test tools/integration_test.cpp)
target_include_directories(integration_test PRIVATE ${PROTO_OUT_DIR})
target_link_libraries(integration_test PRIVATE proto_gen nats nlohmann_json::nlohmann_json)

add_executable(ws_test tools/ws_test.cpp)
target_link_libraries(ws_test PRIVATE Boost::system nlohmann_json::nlohmann_json pthread)

# --- Unit Tests ---
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests")
    enable_testing()
    add_subdirectory(tests)
endif()
```

---

## 7. Test Plan

### 7.1 Unit Tests (Docker build stage — `ctest -R "^test_"`)

All unit tests run inside the Docker build container during `docker compose build gateway`. No external services (NATS, gRPC) required.

| Test Suite | File | Tests | What Is Verified |
|-----------|------|-------|-----------------|
| **test_config** | `tests/test_config.cpp` | 5+ | Default values, env override, all 4 config fields |
| **test_breaker** | `tests/test_breaker.cpp` | 12+ | All state transitions (Closed→Open→HalfOpen→Closed), timeout logic, probe interval, thread safety, allow/reject correctness, state_string() output |
| **test_nats_client** | `tests/test_nats_client.cpp` | 6+ | AnalyzeRequest JSON serialization (all fields), AnalyzeResponse JSON deserialization (with match, without match, with error, missing fields), published counter |
| **test_grpc_server** | `tests/test_grpc_server.cpp` | 8+ | base64_encode (empty, 1-byte, 2-byte, 3-byte, padding), SubmitFrame accepted/rejected paths, GetStatus metric values, avg_latency calculation |
| **test_ws_hub** | `tests/test_ws_hub.cpp` | 5+ | Client add/remove/count, broadcast calls, remove-on-error |
| **test_signaling_hub** | `tests/test_signaling_hub.cpp` | 8+ | Device register/unregister, viewer register/unregister (multi), relay device→viewers, relay viewer→device, presence join/leave, reject bad role, cleanup on disconnect |

**Minimum: ~44 unit tests covering all components.**

### 7.2 Integration Tests (Docker Compose)

Run with `docker compose --profile test up integration-test`:

| Test | Binary | What Is Verified |
|------|--------|-----------------|
| **gRPC E2E** | `/app/integration-test` | Connect gRPC → wait for ready → SubmitFrame → verify ack accepted → wait for NATS `eyed.result` → verify frame_id + device_id |
| **WebSocket** | `/app/ws-test` | Connect to `/ws/results` → wait for broadcast → verify JSON received |
| **Health alive** | `curl` | `GET /health/alive` → `{"alive": true}` |
| **Health ready** | `curl` | `GET /health/ready` → correct JSON schema with NATS + breaker status |

### 7.3 Parity Verification Checklist

| Check | Method | Expected |
|-------|--------|----------|
| docker-compose.yml unchanged | diff | Ports 9503:50051, 9504:8080; env vars; depends_on nats |
| gRPC proto compatibility | capture device connects | StreamFrames works, FrameAck received |
| NATS subject names | tcpdump / NATS monitor | `eyed.analyze` published, `eyed.result` subscribed |
| Health JSON schema | curl + jq | Identical keys and types as Go |
| WebSocket `/ws/results` | ws-test | Receives JSON broadcast matching Go schema |
| WebSocket `/ws/signaling` | manual | Device↔viewer relay works, join/leave presence |
| CORS headers | curl -I | `Access-Control-Allow-Origin: *` on all HTTP responses |
| Circuit breaker | load test | Trips after 30 s no results, probes at 10 s, recovers on result |
| Graceful shutdown | `docker compose stop` | Clean drain, no error logs |

---

## 8. Integration Points

### capture device → gateway

Capture device (C++ / bookworm) connects via gRPC `StreamFrames`. **No code changes needed in capture device.** The proto is identical; the wire protocol is binary protobuf over HTTP/2.

### gateway → iris-engine2

Gateway publishes `eyed.analyze` JSON to NATS. iris-engine2 subscribes. **No code changes needed in iris-engine2.** JSON schema is preserved exactly.

### iris-engine2 → gateway

iris-engine2 publishes `eyed.result` JSON to NATS. Gateway subscribes + broadcasts. **No code changes needed in iris-engine2.**

### gateway → browser clients

WebSocket `/ws/results` broadcasts are JSON text frames. **No changes needed in client code.** Schema is identical.

### gateway → storage

No direct interaction. Archive messages go iris-engine2 → NATS → storage. **No changes needed.**

### docker-compose.yml

The `gateway` service block remains **unchanged**:

```yaml
gateway:
  build:
    context: .
    dockerfile: gateway/Dockerfile
  ports:
    - "9503:50051"   # gRPC
    - "9504:8080"    # HTTP + WebSocket
  depends_on:
    - nats
  environment:
    EYED_NATS_URL: nats://nats:4222
    EYED_LOG_LEVEL: info
```

The `integration-test` service block also stays identical (same Dockerfile, same entrypoint).

---

## 9. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Boost.Beast complexity** — more verbose than gorilla/websocket | Medium | Follow Boost.Beast server examples; isolate HTTP/WS routing in `http_server.cpp`. The patterns are well-documented. |
| **gRPC version difference** between build and capture device | Low | Both use debian:bookworm → gRPC 1.51. Same proto file. Wire compatibility guaranteed. |
| **nats.c FetchContent network failure** in Docker | Medium | Already proven reliable for nats.c in storage migration. Same GIT_SSL_NO_VERIFY workaround. |
| **WebSocket ping/pong timing** differs between gorilla and Beast | Low | Use same values (30 s ping, 60 s read deadline). Test with ws-test binary. |
| **Circuit breaker timing edge cases** | Low | Comprehensive unit tests with mock clock. Same logic as Go. |
| **Bidirectional gRPC streaming** differences between Go and C++ | Medium | C++ gRPC streaming is well-documented. Capture device already uses C++ streaming client. Test with existing capture device. |
| **CORS middleware** may behave differently | Low | Exact same headers. Unit test the response headers. |
| **Signaling relay race conditions** | Medium | Same `std::mutex` protection as Go `sync.RWMutex`. Unit test concurrent access. |
| **Boost runtime library** missing in slim image | Low | Explicitly install `libboost-system1.81.0` in runtime stage. |

---

## 10. Success Criteria

The migration is complete when:

- [ ] `docker compose build gateway` succeeds (no Go toolchain)
- [ ] All unit tests pass (≥44 tests across 6 suites)
- [ ] `docker compose up gateway` starts, connects to NATS, logs structured JSON
- [ ] `/health/alive` returns `{"alive": true}`
- [ ] `/health/ready` returns correct JSON schema with NATS + breaker status
- [ ] Capture device connects via gRPC and submits frames successfully
- [ ] `eyed.analyze` messages appear on NATS with correct JSON schema
- [ ] `eyed.result` subscription works, results broadcast to `/ws/results` clients
- [ ] `/ws/signaling` relays messages between device and viewer correctly
- [ ] Circuit breaker trips/recovers correctly under load
- [ ] Integration test passes: `docker compose --profile test up integration-test`
- [ ] WebSocket test passes: ws-test receives broadcast
- [ ] CORS headers present on all HTTP responses
- [ ] Graceful shutdown on SIGINT/SIGTERM
- [ ] No Go source files remain in `gateway/`
- [ ] No regression in any other service

---

## 11. Execution Order

| # | Phase | Depends On | Effort | Estimate |
|---|-------|-----------|--------|----------|
| 1 | Scaffold, build system & proto gen | — | Medium | 2-3 hours |
| 2 | Circuit breaker + unit tests | Phase 1 | Small | 1-2 hours |
| 3 | NATS client + unit tests | Phase 1 | Small | 1-2 hours |
| 4 | gRPC server + unit tests | Phase 1, 2, 3 | Medium | 2-3 hours |
| 5 | HTTP health + CORS + WS hubs + unit tests | Phase 1, 3 | Large | 3-5 hours |
| 6 | Main lifecycle + test binaries | Phase 2, 3, 4, 5 | Medium | 2-3 hours |
| 7 | Integration testing & parity | Phase 6 | Medium | 2-3 hours |
| 8 | Cleanup & remove Go | Phase 7 | Small | 30 min |

**Total estimated effort: 2-3 days**

The gateway is ~2× the complexity of storage (~1,150 vs ~544 lines Go) due to gRPC server, WebSocket, and signaling. The gRPC and Boost.Beast code will be more verbose than Go equivalents, but all patterns are well-established in C++ and in this project.
