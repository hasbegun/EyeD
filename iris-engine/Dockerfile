ARG RUNTIME=cpu

# =============================================================================
# Stage 1: Build OpenFHE C++ library and Python bindings from source
# (PyPI wheels require Python >= 3.12; we need Python 3.10 for Open-IRIS)
# =============================================================================
FROM python:3.10-slim-bookworm AS openfhe-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake g++ make git autoconf libomp-dev \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "pybind11[global]"

# Build OpenFHE C++ library
ARG OPENFHE_VERSION=v1.4.2
RUN git clone --depth 1 --branch ${OPENFHE_VERSION} \
        https://github.com/openfheorg/openfhe-development.git /tmp/openfhe && \
    cd /tmp/openfhe && mkdir build && cd build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_UNITTESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_BENCHMARKS=OFF \
        -DWITH_BE2=OFF \
        -DWITH_BE4=OFF && \
    make -j$(nproc) && make install && \
    rm -rf /tmp/openfhe

# Build openfhe-python bindings
ARG OPENFHE_PYTHON_VERSION=v1.4.2.0
RUN git clone --depth 1 --branch ${OPENFHE_PYTHON_VERSION} \
        https://github.com/openfheorg/openfhe-python.git /tmp/openfhe-python && \
    cd /tmp/openfhe-python && mkdir build && cd build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DOpenFHE_DIR=/usr/local/lib/cmake/OpenFHE && \
    make -j$(nproc) && make install && \
    rm -rf /tmp/openfhe-python

# =============================================================================
# Stage 2: Runtime image
# =============================================================================
FROM nvidia/cuda:12.6.3-runtime-bookworm AS base-cuda
FROM python:3.10-slim-bookworm AS base-cpu
FROM base-${RUNTIME} AS base

# System deps (opencv needs libgl, OpenFHE needs libomp)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 curl libomp5 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Ensure python3.10 exists on CUDA base
RUN if [ "${RUNTIME}" = "cuda" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Copy OpenFHE libraries and Python bindings from builder
COPY --from=openfhe-builder /usr/local/lib/libOpenFHE* /usr/local/lib/
COPY --from=openfhe-builder /usr/local/lib/libOPENFHE* /usr/local/lib/
COPY --from=openfhe-builder /usr/local/openfhe.cpython-310-*.so /usr/local/lib/python3.10/site-packages/
ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}
RUN ldconfig

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && if [ "${RUNTIME}" = "cuda" ]; then \
        pip install --no-cache-dir onnxruntime-gpu; \
    fi

# Copy application code
COPY src/ /app/src/

ENV EYED_RUNTIME=${RUNTIME}
ENV PYTHONUNBUFFERED=1

EXPOSE 7000

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:7000/health/alive || exit 1

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "7000"]
