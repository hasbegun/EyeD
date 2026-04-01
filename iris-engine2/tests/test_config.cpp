#include "config.h"

#include <cstdlib>
#include <cstring>
#include <fstream>
#include <filesystem>
#include <doctest/doctest.h>

// Helper to set/unset env vars for tests
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

TEST_CASE("Config default values") {
    // Ensure no env vars are set
    unsetenv("EYED_PORT");
    unsetenv("EYED_DB_URL");
    unsetenv("EYED_PIPELINE_CONFIG");
    unsetenv("EYED_MATCH_THRESHOLD");
    unsetenv("EYED_DEDUP_THRESHOLD");
    unsetenv("EYED_DB_USER_FILE");
    unsetenv("EYED_DB_NAME_FILE");
    unsetenv("EYED_DB_PASSWORD_FILE");
    unsetenv("EYED_MODE");
    unsetenv("EYED_SMPC_ENABLED");
    unsetenv("EYED_SMPC_MODE");
    unsetenv("EYED_NATS_URL");
    unsetenv("EYED_SMPC_NUM_PARTIES");
    unsetenv("EYED_TLS_CERT_DIR");
    unsetenv("EYED_AUDIT_LOG_PATH");
    unsetenv("EYED_SECURITY_MONITOR");
    unsetenv("EYED_SMPC_FALLBACK_PLAINTEXT");

    auto config = Config::from_env();

    CHECK(config.port == 7000);
    CHECK(config.db_url.empty());
    CHECK(config.pipeline_config == "/src/libiris/pipeline.yaml");
    CHECK(config.match_threshold == doctest::Approx(0.39));
    CHECK(config.dedup_threshold == doctest::Approx(0.32));
    // Safe-by-default: absent EYED_MODE → prod
    CHECK(config.mode == "prod");
    CHECK(config.smpc_enabled == true);
    CHECK(config.smpc_mode == "distributed");
    CHECK(config.nats_url.empty());
    CHECK(config.smpc_num_parties == 3);
    CHECK(config.smpc_pipeline_depth == 0);
    CHECK(config.smpc_shards_per_participant == 0);
    CHECK(config.tls_cert_dir.empty());
    CHECK(config.audit_log_path.empty());
    CHECK(config.security_monitor_enabled == false);
    CHECK(config.smpc_fallback_plaintext == false);
    CHECK(config.db_name.empty());
}

TEST_CASE("Config port override") {
    EnvGuard port_guard("EYED_PORT", "8080");
    auto config = Config::from_env();
    CHECK(config.port == 8080);

    // Test with different values
    {
        EnvGuard port_guard2("EYED_PORT", "9000");
        auto config2 = Config::from_env();
        CHECK(config2.port == 9000);
    }

    // Test invalid port
    {
        EnvGuard port_guard3("EYED_PORT", "not_a_number");
        auto config3 = Config::from_env();
        CHECK(config3.port == 0);  // atoi returns 0 for invalid input
    }
}

TEST_CASE("Config threshold overrides") {
    EnvGuard match_guard("EYED_MATCH_THRESHOLD", "0.5");
    EnvGuard dedup_guard("EYED_DEDUP_THRESHOLD", "0.4");

    auto config = Config::from_env();

    CHECK(config.match_threshold == doctest::Approx(0.5));
    CHECK(config.dedup_threshold == doctest::Approx(0.4));
}

TEST_CASE("Config pipeline config override") {
    EnvGuard pipeline_guard("EYED_PIPELINE_CONFIG", "/custom/pipeline.yaml");
    auto config = Config::from_env();
    CHECK(config.pipeline_config == "/custom/pipeline.yaml");
}

TEST_CASE("Config db_url override") {
    EnvGuard db_guard("EYED_DB_URL", "postgresql://localhost:5432/eyed");
    auto config = Config::from_env();
    CHECK(config.db_url == "postgresql://localhost:5432/eyed");
}

