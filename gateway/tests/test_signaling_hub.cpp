#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include "signaling_hub.h"

using namespace eyed;

class MockSession : public WsSession {
public:
    MockSession(bool open = true) : open_(open) {}
    void send(const std::string& msg) override {
        if (!open_) throw std::runtime_error("closed");
        received.push_back(msg);
    }
    bool is_open() const override { return open_; }
    void close() { open_ = false; }

    std::vector<std::string> received;
private:
    bool open_;
};

TEST_CASE("SignalingHub: initial counts are zero") {
    SignalingHub hub;
    CHECK(hub.device_count() == 0);
    CHECK(hub.viewer_count() == 0);
}

TEST_CASE("SignalingHub: register_device increments device count") {
    SignalingHub hub;
    auto s = std::make_shared<MockSession>();
    hub.register_device("dev1", s);
    CHECK(hub.device_count() == 1);
    CHECK(hub.viewer_count() == 0);
}

TEST_CASE("SignalingHub: register_viewer increments viewer count") {
    SignalingHub hub;
    auto dev = std::make_shared<MockSession>();
    auto viewer = std::make_shared<MockSession>();
    hub.register_device("dev1", dev);
    hub.register_viewer("dev1", viewer);
    CHECK(hub.device_count() == 1);
    CHECK(hub.viewer_count() == 1);
}

TEST_CASE("SignalingHub: multiple viewers per device") {
    SignalingHub hub;
    auto dev = std::make_shared<MockSession>();
    auto v1  = std::make_shared<MockSession>();
    auto v2  = std::make_shared<MockSession>();
    hub.register_device("dev1", dev);
    hub.register_viewer("dev1", v1);
    hub.register_viewer("dev1", v2);
    CHECK(hub.viewer_count() == 2);
}

TEST_CASE("SignalingHub: relay device→viewers") {
    SignalingHub hub;
    auto dev = std::make_shared<MockSession>();
    auto v1  = std::make_shared<MockSession>();
    auto v2  = std::make_shared<MockSession>();
    hub.register_device("dev1", dev);
    hub.register_viewer("dev1", v1);
    hub.register_viewer("dev1", v2);

    hub.relay(dev, "offer-sdp");

    CHECK(v1->received.size() == 1);
    CHECK(v1->received[0] == "offer-sdp");
    CHECK(v2->received.size() == 1);
    CHECK(v2->received[0] == "offer-sdp");
    CHECK(dev->received.empty());
}

TEST_CASE("SignalingHub: relay viewer→device") {
    SignalingHub hub;
    auto dev    = std::make_shared<MockSession>();
    auto viewer = std::make_shared<MockSession>();
    hub.register_device("dev1", dev);
    hub.register_viewer("dev1", viewer);

    hub.relay(viewer, "answer-sdp");

    CHECK(dev->received.size() == 1);
    CHECK(dev->received[0] == "answer-sdp");
    CHECK(viewer->received.empty());
}

TEST_CASE("SignalingHub: unregister device decrements count") {
    SignalingHub hub;
    auto dev = std::make_shared<MockSession>();
    hub.register_device("dev1", dev);
    hub.unregister(dev);
    CHECK(hub.device_count() == 0);
}

TEST_CASE("SignalingHub: unregister viewer decrements count") {
    SignalingHub hub;
    auto dev    = std::make_shared<MockSession>();
    auto viewer = std::make_shared<MockSession>();
    hub.register_device("dev1", dev);
    hub.register_viewer("dev1", viewer);
    hub.unregister(viewer);
    CHECK(hub.viewer_count() == 0);
}

TEST_CASE("SignalingHub: broadcast_presence sent to viewers on device register") {
    SignalingHub hub;
    auto v = std::make_shared<MockSession>();
    // Register viewer first (no device yet, presence ignored)
    hub.register_viewer("dev1", v);
    // Now register device — presence "join" should be sent to viewer
    auto dev = std::make_shared<MockSession>();
    hub.register_device("dev1", dev);

    bool got_join = false;
    for (auto& msg : v->received) {
        auto j = nlohmann::json::parse(msg);
        if (j["type"] == "presence" && j["event"] == "join") got_join = true;
    }
    CHECK(got_join);
}

TEST_CASE("SignalingHub: relay from unregistered session is no-op") {
    SignalingHub hub;
    auto orphan = std::make_shared<MockSession>();
    hub.relay(orphan, "hello");  // Should not throw or crash
    CHECK(true);
}
