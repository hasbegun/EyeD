#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include "config.h"
#include <cstdlib>

TEST_CASE("Config: defaults when no env vars set") {
    unsetenv("EYED_NATS_URL");
    unsetenv("EYED_GRPC_PORT");
    unsetenv("EYED_HTTP_PORT");
    unsetenv("EYED_LOG_LEVEL");

    auto cfg = eyed::Config::from_env();

    CHECK(cfg.nats_url == "nats://nats:4222");
    CHECK(cfg.grpc_port == "50051");
    CHECK(cfg.http_port == "8080");
    CHECK(cfg.log_level == "info");
}

TEST_CASE("Config: env var override NATS URL") {
    setenv("EYED_NATS_URL", "nats://custom:4223", 1);
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.nats_url == "nats://custom:4223");
    unsetenv("EYED_NATS_URL");
}

TEST_CASE("Config: env var override gRPC port") {
    setenv("EYED_GRPC_PORT", "9999", 1);
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.grpc_port == "9999");
    unsetenv("EYED_GRPC_PORT");
}

TEST_CASE("Config: env var override HTTP port") {
    setenv("EYED_HTTP_PORT", "8888", 1);
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.http_port == "8888");
    unsetenv("EYED_HTTP_PORT");
}

TEST_CASE("Config: env var override log level") {
    setenv("EYED_LOG_LEVEL", "debug", 1);
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.log_level == "debug");
    unsetenv("EYED_LOG_LEVEL");
}

TEST_CASE("Config: empty env var uses default") {
    setenv("EYED_NATS_URL", "", 1);
    auto cfg = eyed::Config::from_env();
    CHECK(cfg.nats_url == "nats://nats:4222");
    unsetenv("EYED_NATS_URL");
}