TEST_CASE("Config secret injection - user") {
    // Create temp secret file
    auto temp_dir = std::filesystem::temp_directory_path();
    auto user_file = temp_dir / "test_db_user.txt";
    auto name_file = temp_dir / "test_db_name.txt";
    auto pass_file = temp_dir / "test_db_password.txt";

    std::ofstream(user_file) << "testuser";
    std::ofstream(name_file) << "testdb";
    std::ofstream(pass_file) << "testpass";

    EnvGuard user_guard("EYED_DB_USER_FILE", user_file.c_str());
    EnvGuard name_guard("EYED_DB_NAME_FILE", name_file.c_str());
    EnvGuard pass_guard("EYED_DB_PASSWORD_FILE", pass_file.c_str());

    EnvGuard db_guard("EYED_DB_URL", "postgresql://__DB_USER__:__DB_PASSWORD__@localhost:5432/__DB_NAME__");

    auto config = Config::from_env();

    CHECK(config.db_url == "postgresql://testuser:testpass@localhost:5432/testdb");

    // Cleanup
    std::filesystem::remove(user_file);
    std::filesystem::remove(name_file);
    std::filesystem::remove(pass_file);
}

TEST_CASE("Config secret injection - partial") {
    auto temp_dir = std::filesystem::temp_directory_path();
    auto user_file = temp_dir / "test_db_user2.txt";

    std::ofstream(user_file) << "admin";

    EnvGuard user_guard("EYED_DB_USER_FILE", user_file.c_str());
    // Don't set NAME_FILE or PASSWORD_FILE
    EnvGuard db_guard("EYED_DB_URL", "postgresql://__DB_USER__:secret@localhost:5432/__DB_NAME__");

    auto config = Config::from_env();

    // Only user should be replaced, others stay as placeholders
    CHECK(config.db_url == "postgresql://admin:secret@localhost:5432/__DB_NAME__");

    // Cleanup
    std::filesystem::remove(user_file);
}

TEST_CASE("Config secret injection - no placeholders") {
    auto temp_dir = std::filesystem::temp_directory_path();
    auto user_file = temp_dir / "test_db_user3.txt";

    std::ofstream(user_file) << "user";

    EnvGuard user_guard("EYED_DB_USER_FILE", user_file.c_str());
    EnvGuard db_guard("EYED_DB_URL", "postgresql://other:pass@localhost:5432/db");

    auto config = Config::from_env();

    // URL should remain unchanged if no placeholders
    CHECK(config.db_url == "postgresql://other:pass@localhost:5432/db");

    // Cleanup
    std::filesystem::remove(user_file);
}

TEST_CASE("Config multiple env vars at once") {
    EnvGuard port_guard("EYED_PORT", "9000");
    EnvGuard db_guard("EYED_DB_URL", "postgresql://user:pass@host/db");
    EnvGuard pipeline_guard("EYED_PIPELINE_CONFIG", "/custom/path.yaml");
    EnvGuard match_guard("EYED_MATCH_THRESHOLD", "0.45");
    EnvGuard dedup_guard("EYED_DEDUP_THRESHOLD", "0.35");

    auto config = Config::from_env();

    CHECK(config.port == 9000);
    CHECK(config.db_url == "postgresql://user:pass@host/db");
    CHECK(config.pipeline_config == "/custom/path.yaml");
    CHECK(config.match_threshold == doctest::Approx(0.45));
    CHECK(config.dedup_threshold == doctest::Approx(0.35));
}

