#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include "http_server.h"

using namespace eyed;

TEST_CASE("HttpServer: can construct") {
    NatsClient nats("nats://localhost:4222");
    Breaker breaker(std::chrono::seconds(30), std::chrono::seconds(10));
    
    HttpServer server("127.0.0.1", 8080, &nats, &breaker);
    
    // Just verify construction succeeds
    CHECK(true);
}

TEST_CASE("HttpServer: can start and stop") {
    NatsClient nats("nats://localhost:4222");
    Breaker breaker(std::chrono::seconds(30), std::chrono::seconds(10));
    
    HttpServer server("127.0.0.1", 18080, &nats, &breaker);
    
    server.run();
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    server.stop();
    
    CHECK(true);
}
