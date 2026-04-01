# =============================================================================
# SMPC Participant Service
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
    libpq-dev \
    libopencv-dev \
    libyaml-cpp-dev \
    libspdlog-dev \
    nlohmann-json3-dev \
    libeigen3-dev \
    libssl-dev \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 100 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-13

# ONNX Runtime (required by libiris even if participant doesn't use pipeline)
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
# Build stage
# =============================================================================
FROM base-deps AS build

WORKDIR /src

# Copy libiris
COPY .libiris/iris/ libiris/

# Copy participant source and root CMakeLists
COPY CMakeLists.txt .
COPY src/ src/
COPY smpc-party/ smpc-party/

RUN cmake -S . -B build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-march=native" \
    -DONNXRUNTIME_ROOT=/opt/onnxruntime

RUN cmake --build build --parallel $(nproc) --target smpc-party

# =============================================================================
# Runtime stage
# =============================================================================
FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    libopencv-dev \
    libssl3t64 \
    && rm -rf /var/lib/apt/lists/*

# Copy ONNX Runtime shared library
COPY --from=build /opt/onnxruntime/lib/libonnxruntime.so* /usr/lib/

# Copy participant binary
COPY --from=build /src/build/smpc-party /usr/local/bin/smpc-party

RUN ldconfig && \
    useradd -r -s /usr/sbin/nologin iris

USER iris

ENTRYPOINT ["smpc-party"]
