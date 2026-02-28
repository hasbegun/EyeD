# ---- Stage 1: Build ----
FROM debian:bookworm AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build pkg-config ca-certificates wget \
    g++ \
    libgrpc++-dev libprotobuf-dev protobuf-compiler protobuf-compiler-grpc \
    libopencv-dev \
    libspdlog-dev libfmt-dev \
    && rm -rf /var/lib/apt/lists/*

# toml++ v3.4.0 — single header, download directly
RUN mkdir -p /usr/local/include/toml++ && \
    wget -qO /usr/local/include/toml++/toml.hpp \
        https://raw.githubusercontent.com/marzer/tomlplusplus/v3.4.0/toml.hpp

WORKDIR /src

# Copy proto definition (at /proto, sibling of /src)
COPY proto/ /proto/

# Copy capture source
COPY capture/ .

RUN cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel $(nproc)

# ---- Stage 2: Runtime ----
FROM debian:bookworm-slim

# Install only shared libraries needed at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgrpc++1.51 \
    libprotobuf32 \
    libopencv-core406 libopencv-imgcodecs406 libopencv-imgproc406 libopencv-videoio406 \
    libspdlog1.10 libfmt9 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/capture_device /app/capture_device
COPY --from=build /src/config/capture.toml /app/config/capture.toml

ENV CAPTURE_CONFIG=/app/config/capture.toml

ENTRYPOINT ["/app/capture_device"]
