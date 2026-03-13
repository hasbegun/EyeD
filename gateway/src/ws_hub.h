#pragma once

#include <string>
#include <set>
#include <mutex>
#include <memory>
#include <nlohmann/json.hpp>

namespace eyed {

// Forward declaration - WebSocket session will be managed by HTTP server
class WsSession;

class WsHub {
public:
    WsHub() = default;
    ~WsHub() = default;

    // Register a new WebSocket client
    void add_client(std::shared_ptr<WsSession> session);
    
    // Unregister a WebSocket client
    void remove_client(std::shared_ptr<WsSession> session);
    
    // Broadcast JSON message to all connected clients
    void broadcast(const nlohmann::json& message);
    
    // Get current client count
    int client_count() const;

private:
    mutable std::mutex mutex_;
    std::set<std::shared_ptr<WsSession>> clients_;
};

// WebSocket session interface for broadcasting
class WsSession {
public:
    virtual ~WsSession() = default;
    virtual void send(const std::string& message) = 0;
    virtual bool is_open() const = 0;
};

} // namespace eyed
