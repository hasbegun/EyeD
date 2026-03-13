#pragma once

#include <atomic>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>
#include "capture.grpc.pb.h"
#include "nats_client.h"
#include "breaker.h"

namespace eyed {

// Standalone base64 encoding function (for testing)
std::string base64_encode(const std::string& input);

class GrpcServiceImpl final : public eyed::CaptureService::Service {
public:
    GrpcServiceImpl(NatsClient* nats, Breaker* breaker);

    grpc::Status SubmitFrame(grpc::ServerContext* context,
                            const eyed::CaptureFrame* request,
                            eyed::FrameAck* response) override;

    grpc::Status StreamFrames(grpc::ServerContext* context,
                             grpc::ServerReaderWriter<eyed::FrameAck, eyed::CaptureFrame>* stream) override;

    grpc::Status GetStatus(grpc::ServerContext* context,
                          const eyed::Empty* request,
                          eyed::ServerStatus* response) override;

    // Metrics accessors for testing
    uint64_t frames_processed() const { return frames_processed_.load(); }
    uint64_t frames_rejected() const { return frames_rejected_.load(); }
    int32_t connected_devices() const { return connected_devices_.load(); }
    double avg_latency_ms() const;

private:
    NatsClient* nats_;
    Breaker* breaker_;

    std::atomic<uint64_t> frames_processed_{0};
    std::atomic<uint64_t> frames_rejected_{0};
    std::atomic<int32_t> connected_devices_{0};
    std::atomic<int64_t> total_latency_us_{0};

    // Helper: process a single frame (used by both SubmitFrame and StreamFrames)
    bool process_frame(const eyed::CaptureFrame* frame, eyed::FrameAck* ack);
};

} // namespace eyed
