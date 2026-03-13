#pragma once

#include <string>
#include <map>
#include <set>
#include <mutex>
#include <memory>
#include "ws_hub.h"

namespace eyed {

class SignalingHub {
public:
    SignalingHub() = default;
    ~SignalingHub() = default;

    // Register a capture device session
    void register_device(const std::string& device_id, std::shared_ptr<WsSession> session);

    // Register a viewer session for a given device
    void register_viewer(const std::string& device_id, std::shared_ptr<WsSession> session);

    // Unregister any session (device or viewer) by session pointer
    void unregister(std::shared_ptr<WsSession> session);

    // Relay a message from sender to the other side
    // device → all viewers for same device_id
    // viewer → the device for same device_id
    void relay(std::shared_ptr<WsSession> sender, const std::string& msg);

    int device_count() const;
    int viewer_count() const;

private:
    mutable std::mutex mutex_;

    // device_id → device session
    std::map<std::string, std::shared_ptr<WsSession>> devices_;

    // device_id → set of viewer sessions
    std::map<std::string, std::set<std::shared_ptr<WsSession>>> viewers_;

    // reverse lookup: session → device_id
    std::map<WsSession*, std::string> session_device_;

    // reverse lookup: session → role ("device" or "viewer")
    std::map<WsSession*, std::string> session_role_;

    void broadcast_presence(const std::string& device_id, const std::string& event);
};

} // namespace eyed
