FROM golang:1.24-bookworm AS build

WORKDIR /app

# Copy all storage source
COPY storage/ ./

# Resolve dependencies and build
RUN go mod tidy && CGO_ENABLED=0 go build -o /storage ./cmd/storage

# --- Runtime ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /storage /app/storage

EXPOSE 8082

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8082/health/alive || exit 1

CMD ["/app/storage"]
