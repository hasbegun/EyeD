#include "client.h"

#include <algorithm>
#include <chrono>
#include <thread>

#include <spdlog/spdlog.h>

GrpcClient::GrpcClient(const GatewayConfig& cfg, std::string device_id)
    : cfg_(cfg), device_id_(std::move(device_id)) {}

GrpcClient::~GrpcClient() {
    teardown_stream();
}

bool GrpcClient::connect() {
    teardown_stream();

    grpc::ChannelArguments args;
    args.SetInt(GRPC_ARG_KEEPALIVE_TIME_MS, 10000);
    args.SetInt(GRPC_ARG_KEEPALIVE_TIMEOUT_MS, 5000);
    args.SetInt(GRPC_ARG_KEEPALIVE_PERMIT_WITHOUT_CALLS, 1);

    channel_ = grpc::CreateCustomChannel(
        cfg_.address, grpc::InsecureChannelCredentials(), args);
    stub_ = eyed::CaptureService::NewStub(channel_);

    auto deadline = std::chrono::system_clock::now()
                    + std::chrono::milliseconds(cfg_.connect_timeout_ms);
    bool ok = channel_->WaitForConnected(deadline);
    connected_.store(ok, std::memory_order_relaxed);

    if (ok) {
        spdlog::info("Connected to gateway at {}", cfg_.address);
        ok = open_stream();
    } else {
        spdlog::warn("Failed to connect to gateway at {}", cfg_.address);
    }
    return ok;
}

bool GrpcClient::open_stream() {
    stream_ctx_ = std::make_unique<grpc::ClientContext>();
    stream_ = stub_->StreamFrames(stream_ctx_.get());
    if (!stream_) {
        spdlog::error("Failed to open StreamFrames");
        connected_.store(false, std::memory_order_relaxed);
        return false;
    }
    spdlog::info("StreamFrames opened");
    return true;
}

void GrpcClient::teardown_stream() {
    if (stream_) {
        stream_->WritesDone();
        stream_->Finish();
        stream_.reset();
    }
    stream_ctx_.reset();
    connected_.store(false, std::memory_order_relaxed);
}

SendResult GrpcClient::send_frame(uint32_t frame_id,
                                  const std::vector<unsigned char>& jpeg_data,
                                  float quality_score, uint64_t timestamp_us,
                                  const std::string& eye_side, bool is_nir) {
    if (!stream_) {
        return {.accepted = false, .queue_depth = 0, .connection_ok = false};
    }

    eyed::CaptureFrame frame;
    frame.set_jpeg_data(jpeg_data.data(), jpeg_data.size());
    frame.set_quality_score(quality_score);
    frame.set_timestamp_us(timestamp_us);
    frame.set_frame_id(frame_id);
    frame.set_device_id(device_id_);
    frame.set_is_nir(is_nir);
    frame.set_eye_side(eye_side);

    if (!stream_->Write(frame)) {
        spdlog::warn("StreamFrames Write failed (transport error)");
        teardown_stream();
        return {.accepted = false, .queue_depth = 0, .connection_ok = false};
    }

    eyed::FrameAck ack;
    if (!stream_->Read(&ack)) {
        spdlog::warn("StreamFrames Read failed (transport error)");
        teardown_stream();
        return {.accepted = false, .queue_depth = 0, .connection_ok = false};
    }

    return {
        .accepted      = ack.accepted(),
        .queue_depth   = ack.queue_depth(),
        .connection_ok = true,
    };
}

void reconnect_with_backoff(GrpcClient& client, const GatewayConfig& cfg) {
    int backoff_ms = cfg.reconnect_base_ms;
    while (!client.connect()) {
        spdlog::warn("Gateway unreachable, retrying in {}ms", backoff_ms);
        std::this_thread::sleep_for(std::chrono::milliseconds(backoff_ms));
        backoff_ms = std::min(backoff_ms * 2, cfg.reconnect_max_ms);
    }
}
