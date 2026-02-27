ARG RUNTIME=cpu

# --- Base images ---
FROM nvidia/cuda:12.6.3-runtime-bookworm AS base-cuda
FROM python:3.10-slim-bookworm AS base-cpu
FROM base-${RUNTIME} AS base

# System deps (opencv needs libgl)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 curl \
    && rm -rf /var/lib/apt/lists/*

# Ensure python3.10 exists on CUDA base
RUN if [ "${RUNTIME}" = "cuda" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        && rm -rf /var/lib/apt/lists/*; \
    fi

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
