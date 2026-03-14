#pragma once

#include <cstdlib>
#include <fstream>
#include <string>

namespace eyed {

// ---------------------------------------------------------------------------
// Config — loaded from EYED_* environment variables.
// All fields map 1:1 to the Go storage service's config.Config struct.
// ---------------------------------------------------------------------------
struct Config {
    std::string nats_url    = "nats://nats:4222";
    std::string archive_root = "/data/archive";
    std::string log_level   = "info";
    std::string http_port   = "8082";

    // Retention policy (days, 0 = keep forever)
    int retention_raw_days       = 730;
    int retention_artifacts_days = 90;
    int retention_match_log_days = 365;

    static Config from_env() {
        Config c;

        if (auto* v = std::getenv("EYED_NATS_URL"))       c.nats_url     = v;
        if (auto* v = std::getenv("EYED_ARCHIVE_ROOT"))   c.archive_root = v;
        if (auto* v = std::getenv("EYED_LOG_LEVEL"))      c.log_level    = v;
        if (auto* v = std::getenv("EYED_HTTP_PORT"))      c.http_port    = v;

        if (auto* v = std::getenv("EYED_RETENTION_RAW_DAYS")) {
            if (int n = std::atoi(v); n >= 0) c.retention_raw_days = n;
        }
        if (auto* v = std::getenv("EYED_RETENTION_ARTIFACTS_DAYS")) {
            if (int n = std::atoi(v); n >= 0) c.retention_artifacts_days = n;
        }
        if (auto* v = std::getenv("EYED_RETENTION_MATCH_LOG_DAYS")) {
            if (int n = std::atoi(v); n >= 0) c.retention_match_log_days = n;
        }

        return c;
    }
};

}  // namespace eyed
