#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include "grpc_server.h"

using namespace eyed;

TEST_CASE("base64_encode: empty string") {
    CHECK(base64_encode("") == "");
}

TEST_CASE("base64_encode: single byte") {
    CHECK(base64_encode("A") == "QQ==");
}

TEST_CASE("base64_encode: two bytes") {
    CHECK(base64_encode("AB") == "QUI=");
}

TEST_CASE("base64_encode: three bytes") {
    CHECK(base64_encode("ABC") == "QUJD");
}

TEST_CASE("base64_encode: four bytes") {
    CHECK(base64_encode("ABCD") == "QUJDRA==");
}

TEST_CASE("base64_encode: typical string") {
    CHECK(base64_encode("Hello, World!") == "SGVsbG8sIFdvcmxkIQ==");
}

TEST_CASE("GrpcServer: initial metrics are zero") {
    NatsClient nats("nats://localhost:4222");
    Breaker breaker(std::chrono::seconds(30), std::chrono::seconds(10));
    GrpcServiceImpl server(&nats, &breaker);

    CHECK(server.frames_processed() == 0);
    CHECK(server.frames_rejected() == 0);
    CHECK(server.connected_devices() == 0);
    CHECK(server.avg_latency_ms() == 0.0);
}

TEST_CASE("GrpcServer: GetStatus returns alive") {
    NatsClient nats("nats://localhost:4222");
    Breaker breaker(std::chrono::seconds(30), std::chrono::seconds(10));
    GrpcServiceImpl server(&nats, &breaker);

    grpc::ServerContext context;
    eyed::Empty request;
    eyed::ServerStatus response;

    auto status = server.GetStatus(&context, &request, &response);

    CHECK(status.ok());
    CHECK(response.alive() == true);
    CHECK(response.frames_processed() == 0);
}
