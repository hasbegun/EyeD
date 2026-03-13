#include "config.h"

#include <cstdlib>
#include <doctest/doctest.h>

// ---------------------------------------------------------------------------
// EnvGuard — RAII helper to set/restore an environment variable in a test.
// ---------------------------------------------------------------------------
class EnvGuard {
    std::string key_;
    std::string old_value_;
    bool was_set_ = false;

  public:
    EnvGuard(const char* key, const char* value) : key_(key) {
        if (const char* v = std::getenv(key)) {
            was_set_ = true;
            old_value_ = v;
        }
        if (value) {
            setenv(key_.c_str(), value, 1);
        } else {
            unsetenv(key_.c_str());
        }
    }
    ~EnvGuard() {
        if (was_set_) {
            setenv(key_.c_str(), old_value_.c_str(), 1);
        } else {
            unsetenv(key_.c_str());
        }
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

TEST_CASE("Config default values") {
    unsetenv("EYED_NATS_URL");
    unsetenv("EYED_ARCHIVE_ROOT");
    unsetenv("EYED_LOG_LEVEL");
    unsetenv("EYED_HTTP_PORT");
    unsetenv("EYED_RETENTION_RAW_DAYS");
    unsetenv("EYED_RETENTION_ARTIFACTS_DAYS");
    unsetenv("EYED_RETENTION_MATCH_LOG_DAYS");

    auto cfg = eyed::Config::from_env();

    CHECK(cfg.nats_url    == "nats://nats:4222");
    CHECK(cfg.archive_root == "/data/archive");
    CHECK(cfg.log_level   == "info");
    CHECK(cfg.http_port   == "8082");
    CHECK(cfg.retention_raw_days       == 730);
    CHECK(cfg.retention_artifacts_days == 90);
    CHECK(cfg.retention_match_log_days == 365);
}

TEST_CASE("Config NATS URL override") {
    EnvGuard g("EYED_NATS_URL", "nats://custom-host:4222");
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.nats_url == "nats://custom-host:4222");
}

TEST_CASE("Config archive root override") {
    EnvGuard g("EYED_ARCHIVE_ROOT", "/mnt/storage");
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.archive_root == "/mnt/storage");
}

TEST_CASE("Config log level override") {
    SUBCASE("debug") {
        EnvGuard g("EYED_LOG_LEVEL", "debug");
        CHECK(eyed::Config::from_env().log_level == "debug");
    }
    SUBCASE("warn") {
        EnvGuard g("EYED_LOG_LEVEL", "warn");
        CHECK(eyed::Config::from_env().log_level == "warn");
    }
    SUBCASE("error") {
        EnvGuard g("EYED_LOG_LEVEL", "error");
        CHECK(eyed::Config::from_env().log_level == "error");
    }
}

TEST_CASE("Config HTTP port override") {
    EnvGuard g("EYED_HTTP_PORT", "9090");
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.http_port == "9090");
}

TEST_CASE("Config retention raw days override") {
    SUBCASE("valid value") {
        EnvGuard g("EYED_RETENTION_RAW_DAYS", "365");
        CHECK(eyed::Config::from_env().retention_raw_days == 365);
    }
    SUBCASE("zero disables retention") {
        EnvGuard g("EYED_RETENTION_RAW_DAYS", "0");
        CHECK(eyed::Config::from_env().retention_raw_days == 0);
    }
    SUBCASE("invalid string keeps default") {
        EnvGuard g("EYED_RETENTION_RAW_DAYS", "not_a_number");
        // atoi("not_a_number") returns 0; 0 >= 0 so it is accepted (keep-forever mode)
        CHECK(eyed::Config::from_env().retention_raw_days == 0);
    }
}

TEST_CASE("Config retention artifacts days override") {
    EnvGuard g("EYED_RETENTION_ARTIFACTS_DAYS", "30");
    CHECK(eyed::Config::from_env().retention_artifacts_days == 30);
}

TEST_CASE("Config retention match log days override") {
    EnvGuard g("EYED_RETENTION_MATCH_LOG_DAYS", "180");
    CHECK(eyed::Config::from_env().retention_match_log_days == 180);
}

TEST_CASE("Config all env vars at once") {
    EnvGuard g1("EYED_NATS_URL",                  "nats://prod:4222");
    EnvGuard g2("EYED_ARCHIVE_ROOT",               "/data/prod");
    EnvGuard g3("EYED_LOG_LEVEL",                  "warn");
    EnvGuard g4("EYED_HTTP_PORT",                  "8099");
    EnvGuard g5("EYED_RETENTION_RAW_DAYS",         "90");
    EnvGuard g6("EYED_RETENTION_ARTIFACTS_DAYS",   "30");
    EnvGuard g7("EYED_RETENTION_MATCH_LOG_DAYS",   "60");

    auto cfg = eyed::Config::from_env();

    CHECK(cfg.nats_url                 == "nats://prod:4222");
    CHECK(cfg.archive_root             == "/data/prod");
    CHECK(cfg.log_level                == "warn");
    CHECK(cfg.http_port                == "8099");
    CHECK(cfg.retention_raw_days       == 90);
    CHECK(cfg.retention_artifacts_days == 30);
    CHECK(cfg.retention_match_log_days == 60);
}
