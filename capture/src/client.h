#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <grpcpp/grpcpp.h>
#include <spdlog/spdlog.h>

#include "capture.grpc.pb.h"

struct GatewayConfig {
    std::string address            = "gateway:50051";
    int         connect_timeout_ms = 5000;
    int         reconnect_base_ms  = 500;
    int         reconnect_max_ms   = 30000;
};

struct SendResult {
    bool     accepted      = false;
    uint32_t queue_depth   = 0;
    bool     connection_ok = true; // false → transport error, caller reconnects
};

class GrpcClient {
public:
    GrpcClient(const GatewayConfig& cfg, std::string device_id);
    ~GrpcClient();

    // Connect (or reconnect) to the gateway. Blocks until connected or timeout.
    bool connect();

    // Send a frame via the active StreamFrames stream.
    SendResult send_frame(uint32_t frame_id, const std::vector<unsigned char>& jpeg_data,
                          float quality_score, uint64_t timestamp_us,
                          const std::string& eye_side, bool is_nir);

    bool is_connected() const { return connected_.load(std::memory_order_relaxed); }

private:
    GatewayConfig cfg_;
    std::string   device_id_;

    std::shared_ptr<grpc::Channel>                               channel_;
    std::unique_ptr<eyed::CaptureService::Stub>                  stub_;
    std::unique_ptr<grpc::ClientContext>                          stream_ctx_;
    std::unique_ptr<grpc::ClientReaderWriter<eyed::CaptureFrame,
                                             eyed::FrameAck>>    stream_;
    std::atomic<bool> connected_{false};

    bool open_stream();
    void teardown_stream();
};

// Reconnect with exponential backoff. Blocks until connected.
void reconnect_with_backoff(GrpcClient& client, const GatewayConfig& cfg);
