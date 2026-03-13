# =============================================================================
# EyeD storage service — C++ rewrite
# Multi-stage: ubuntu:22.04 build → ubuntu:22.04 runtime
# Build context: project root (.)
# =============================================================================

# --- Stage 1: build ---
FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV GIT_SSL_NO_VERIFY=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build g++ git ca-certificates \
    libssl-dev nlohmann-json3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Copy source, tests, and vendored headers (cpp-httplib is vendored to avoid
# network downloads inside Docker).
COPY storage/CMakeLists.txt .
COPY storage/src/          src/
COPY storage/tests/        tests/
COPY storage/vendor/       vendor/

RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel $(nproc)

# --- Stage 2: test (inherit build, only run ctest — no re-download) ---
FROM build AS test

RUN cd build && ctest -R "^test_" --output-on-failure

# --- Stage 3: runtime ---
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/_deps/nats_c-build/src/libnats.so* /usr/local/lib/
COPY --from=build /src/build/storage /app/storage

RUN ldconfig

EXPOSE 8082

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8082/health/alive || exit 1

CMD ["/app/storage"]
