# =============================================================================
# EyeD key-service: BFV secret key holder and decryption service
# Multi-stage build: OpenFHE + nats.c + key-service → minimal runtime image
# =============================================================================

# --- Stage 1: Build everything ---
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake g++ make git ca-certificates \
    libssl-dev libomp-dev \
    && rm -rf /var/lib/apt/lists/*

# Build OpenFHE C++ library
ARG OPENFHE_VERSION=v1.4.2
RUN git clone --depth 1 --branch ${OPENFHE_VERSION} \
        https://github.com/openfheorg/openfhe-development.git /tmp/openfhe && \
    cd /tmp/openfhe && mkdir build && cd build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_UNITTESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_BENCHMARKS=OFF \
        -DWITH_BE2=OFF \
        -DWITH_BE4=OFF && \
    make -j$(nproc) && make install && \
    rm -rf /tmp/openfhe

# Copy key-service source and build
# Build context is project root (.), so paths are relative to eyed/
COPY key-service/src/ /app/src/
COPY key-service/CMakeLists.txt /app/

WORKDIR /app/build
RUN cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DOpenFHE_DIR=/usr/local/lib/cmake/OpenFHE && \
    make -j$(nproc)

# --- Stage 2: Minimal runtime image ---
FROM ubuntu:22.04 AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy OpenFHE shared libraries
COPY --from=builder /usr/local/lib/libOpenFHE* /usr/local/lib/
COPY --from=builder /usr/local/lib/libOPENFHE* /usr/local/lib/

# Copy nats.c shared library (built by FetchContent in the app build tree)
COPY --from=builder /app/build/_deps/nats_c-build/src/libnats.so* /usr/local/lib/

# Copy key-service binary
COPY --from=builder /app/build/key-service /usr/local/bin/key-service

ENV LD_LIBRARY_PATH=/usr/local/lib
RUN ldconfig

# Key storage directory
RUN mkdir -p /keys
VOLUME /keys

# No external ports — NATS-only communication
ENV EYED_NATS_URL=nats://nats:4222
ENV EYED_HE_KEY_DIR=/keys
ENV EYED_LOG_LEVEL=info

CMD ["key-service"]
