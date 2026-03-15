#include "grpc_server.h"
#include <chrono>
#include <sstream>
#include <iomanip>

namespace eyed {

// Base64 encoding table
static const char base64_chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789+/";

std::string base64_encode(const std::string& input) {
    std::string ret;
    int i = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];
    size_t in_len = input.size();
    const unsigned char* bytes_to_encode = reinterpret_cast<const unsigned char*>(input.data());

    while (in_len--) {
        char_array_3[i++] = *(bytes_to_encode++);
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;

            for (i = 0; i < 4; i++)
                ret += base64_chars[char_array_4[i]];
            i = 0;
        }
    }

    if (i) {
        for (int j = i; j < 3; j++)
            char_array_3[j] = '\0';

        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);

        for (int j = 0; j < i + 1; j++)
            ret += base64_chars[char_array_4[j]];

        while (i++ < 3)
            ret += '=';
    }

    return ret;
}

GrpcServiceImpl::GrpcServiceImpl(NatsClient* nats, Breaker* breaker)
    : nats_(nats), breaker_(breaker) {}

bool GrpcServiceImpl::process_frame(const eyed::CaptureFrame* frame, eyed::FrameAck* ack) {
    auto start = std::chrono::steady_clock::now();

    // Check circuit breaker
    if (!breaker_->allow()) {
        frames_rejected_++;
        ack->set_frame_id(frame->frame_id());
        ack->set_accepted(false);
        ack->set_queue_depth(0);
        return false;
    }

    // Build AnalyzeRequest JSON
    json req;
    req["frame_id"] = std::to_string(frame->frame_id());
    req["device_id"] = frame->device_id();
    req["jpeg_b64"] = base64_encode(frame->jpeg_data());
    req["quality_score"] = frame->quality_score();
    req["eye_side"] = frame->eye_side();

    // Convert timestamp_us to RFC3339Nano format
    auto us = frame->timestamp_us();
    auto sec = us / 1000000;
    auto usec = us % 1000000;
    std::time_t t = static_cast<std::time_t>(sec);
    std::tm tm;
    gmtime_r(&t, &tm);
    std::ostringstream oss;
    oss << std::put_time(&tm, "%Y-%m-%dT%H:%M:%S");
    oss << "." << std::setfill('0') << std::setw(6) << usec << "Z";
    req["timestamp"] = oss.str();

    // Publish to NATS
    if (!nats_->publish_analyze(req)) {
        frames_rejected_++;
        ack->set_frame_id(frame->frame_id());
        ack->set_accepted(false);
        ack->set_queue_depth(0);
        return false;
    }

    // Success
    frames_processed_++;
    auto end = std::chrono::steady_clock::now();
    auto latency_us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();
    total_latency_us_ += latency_us;

    ack->set_frame_id(frame->frame_id());
    ack->set_accepted(true);
    ack->set_queue_depth(0);
    return true;
}

grpc::Status GrpcServiceImpl::SubmitFrame(grpc::ServerContext* context,
                                          const eyed::CaptureFrame* request,
                                          eyed::FrameAck* response) {
    process_frame(request, response);
    return grpc::Status::OK;
}

grpc::Status GrpcServiceImpl::StreamFrames(grpc::ServerContext* context,
                                           grpc::ServerReaderWriter<eyed::FrameAck, eyed::CaptureFrame>* stream) {
    connected_devices_++;

    eyed::CaptureFrame frame;
    while (stream->Read(&frame)) {
        eyed::FrameAck ack;
        process_frame(&frame, &ack);
        if (!stream->Write(ack)) {
            break;
        }
    }

    connected_devices_--;
    return grpc::Status::OK;
}

grpc::Status GrpcServiceImpl::GetStatus(grpc::ServerContext* context,
                                        const eyed::Empty* request,
                                        eyed::ServerStatus* response) {
    response->set_alive(true);
    response->set_ready(nats_->is_connected() && breaker_->state() == State::Closed);
    response->set_connected_devices(connected_devices_.load());
    response->set_avg_latency_ms(avg_latency_ms());
    response->set_frames_processed(frames_processed_.load());
    return grpc::Status::OK;
}

double GrpcServiceImpl::avg_latency_ms() const {
    uint64_t processed = frames_processed_.load();
    if (processed == 0) {
        return 0.0;
    }
    int64_t total_us = total_latency_us_.load();
    return (static_cast<double>(total_us) / static_cast<double>(processed)) / 1000.0;
}

} // namespace eyed
