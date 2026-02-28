package config

import (
	"os"
	"strconv"
)

// Config holds storage service configuration, loaded from environment variables.
type Config struct {
	NatsURL     string
	ArchiveRoot string
	LogLevel    string
	HTTPPort    string

	// Retention policy (days, 0 = keep forever)
	RetentionRawDays       int
	RetentionArtifactsDays int
	RetentionMatchLogDays  int
}

// Load reads configuration from EYED_* environment variables.
func Load() Config {
	return Config{
		NatsURL:                envOr("EYED_NATS_URL", "nats://nats:4222"),
		ArchiveRoot:            envOr("EYED_ARCHIVE_ROOT", "/data/archive"),
		LogLevel:               envOr("EYED_LOG_LEVEL", "info"),
		HTTPPort:               envOr("EYED_HTTP_PORT", "8082"),
		RetentionRawDays:       envInt("EYED_RETENTION_RAW_DAYS", 730),
		RetentionArtifactsDays: envInt("EYED_RETENTION_ARTIFACTS_DAYS", 90),
		RetentionMatchLogDays:  envInt("EYED_RETENTION_MATCH_LOG_DAYS", 365),
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}
