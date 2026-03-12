#pragma once

#include <cstdlib>
#include <fstream>
#include <string>

struct Config {
    int port = 7000;
    std::string db_url;
    std::string pipeline_config = "/src/libiris/pipeline.yaml";
    double match_threshold = 0.39;
    double dedup_threshold = 0.32;

    static Config from_env() {
        Config c;
        if (auto* v = std::getenv("EYED_PORT")) c.port = std::atoi(v);
        if (auto* v = std::getenv("EYED_DB_URL")) c.db_url = v;
        if (auto* v = std::getenv("EYED_PIPELINE_CONFIG")) c.pipeline_config = v;
        if (auto* v = std::getenv("EYED_MATCH_THRESHOLD")) c.match_threshold = std::atof(v);
        if (auto* v = std::getenv("EYED_DEDUP_THRESHOLD")) c.dedup_threshold = std::atof(v);

        c.db_url = inject_secrets(c.db_url);
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
