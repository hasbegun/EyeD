#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include "nats_client.h"

using namespace eyed;
using json = nlohmann::json;

TEST_CASE("NatsClient: AnalyzeRequest JSON serialization") {
    json req;
    req["frame_id"] = "123";
    req["device_id"] = "test-device";
    req["jpeg_b64"] = "base64data";
    req["quality_score"] = 0.85f;
    req["eye_side"] = "left";
    req["timestamp"] = "2024-01-01T00:00:00Z";
    
    CHECK(req["frame_id"] == "123");
    CHECK(req["device_id"] == "test-device");
    CHECK(req["jpeg_b64"] == "base64data");
    CHECK(req["quality_score"] == 0.85f);
    CHECK(req["eye_side"] == "left");
    CHECK(req["timestamp"] == "2024-01-01T00:00:00Z");
}

TEST_CASE("NatsClient: AnalyzeResponse JSON deserialization with match") {
    std::string payload = R"({
        "frame_id": "456",
        "device_id": "test-device",
        "match": {
            "is_match": true,
            "matched_identity_id": "user123",
            "hamming_distance": 0.15,
            "best_rotation": 2
        },
        "iris_template_b64": "template_data",
        "latency_ms": 123.45
    })";
    
    json resp = json::parse(payload);
    
    CHECK(resp["frame_id"] == "456");
    CHECK(resp["device_id"] == "test-device");
    CHECK(resp["match"]["is_match"] == true);
    CHECK(resp["match"]["matched_identity_id"] == "user123");
    CHECK(resp["match"]["hamming_distance"] == 0.15);
    CHECK(resp["match"]["best_rotation"] == 2);
    CHECK(resp["iris_template_b64"] == "template_data");
    CHECK(resp["latency_ms"] == 123.45);
}

TEST_CASE("NatsClient: AnalyzeResponse JSON deserialization without match") {
    std::string payload = R"({
        "frame_id": "789",
        "device_id": "test-device",
        "iris_template_b64": "template_data",
        "latency_ms": 98.76
    })";
    
    json resp = json::parse(payload);
    
    CHECK(resp["frame_id"] == "789");
    CHECK(resp["device_id"] == "test-device");
    CHECK(resp.contains("match") == false);
    CHECK(resp["iris_template_b64"] == "template_data");
    CHECK(resp["latency_ms"] == 98.76);
}

TEST_CASE("NatsClient: AnalyzeResponse JSON deserialization with error") {
    std::string payload = R"({
        "frame_id": "999",
        "device_id": "test-device",
        "error": "segmentation failed",
        "latency_ms": 50.0
    })";
    
    json resp = json::parse(payload);
    
    CHECK(resp["frame_id"] == "999");
    CHECK(resp["device_id"] == "test-device");
    CHECK(resp["error"] == "segmentation failed");
    CHECK(resp["latency_ms"] == 50.0);
}

TEST_CASE("NatsClient: published counter starts at zero") {
    NatsClient client("nats://localhost:4222");
    CHECK(client.published() == 0);
}

TEST_CASE("NatsClient: is_connected returns false before connect") {
    NatsClient client("nats://localhost:4222");
    CHECK(client.is_connected() == false);
}
