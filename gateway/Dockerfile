FROM golang:1.24-bookworm AS build

# Install protoc and Go plugins
RUN apt-get update && apt-get install -y --no-install-recommends \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables to bypass certificate validation
ENV GIT_SSL_NO_VERIFY=1
ENV GOPRIVATE=*
ENV GOINSECURE=*

# Configure git to handle large repositories and network issues
RUN git config --global http.postBuffer 524288000 && \
    git config --global http.lowSpeedLimit 0 && \
    git config --global http.lowSpeedTime 999999

RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest \
    && go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

WORKDIR /app

# Copy proto definition and generate Go code
COPY proto/capture.proto /proto/
RUN mkdir -p /app/proto/eyed && \
    protoc --go_out=/app/proto/eyed --go_opt=paths=source_relative \
           --go-grpc_out=/app/proto/eyed --go-grpc_opt=paths=source_relative \
           -I/proto \
           /proto/capture.proto

# Copy all gateway source
COPY gateway/ ./

# Resolve dependencies and build with retry logic for network issues
RUN for i in 1 2 3; do \
        go mod tidy && break || sleep 5; \
    done && \
    CGO_ENABLED=0 go build -o /gateway ./cmd/gateway && \
    CGO_ENABLED=0 go build -o /integration-test ./cmd/integration-test && \
    CGO_ENABLED=0 go build -o /ws-test ./cmd/ws-test

# --- Runtime ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /gateway /app/gateway
COPY --from=build /integration-test /app/integration-test
COPY --from=build /ws-test /app/ws-test

EXPOSE 50051 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/health/alive || exit 1

CMD ["/app/gateway"]
