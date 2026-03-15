#include "ws_hub.h"
#include <iostream>

namespace eyed {

void WsHub::add_client(std::shared_ptr<WsSession> session) {
    std::lock_guard<std::mutex> lock(mutex_);
    clients_.insert(session);
}

void WsHub::remove_client(std::shared_ptr<WsSession> session) {
    std::lock_guard<std::mutex> lock(mutex_);
    clients_.erase(session);
}

void WsHub::broadcast(const nlohmann::json& message) {
    std::string msg_str = message.dump();
    
    std::lock_guard<std::mutex> lock(mutex_);
    
    // Remove closed sessions while broadcasting
    auto it = clients_.begin();
    while (it != clients_.end()) {
        if ((*it)->is_open()) {
            try {
                (*it)->send(msg_str);
                ++it;
            } catch (const std::exception& e) {
                // Send failed, remove client
                it = clients_.erase(it);
            }
        } else {
            // Session closed, remove it
            it = clients_.erase(it);
        }
    }
}

int WsHub::client_count() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return static_cast<int>(clients_.size());
}

} // namespace eyed
