package config

import "os"

// Config holds gateway configuration loaded from environment variables.
type Config struct {
	NatsURL  string
	GRPCPort string
	HTTPPort string
	LogLevel string
}

// Load reads configuration from EYED_* environment variables with defaults.
func Load() Config {
	return Config{
		NatsURL:  envOr("EYED_NATS_URL", "nats://nats:4222"),
		GRPCPort: envOr("EYED_GRPC_PORT", "50051"),
		HTTPPort: envOr("EYED_HTTP_PORT", "8080"),
		LogLevel: envOr("EYED_LOG_LEVEL", "info"),
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
