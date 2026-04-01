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
    bool smpc_enabled = true;                    // Enable SMPC template protection
    std::string smpc_mode = "distributed";        // "simulated" | "distributed"
    std::string nats_url;                          // NATS URL for distributed mode
    int smpc_num_parties = 3;                      // Number of SMPC parties
    int smpc_pipeline_depth = 0;                   // 0 = disabled, >0 = pipelined coordinator
    int smpc_shards_per_participant = 0;           // 0 = no sharding, >0 = sharded coordinator

    // Security hardening (Phase 4) — all opt-in, disabled by default
    std::string tls_cert_dir;                      // Path to mTLS certs (empty = TLS disabled)
    std::string audit_log_path;                    // Path to audit log file (empty = audit disabled)
    bool security_monitor_enabled = false;         // Enable SecurityMonitor anomaly detection
    bool smpc_fallback_plaintext = false;             // Fall back to plaintext matching if SMPC init fails

    static Config from_env() {
        Config c;

        // 1. Read mode first — it sets secure defaults for other fields
        if (auto* v = std::getenv("EYED_MODE")) c.mode = v;

        // 2. Apply mode-based defaults before explicit env overrides
        if (c.mode == "dev") c.smpc_mode = "simulated";

        // 3. Explicit env vars override mode defaults
        if (auto* v = std::getenv("EYED_PORT")) c.port = std::atoi(v);
        if (auto* v = std::getenv("EYED_DB_URL")) c.db_url = v;
        if (auto* v = std::getenv("EYED_PIPELINE_CONFIG")) c.pipeline_config = v;
        if (auto* v = std::getenv("EYED_MATCH_THRESHOLD")) c.match_threshold = std::atof(v);
        if (auto* v = std::getenv("EYED_DEDUP_THRESHOLD")) c.dedup_threshold = std::atof(v);
        if (auto* v = std::getenv("EYED_SMPC_ENABLED")) {
            std::string val(v);
            c.smpc_enabled = (val == "true" || val == "1" || val == "yes");
        }
        if (auto* v = std::getenv("EYED_SMPC_MODE")) c.smpc_mode = v;
        if (auto* v = std::getenv("EYED_NATS_URL")) c.nats_url = v;
        if (auto* v = std::getenv("EYED_SMPC_NUM_PARTIES")) c.smpc_num_parties = std::atoi(v);
        if (auto* v = std::getenv("EYED_SMPC_PIPELINE_DEPTH")) c.smpc_pipeline_depth = std::atoi(v);
        if (auto* v = std::getenv("EYED_SMPC_SHARDS_PER_PARTICIPANT")) c.smpc_shards_per_participant = std::atoi(v);
        if (auto* v = std::getenv("EYED_TLS_CERT_DIR")) c.tls_cert_dir = v;
        if (auto* v = std::getenv("EYED_AUDIT_LOG_PATH")) c.audit_log_path = v;
        if (auto* v = std::getenv("EYED_SECURITY_MONITOR")) {
            std::string val(v);
            c.security_monitor_enabled = (val == "true" || val == "1" || val == "yes");
        }
        if (auto* v = std::getenv("EYED_SMPC_FALLBACK_PLAINTEXT")) {
            std::string val(v);
            c.smpc_fallback_plaintext = (val == "true" || val == "1" || val == "yes");
        }

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
