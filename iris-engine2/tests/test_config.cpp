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

    auto config = Config::from_env();

    CHECK(config.port == 7000);
    CHECK(config.db_url.empty());
    CHECK(config.pipeline_config == "/src/libiris/pipeline.yaml");
    CHECK(config.match_threshold == doctest::Approx(0.39));
    CHECK(config.dedup_threshold == doctest::Approx(0.32));
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