TEST_CASE("Config empty secret files") {
    auto temp_dir = std::filesystem::temp_directory_path();
    auto user_file = temp_dir / "test_db_user_empty.txt";
    auto name_file = temp_dir / "test_db_name_empty.txt";
    auto pass_file = temp_dir / "test_db_password_empty.txt";

    // Create empty files
    std::ofstream(user_file) << "";
    std::ofstream(name_file) << "";
    std::ofstream(pass_file) << "";

    EnvGuard user_guard("EYED_DB_USER_FILE", user_file.c_str());
    EnvGuard name_guard("EYED_DB_NAME_FILE", name_file.c_str());
    EnvGuard pass_guard("EYED_DB_PASSWORD_FILE", pass_file.c_str());
    EnvGuard db_guard("EYED_DB_URL", "postgresql://__DB_USER__:__DB_PASSWORD__@localhost:5432/__DB_NAME__");

    auto config = Config::from_env();

    // Empty values should not replace placeholders
    CHECK(config.db_url == "postgresql://__DB_USER__:__DB_PASSWORD__@localhost:5432/__DB_NAME__");

    // Cleanup
    std::filesystem::remove(user_file);
    std::filesystem::remove(name_file);
    std::filesystem::remove(pass_file);
}

TEST_CASE("Config nonexistent secret file") {
    EnvGuard user_guard("EYED_DB_USER_FILE", "/nonexistent/path/secret.txt");
    EnvGuard db_guard("EYED_DB_URL", "postgresql://__DB_USER__@localhost:5432/db");

    auto config = Config::from_env();

    // Nonexistent file should leave placeholder unchanged
    CHECK(config.db_url == "postgresql://__DB_USER__@localhost:5432/db");
}

// ---------------------------------------------------------------------------
// T1: EYED_MODE=prod — smpc_mode defaults to "distributed"
// ---------------------------------------------------------------------------
TEST_CASE("T1: prod mode - smpc_mode defaults distributed") {
    EnvGuard mode_guard("EYED_MODE", "prod");
    unsetenv("EYED_SMPC_MODE");

    auto config = Config::from_env();

    CHECK(config.mode == "prod");
    CHECK(config.smpc_enabled == true);
    CHECK(config.smpc_mode == "distributed");
}

// ---------------------------------------------------------------------------
// T2: EYED_MODE=dev — smpc_mode defaults to "simulated"
// ---------------------------------------------------------------------------
TEST_CASE("T2: dev mode - smpc_mode defaults simulated") {
    EnvGuard mode_guard("EYED_MODE", "dev");
    unsetenv("EYED_SMPC_MODE");
    unsetenv("EYED_SMPC_ENABLED");

    auto config = Config::from_env();

    CHECK(config.mode == "dev");
    CHECK(config.smpc_mode == "simulated");
    CHECK(config.smpc_enabled == true);
}

// ---------------------------------------------------------------------------
// T3: EYED_MODE=prod + explicit EYED_SMPC_MODE overrides default
// ---------------------------------------------------------------------------
TEST_CASE("T3: prod mode - explicit EYED_SMPC_MODE overrides default") {
    EnvGuard mode_guard("EYED_MODE", "prod");
    EnvGuard smpc_guard("EYED_SMPC_MODE", "simulated");

    auto config = Config::from_env();

    CHECK(config.mode == "prod");
    CHECK(config.smpc_mode == "simulated");
}

// ---------------------------------------------------------------------------
// Safe-by-default: no EYED_MODE set → behaves as prod
// ---------------------------------------------------------------------------
TEST_CASE("Safe-by-default: absent EYED_MODE acts as prod") {
    unsetenv("EYED_MODE");
    unsetenv("EYED_SMPC_MODE");

    auto config = Config::from_env();

    CHECK(config.mode == "prod");
    CHECK(config.smpc_mode == "distributed");
}

// ---------------------------------------------------------------------------
// test mode behaves like dev for smpc_mode
// ---------------------------------------------------------------------------
TEST_CASE("test mode - smpc_mode does not auto-switch to simulated") {
    EnvGuard mode_guard("EYED_MODE", "test");
    unsetenv("EYED_SMPC_MODE");

    auto config = Config::from_env();

    CHECK(config.mode == "test");
    // Only dev auto-switches to simulated
    CHECK(config.smpc_mode == "distributed");
}

