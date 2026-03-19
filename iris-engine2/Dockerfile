# =============================================================================
# Stage 1: base-deps — OS + all third-party libraries
# =============================================================================
FROM ubuntu:24.04 AS base-deps

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    g++-13 \
    cmake \
    ninja-build \
    git \
    curl \
    ca-certificates \
    pkg-config \
    # OpenCV
    libopencv-dev \
    # yaml-cpp
    libyaml-cpp-dev \
    # spdlog
    libspdlog-dev \
    # nlohmann-json
    nlohmann-json3-dev \
    # Eigen
    libeigen3-dev \
    # PostgreSQL client library
    libpq-dev \
    # ONNX Runtime build deps
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set GCC 13 as default
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 100 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-13

# --- ONNX Runtime (prebuilt) ---
ARG ONNXRUNTIME_VERSION=1.17.3
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then ORT_ARCH="x64"; else ORT_ARCH="aarch64"; fi && \
    wget -q "https://github.com/microsoft/onnxruntime/releases/download/v${ONNXRUNTIME_VERSION}/onnxruntime-linux-${ORT_ARCH}-${ONNXRUNTIME_VERSION}.tgz" \
         -O /tmp/ort.tgz && \
    tar xzf /tmp/ort.tgz -C /opt/ && \
    mv /opt/onnxruntime-linux-${ORT_ARCH}-${ONNXRUNTIME_VERSION} /opt/onnxruntime && \
    rm /tmp/ort.tgz

ENV ONNXRUNTIME_ROOT=/opt/onnxruntime

# =============================================================================
# Stage 1b: openfhe — build OpenFHE from source
# =============================================================================
FROM base-deps AS openfhe

ARG OPENFHE_VERSION=v1.4.2

RUN git clone --depth 1 --branch ${OPENFHE_VERSION} \
    https://github.com/openfheorg/openfhe-development.git /tmp/openfhe && \
    cmake -S /tmp/openfhe -B /tmp/openfhe/build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/openfhe \
        -DBUILD_STATIC=ON \
        -DBUILD_SHARED=OFF \
        -DWITH_BE2=ON \
        -DWITH_BE4=OFF \
        -DWITH_NTL=OFF \
        -DBUILD_UNITTESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_BENCHMARKS=OFF \
        -DNATIVE_SIZE=64 && \
    cmake --build /tmp/openfhe/build --parallel $(nproc) && \
    cmake --install /tmp/openfhe/build && \
    rm -rf /tmp/openfhe

# =============================================================================
# Stage 2: build — compile libiris (with FHE) + service
# =============================================================================
FROM base-deps AS build

# Copy OpenFHE from stage 1b
COPY --from=openfhe /opt/openfhe /opt/openfhe
ENV OpenFHE_DIR=/opt/openfhe/lib/OpenFHE

WORKDIR /src

# Copy libiris from additional build context (resolves symlink via docker-compose)
COPY --from=libiris . libiris/

# Copy service source
COPY CMakeLists.txt .
COPY src/ src/

# Mode-based build flags:
#   dev  → Release (fast iteration)
#   test → Debug + sanitizers
#   prod → Release (default)
ARG EYED_MODE=prod
RUN if [ "$EYED_MODE" = "test" ]; then \
        BUILD_TYPE="Debug"; \
        EXTRA_FLAGS="-fsanitize=address,undefined"; \
    else \
        BUILD_TYPE="Release"; \
        EXTRA_FLAGS=""; \
    fi && \
    cmake -S . -B build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_CXX_FLAGS="-march=native ${EXTRA_FLAGS}" \
        -DCMAKE_EXE_LINKER_FLAGS="${EXTRA_FLAGS}" \
        -DONNXRUNTIME_ROOT=/opt/onnxruntime

# Build
RUN cmake --build build --parallel $(nproc)

# =============================================================================
# Stage 3: runtime — reuse base-deps (large but reliable for parity testing)
# =============================================================================
FROM base-deps AS runtime

RUN useradd -r -s /usr/sbin/nologin iris

# Copy ONNX Runtime shared library
COPY --from=build /opt/onnxruntime/lib/libonnxruntime.so* /usr/lib/

# Copy the service binary
COPY --from=build /src/build/iris-engine2 /usr/local/bin/iris-engine2

# Copy pipeline config
COPY --from=build /src/libiris/pipeline.yaml /src/libiris/pipeline.yaml

# FHE key directory (mounted at runtime via docker-compose volume)
RUN mkdir -p /keys && chown iris:iris /keys

# Config directory for FHE toggle persistence (mounted as fhe-config volume)
RUN mkdir -p /config && chown iris:iris /config

RUN ldconfig

USER iris
WORKDIR /opt/iris

EXPOSE 7000

CMD ["iris-engine2"]

# =============================================================================
# Stage 4: test — build and run unit tests
# =============================================================================
FROM base-deps AS test

# Copy OpenFHE for FHE-enabled tests
COPY --from=openfhe /opt/openfhe /opt/openfhe
ENV OpenFHE_DIR=/opt/openfhe/lib/OpenFHE

WORKDIR /src

# Copy libiris
COPY --from=libiris . libiris/

# Copy test source and CMakeLists
COPY CMakeLists.txt .
COPY src/ src/
COPY tests/ tests/

# Configure with tests enabled (FHE enabled via CMakeLists.txt)
RUN cmake -S . -B build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_FLAGS="-march=native" \
    -DONNXRUNTIME_ROOT=/opt/onnxruntime

# Build test executables
RUN cmake --build build --parallel $(nproc)

# Run tests
CMD ["cmake", "--build", "build", "--target", "test"]
