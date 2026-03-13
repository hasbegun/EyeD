#include "config.h"
#include "breaker.h"
#include "nats_client.h"
#include "grpc_server.h"
#include "http_server.h"
#include "ws_hub.h"
#include "signaling_hub.h"
#include <iostream>
#include <csignal>
#include <atomic>
#include <thread>
#include <chrono>
#include <grpcpp/grpcpp.h>
#include <nlohmann/json.hpp>

using namespace eyed;

std::atomic<bool> shutdown_requested{false};

void log_json(const std::string& level, const std::string& msg) {
    nlohmann::json j;
    j["level"] = level;
    j["msg"] = msg;
    std::cout << j.dump() << std::endl;
}

void signal_handler(int signal) {
    nlohmann::json j;
    j["level"] = "info";
    j["msg"] = "Shutdown signal received";
    j["signal"] = signal;
    std::cout << j.dump() << std::endl;
    shutdown_requested = true;
}

int main() {
    // Load configuration
    auto cfg = Config::from_env();

    log_json("info", "EyeD gateway service (C++) starting");
    nlohmann::json startup;
    startup["nats_url"] = cfg.nats_url;
    startup["grpc_port"] = cfg.grpc_port;
    startup["http_port"] = cfg.http_port;
    startup["log_level"] = cfg.log_level;
    startup["level"] = "info";
    startup["msg"] = "Configuration loaded";
    std::cout << startup.dump() << std::endl;

    // Install signal handlers
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    // Connect to NATS
    log_json("info", "Connecting to NATS");
    NatsClient nats(cfg.nats_url);
    if (!nats.connect()) {
        log_json("error", "Failed to connect to NATS");
        return 1;
    }
    log_json("info", "Connected to NATS");

    // Initialize circuit breaker (30s timeout, 10s probe interval)
    Breaker breaker(std::chrono::seconds(30), std::chrono::seconds(10));
    nlohmann::json breaker_info;
    breaker_info["level"] = "info";
    breaker_info["msg"] = "Circuit breaker initialized";
    breaker_info["timeout"] = "30s";
    breaker_info["probe_interval"] = "10s";
    std::cout << breaker_info.dump() << std::endl;

    // Create WebSocket hub for broadcasting results
    WsHub ws_hub;

    // Subscribe to NATS results and broadcast to WebSocket clients
    nats.subscribe_results([&](const nlohmann::json& result) {
        // Reset circuit breaker on result
        breaker.record_result();

        // Log result
        bool has_error = result.contains("error") &&
                         result["error"].is_string() &&
                         !result["error"].get<std::string>().empty();
        nlohmann::json log;
        log["level"] = has_error ? "warn" : "info";
        log["msg"] = "Analysis result received";
        if (result.contains("frame_id"))  log["frame_id"]  = result["frame_id"];
        if (result.contains("device_id")) log["device_id"] = result["device_id"];
        if (result.contains("latency_ms")) log["latency_ms"] = result["latency_ms"];
        if (has_error) log["error"] = result["error"];
        if (result.contains("match") && result["match"].is_object() &&
            result["match"].value("is_match", false)) {
            log["match"] = true;
            log["identity"] = result["match"].value("matched_identity_id", "");
        }
        std::cout << log.dump() << std::endl;

        // Broadcast to WebSocket clients
        ws_hub.broadcast(result);
    });

    // Start gRPC server
    log_json("info", "Starting gRPC server");
    GrpcServiceImpl grpc_service(&nats, &breaker);
    grpc::ServerBuilder builder;
    builder.AddListeningPort("0.0.0.0:" + cfg.grpc_port, grpc::InsecureServerCredentials());
    builder.RegisterService(&grpc_service);
    std::unique_ptr<grpc::Server> grpc_server(builder.BuildAndStart());

    nlohmann::json grpc_info;
    grpc_info["level"] = "info";
    grpc_info["msg"] = "gRPC server listening";
    grpc_info["port"] = cfg.grpc_port;
    std::cout << grpc_info.dump() << std::endl;

    // Create WebRTC signaling hub
    SignalingHub signaling_hub;

    // Start HTTP server (health + WebSocket + signaling)
    log_json("info", "Starting HTTP server");
    HttpServer http_server("0.0.0.0", std::stoi(cfg.http_port), &nats, &breaker,
                           &ws_hub, &signaling_hub);
    http_server.run();

    nlohmann::json http_info;
    http_info["level"] = "info";
    http_info["msg"] = "HTTP server listening";
    http_info["port"] = cfg.http_port;
    std::cout << http_info.dump() << std::endl;

    log_json("info", "Gateway ready");

    // Wait for shutdown signal
    while (!shutdown_requested) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    // Graceful shutdown
    log_json("info", "Shutting down gateway");

    http_server.stop();
    log_json("info", "HTTP server stopped");

    grpc_server->Shutdown();
    log_json("info", "gRPC server stopped");

    nats.close();
    log_json("info", "NATS connection closed");

    log_json("info", "Shutdown complete");

    return 0;
}
