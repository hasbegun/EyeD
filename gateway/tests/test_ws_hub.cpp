#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include "ws_hub.h"

using namespace eyed;

// Mock WebSocket session for testing
class MockWsSession : public WsSession {
public:
    MockWsSession(bool open = true) : open_(open) {}
    
    void send(const std::string& message) override {
        if (!open_) {
            throw std::runtime_error("Session closed");
        }
        last_message_ = message;
        send_count_++;
    }
    
    bool is_open() const override {
        return open_;
    }
    
    void close() {
        open_ = false;
    }
    
    std::string last_message_;
    int send_count_ = 0;
    
private:
    bool open_;
};

TEST_CASE("WsHub: initial client count is zero") {
    WsHub hub;
    CHECK(hub.client_count() == 0);
}

TEST_CASE("WsHub: add client increments count") {
    WsHub hub;
    auto session = std::make_shared<MockWsSession>();
    
    hub.add_client(session);
    CHECK(hub.client_count() == 1);
}

TEST_CASE("WsHub: remove client decrements count") {
    WsHub hub;
    auto session = std::make_shared<MockWsSession>();
    
    hub.add_client(session);
    CHECK(hub.client_count() == 1);
    
    hub.remove_client(session);
    CHECK(hub.client_count() == 0);
}

TEST_CASE("WsHub: broadcast sends to all clients") {
    WsHub hub;
    auto session1 = std::make_shared<MockWsSession>();
    auto session2 = std::make_shared<MockWsSession>();
    
    hub.add_client(session1);
    hub.add_client(session2);
    
    nlohmann::json msg;
    msg["test"] = "hello";
    
    hub.broadcast(msg);
    
    CHECK(session1->send_count_ == 1);
    CHECK(session2->send_count_ == 1);
    CHECK(session1->last_message_ == msg.dump());
    CHECK(session2->last_message_ == msg.dump());
}

TEST_CASE("WsHub: broadcast removes closed sessions") {
    WsHub hub;
    auto session1 = std::make_shared<MockWsSession>();
    auto session2 = std::make_shared<MockWsSession>();
    
    hub.add_client(session1);
    hub.add_client(session2);
    CHECK(hub.client_count() == 2);
    
    // Close session2
    session2->close();
    
    nlohmann::json msg;
    msg["test"] = "hello";
    
    hub.broadcast(msg);
    
    // session1 should receive, session2 should be removed
    CHECK(session1->send_count_ == 1);
    CHECK(session2->send_count_ == 0);
    CHECK(hub.client_count() == 1);
}

TEST_CASE("WsHub: multiple broadcasts to same clients") {
    WsHub hub;
    auto session = std::make_shared<MockWsSession>();
    
    hub.add_client(session);
    
    nlohmann::json msg1;
    msg1["count"] = 1;
    hub.broadcast(msg1);
    
    nlohmann::json msg2;
    msg2["count"] = 2;
    hub.broadcast(msg2);
    
    CHECK(session->send_count_ == 2);
    CHECK(session->last_message_ == msg2.dump());
}

TEST_CASE("WsHub: add same client twice only counts once") {
    WsHub hub;
    auto session = std::make_shared<MockWsSession>();
    
    hub.add_client(session);
    hub.add_client(session);
    
    CHECK(hub.client_count() == 1);
}

TEST_CASE("WsHub: broadcast with no clients doesn't crash") {
    WsHub hub;
    
    nlohmann::json msg;
    msg["test"] = "hello";
    
    hub.broadcast(msg);
    
    CHECK(hub.client_count() == 0);
}
