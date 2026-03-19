#pragma once

#include <cstdlib>
#include <fstream>
#include <string>

struct Config {
    std::string mode = "prod";         // "dev" | "test" | "prod" — safe default
    int port = 7000;
    std::string db_url;
    std::string db_name;               // Resolved from EYED_DB_NAME_FILE secret
    std::string pipeline_config = "/src/libiris/pipeline.yaml";
    double match_threshold = 0.39;
    double dedup_threshold = 0.32;
    bool fhe_enabled = true;           // Enable FHE encryption (runtime-toggleable in dev/test)
    std::string he_key_dir = "/keys";  // Directory for FHE key storage
    bool allow_plaintext = false;      // Plaintext fallback if FHE init fails
    std::string fhe_state_path = "/config/fhe_state";  // Persists dev/test FHE toggle

    static Config from_env() {
        Config c;

        // 1. Read mode first — it sets secure defaults for other fields
        if (auto* v = std::getenv("EYED_MODE")) c.mode = v;

        // 2. Apply mode-based defaults before explicit env overrides
        c.allow_plaintext = (c.mode == "dev" || c.mode == "test");

        // 3. Explicit env vars override mode defaults
        if (auto* v = std::getenv("EYED_PORT")) c.port = std::atoi(v);
        if (auto* v = std::getenv("EYED_DB_URL")) c.db_url = v;
        if (auto* v = std::getenv("EYED_PIPELINE_CONFIG")) c.pipeline_config = v;
        if (auto* v = std::getenv("EYED_MATCH_THRESHOLD")) c.match_threshold = std::atof(v);
        if (auto* v = std::getenv("EYED_DEDUP_THRESHOLD")) c.dedup_threshold = std::atof(v);
        if (auto* v = std::getenv("EYED_FHE_ENABLED")) {
            std::string val(v);
            c.fhe_enabled = (val == "true" || val == "1" || val == "yes");
        }
        if (auto* v = std::getenv("EYED_HE_KEY_DIR")) c.he_key_dir = v;
        if (auto* v = std::getenv("EYED_ALLOW_PLAINTEXT")) {
            std::string val(v);
            c.allow_plaintext = (val == "true" || val == "1" || val == "yes");
        }
        if (auto* v = std::getenv("EYED_FHE_STATE_PATH")) c.fhe_state_path = v;

        // 4. Resolve secrets and build db_url
        c.db_name = read_secret("EYED_DB_NAME_FILE");
        c.db_url  = inject_secrets(c.db_url);
        return c;
    }

  private:
    static std::string read_secret(const char* env_var) {
        auto* path = std::getenv(env_var);
        if (!path) return "";
        std::ifstream f(path);
        std::string val;
        std::getline(f, val);
        return val;
    }

    static std::string inject_secrets(std::string url) {
        auto user = read_secret("EYED_DB_USER_FILE");
        auto name = read_secret("EYED_DB_NAME_FILE");
        auto pass = read_secret("EYED_DB_PASSWORD_FILE");

        auto replace = [](std::string& s, const std::string& from, const std::string& to) {
            auto pos = s.find(from);
            if (pos != std::string::npos) s.replace(pos, from.length(), to);
        };

        if (!user.empty()) replace(url, "__DB_USER__", user);
        if (!name.empty()) replace(url, "__DB_NAME__", name);
        if (!pass.empty()) replace(url, "__DB_PASSWORD__", pass);

        return url;
    }
};
