// Gateway integration test: connects via gRPC, submits a frame, verifies the ack.
// Usage: integration_test [gateway_host] [grpc_port]
//   Defaults: localhost 50051

#include <iostream>
#include <chrono>
#include <thread>
#include <cstring>
#include <grpcpp/grpcpp.h>
#include "capture.grpc.pb.h"

static const char* JPEG_1x1 =
    "\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    "\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t"
    "\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a"
    "\x1f\x1e\x1d\x1a\x1c\x1c $.' \",#\x1c\x1c(7),01444\x1f'9=82<.342\x1e\x1e"
    "\x1c##=?\x1d\x1d=?\x1d\x1d\x1d##=?\x1d\x1d=?\x1d\x1d"
    "\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
    "\xff\xc4\x00\x1f\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\t\n\x0b"
    "\xff\xc4\x00\xb5\x10\x00\x02\x01\x03\x03\x02\x04\x03\x05\x05\x04\x04\x00\x00"
    "\x01}\x01\x02\x03\x00\x04\x11\x05\x12!1A\x06\x13Qa\x07\"q\x142\x81\x91\xa1"
    "\x08#B\xb1\xc1\x15R\xd1\xf0$3br\x82\t\n\x16\x17\x18\x19\x1a%&'()*456789:CDEFGHIJ"
    "STUVWXYZ\xff\xda\x00\x08\x01\x01\x00\x00?\x00\xfb\xd4P\x00\x00\x00\x1f\xff\xd9";

int main(int argc, char* argv[]) {
    std::string host = (argc > 1) ? argv[1] : "localhost";
    std::string port = (argc > 2) ? argv[2] : "50051";
    std::string target = host + ":" + port;

    std::cout << "{\"level\":\"info\",\"msg\":\"Connecting to gateway\",\"target\":\"" << target << "\"}" << std::endl;

    // Connect with a deadline
    auto channel = grpc::CreateChannel(target, grpc::InsecureChannelCredentials());
    auto deadline = std::chrono::system_clock::now() + std::chrono::seconds(10);
    if (!channel->WaitForConnected(deadline)) {
        std::cerr << "{\"level\":\"error\",\"msg\":\"Failed to connect to gRPC\"}" << std::endl;
        return 1;
    }
    std::cout << "{\"level\":\"info\",\"msg\":\"Connected to gRPC\"}" << std::endl;

    auto stub = eyed::CaptureService::NewStub(channel);

    // Build a minimal CaptureFrame
    eyed::CaptureFrame frame;
    frame.set_frame_id(1);
    frame.set_device_id("integration-test");
    frame.set_jpeg_data(std::string(JPEG_1x1, 200));
    frame.set_quality_score(0.85f);
    frame.set_eye_side("left");
    frame.set_timestamp_us(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());

    // SubmitFrame RPC
    grpc::ClientContext ctx;
    eyed::FrameAck ack;
    grpc::Status status = stub->SubmitFrame(&ctx, frame, &ack);

    if (!status.ok()) {
        std::cerr << "{\"level\":\"error\",\"msg\":\"SubmitFrame failed\",\"error\":\""
                  << status.error_message() << "\"}" << std::endl;
        return 1;
    }

    if (!ack.accepted()) {
        std::cerr << "{\"level\":\"error\",\"msg\":\"Frame rejected by gateway (circuit breaker open?)\"}" << std::endl;
        return 1;
    }

    std::cout << "{\"level\":\"info\",\"msg\":\"Frame accepted\",\"frame_id\":"
              << ack.frame_id() << "}" << std::endl;

    // GetStatus RPC
    grpc::ClientContext ctx2;
    eyed::Empty empty;
    eyed::ServerStatus srv_status;
    status = stub->GetStatus(&ctx2, empty, &srv_status);
    if (!status.ok()) {
        std::cerr << "{\"level\":\"error\",\"msg\":\"GetStatus failed\",\"error\":\""
                  << status.error_message() << "\"}" << std::endl;
        return 1;
    }

    std::cout << "{\"level\":\"info\",\"msg\":\"Gateway status\","
              << "\"alive\":" << (srv_status.alive() ? "true" : "false")
              << ",\"ready\":" << (srv_status.ready() ? "true" : "false")
              << ",\"frames_processed\":" << srv_status.frames_processed()
              << "}" << std::endl;

    std::cout << "{\"level\":\"info\",\"msg\":\"Integration test PASSED\"}" << std::endl;
    return 0;
}
