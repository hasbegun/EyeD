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
COPY --from=build /src/build/tools/integration_test /app/integration_test
COPY --from=build /src/build/tools/ws_test          /app/ws_test

EXPOSE 50051 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/health/alive || exit 1

CMD ["/app/gateway"]