// ---------------------------------------------------------------------------
// NATS URL override
// ---------------------------------------------------------------------------
TEST_CASE("EYED_NATS_URL override") {
    EnvGuard guard("EYED_NATS_URL", "nats://my-nats:4222");
    auto config = Config::from_env();
    CHECK(config.nats_url == "nats://my-nats:4222");
}

TEST_CASE("EYED_SMPC_NUM_PARTIES override") {
    EnvGuard guard("EYED_SMPC_NUM_PARTIES", "5");
    auto config = Config::from_env();
    CHECK(config.smpc_num_parties == 5);
}

// ---------------------------------------------------------------------------
// db_name populated from EYED_DB_NAME_FILE secret
// ---------------------------------------------------------------------------
TEST_CASE("db_name populated from secret file") {
    auto temp_dir = std::filesystem::temp_directory_path();
    auto name_file = temp_dir / "test_db_name_mode.txt";
    std::ofstream(name_file) << "eyed_dev";

    EnvGuard name_guard("EYED_DB_NAME_FILE", name_file.c_str());
    auto config = Config::from_env();

    CHECK(config.db_name == "eyed_dev");

    std::filesystem::remove(name_file);
}

TEST_CASE("db_name empty when no secret file") {
    unsetenv("EYED_DB_NAME_FILE");
    auto config = Config::from_env();
    CHECK(config.db_name.empty());
}

// ---------------------------------------------------------------------------
// EYED_SMPC_ENABLED=false overrides mode default
// ---------------------------------------------------------------------------
TEST_CASE("EYED_SMPC_ENABLED=false overrides dev mode default") {
    EnvGuard mode_guard("EYED_MODE", "dev");
    EnvGuard smpc_guard("EYED_SMPC_ENABLED", "false");

    auto config = Config::from_env();

    CHECK(config.mode == "dev");
    CHECK(config.smpc_enabled == false);
}

TEST_CASE("EYED_SMPC_PIPELINE_DEPTH override") {
    EnvGuard guard("EYED_SMPC_PIPELINE_DEPTH", "4");
    auto config = Config::from_env();
    CHECK(config.smpc_pipeline_depth == 4);
}

TEST_CASE("EYED_SMPC_SHARDS_PER_PARTICIPANT override") {
    EnvGuard guard("EYED_SMPC_SHARDS_PER_PARTICIPANT", "2");
    auto config = Config::from_env();
    CHECK(config.smpc_shards_per_participant == 2);
}

TEST_CASE("EYED_TLS_CERT_DIR override") {
    EnvGuard guard("EYED_TLS_CERT_DIR", "/certs/smpc");
    auto config = Config::from_env();
    CHECK(config.tls_cert_dir == "/certs/smpc");
}

TEST_CASE("EYED_AUDIT_LOG_PATH override") {
    EnvGuard guard("EYED_AUDIT_LOG_PATH", "/var/log/smpc_audit.log");
    auto config = Config::from_env();
    CHECK(config.audit_log_path == "/var/log/smpc_audit.log");
}

TEST_CASE("EYED_SECURITY_MONITOR override") {
    EnvGuard guard("EYED_SECURITY_MONITOR", "true");
    auto config = Config::from_env();
    CHECK(config.security_monitor_enabled == true);
}

TEST_CASE("EYED_SECURITY_MONITOR disabled by default") {
    unsetenv("EYED_SECURITY_MONITOR");
    auto config = Config::from_env();
    CHECK(config.security_monitor_enabled == false);
}

TEST_CASE("EYED_SMPC_FALLBACK_PLAINTEXT override") {
    EnvGuard guard("EYED_SMPC_FALLBACK_PLAINTEXT", "true");
    auto config = Config::from_env();
    CHECK(config.smpc_fallback_plaintext == true);
}

TEST_CASE("EYED_SMPC_FALLBACK_PLAINTEXT disabled by default") {
    unsetenv("EYED_SMPC_FALLBACK_PLAINTEXT");
    auto config = Config::from_env();
    CHECK(config.smpc_fallback_plaintext == false);
}

