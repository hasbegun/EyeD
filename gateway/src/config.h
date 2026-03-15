#pragma once

#include <cstdlib>
#include <string>

namespace eyed {

struct Config {
    std::string nats_url;
    std::string grpc_port;
    std::string http_port;
    std::string log_level;

    static Config from_env() {
        Config cfg;
        cfg.nats_url  = getenv_or("EYED_NATS_URL", "nats://nats:4222");
        cfg.grpc_port = getenv_or("EYED_GRPC_PORT", "50051");
        cfg.http_port = getenv_or("EYED_HTTP_PORT", "8080");
        cfg.log_level = getenv_or("EYED_LOG_LEVEL", "info");
        return cfg;
    }

private:
    static std::string getenv_or(const char* key, const char* fallback) {
        const char* val = std::getenv(key);
        return (val && val[0] != '\0') ? std::string(val) : std::string(fallback);
    }
};

} // namespace eyed
