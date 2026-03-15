#include "signaling_hub.h"
#include <nlohmann/json.hpp>

namespace eyed {

void SignalingHub::register_device(const std::string& device_id, std::shared_ptr<WsSession> session) {
    std::lock_guard<std::mutex> lock(mutex_);
    devices_[device_id] = session;
    session_device_[session.get()] = device_id;
    session_role_[session.get()] = "device";
    broadcast_presence(device_id, "join");
}

void SignalingHub::register_viewer(const std::string& device_id, std::shared_ptr<WsSession> session) {
    std::lock_guard<std::mutex> lock(mutex_);
    viewers_[device_id].insert(session);
    session_device_[session.get()] = device_id;
    session_role_[session.get()] = "viewer";
}

void SignalingHub::unregister(std::shared_ptr<WsSession> session) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it_device = session_device_.find(session.get());
    if (it_device == session_device_.end()) return;

    std::string device_id = it_device->second;
    std::string role = session_role_[session.get()];

    if (role == "device") {
        devices_.erase(device_id);
        broadcast_presence(device_id, "leave");
    } else {
        auto& viewer_set = viewers_[device_id];
        viewer_set.erase(session);
        if (viewer_set.empty()) {
            viewers_.erase(device_id);
        }
    }

    session_device_.erase(session.get());
    session_role_.erase(session.get());
}

void SignalingHub::relay(std::shared_ptr<WsSession> sender, const std::string& msg) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = session_device_.find(sender.get());
    if (it == session_device_.end()) return;

    const std::string& device_id = it->second;
    const std::string& role = session_role_[sender.get()];

    if (role == "device") {
        // Device → relay to all viewers
        auto vit = viewers_.find(device_id);
        if (vit == viewers_.end()) return;
        auto& viewer_set = vit->second;
        auto vit2 = viewer_set.begin();
        while (vit2 != viewer_set.end()) {
            if ((*vit2)->is_open()) {
                try {
                    (*vit2)->send(msg);
                    ++vit2;
                } catch (...) {
                    vit2 = viewer_set.erase(vit2);
                }
            } else {
                vit2 = viewer_set.erase(vit2);
            }
        }
    } else {
        // Viewer → relay to device
        auto dit = devices_.find(device_id);
        if (dit == devices_.end()) return;
        if (dit->second->is_open()) {
            try {
                dit->second->send(msg);
            } catch (...) {
                devices_.erase(dit);
            }
        }
    }
}

void SignalingHub::broadcast_presence(const std::string& device_id, const std::string& event) {
    // Called with lock already held
    nlohmann::json j;
    j["type"] = "presence";
    j["device_id"] = device_id;
    j["event"] = event;
    std::string msg = j.dump();

    auto vit = viewers_.find(device_id);
    if (vit == viewers_.end()) return;
    for (auto& s : vit->second) {
        if (s->is_open()) {
            try { s->send(msg); } catch (...) {}
        }
    }
}

int SignalingHub::device_count() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return static_cast<int>(devices_.size());
}

int SignalingHub::viewer_count() const {
    std::lock_guard<std::mutex> lock(mutex_);
    int total = 0;
    for (auto& [k, v] : viewers_) total += static_cast<int>(v.size());
    return total;
}

} // namespace eyed
