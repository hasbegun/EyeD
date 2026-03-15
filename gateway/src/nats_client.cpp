#include "nats_client.h"
#include <thread>
#include <chrono>
#include <iostream>

namespace eyed {

NatsClient::NatsClient(const std::string& url) : url_(url) {}

NatsClient::~NatsClient() {
    close();
}

bool NatsClient::connect() {
    natsOptions* opts = nullptr;
    natsStatus s;

    s = natsOptions_Create(&opts);
    if (s != NATS_OK) {
        return false;
    }

    natsOptions_SetURL(opts, url_.c_str());
    natsOptions_SetAllowReconnect(opts, true);
    natsOptions_SetMaxReconnect(opts, -1);  // Infinite reconnect
    natsOptions_SetReconnectWait(opts, 2000);  // 2s between attempts

    s = natsConnection_Connect(&conn_, opts);
    natsOptions_Destroy(opts);

    return s == NATS_OK;
}

bool NatsClient::publish_analyze(const json& request) {
    if (!conn_) {
        return false;
    }

    std::string payload = request.dump();
    natsStatus s = natsConnection_PublishString(conn_, "eyed.analyze", payload.c_str());
    
    if (s == NATS_OK) {
        published_++;
        return true;
    }
    return false;
}

void NatsClient::on_message(natsConnection* nc, natsSubscription* sub, natsMsg* msg, void* closure) {
    auto* client = static_cast<NatsClient*>(closure);
    
    const char* data = natsMsg_GetData(msg);
    int len = natsMsg_GetDataLength(msg);
    
    if (data && len > 0 && client->result_callback_) {
        try {
            json result = json::parse(std::string(data, len));
            client->result_callback_(result);
        } catch (const json::exception& e) {
            // Log parse error but don't crash
            std::cerr << "Failed to parse NATS result: " << e.what() << std::endl;
        }
    }
    
    natsMsg_Destroy(msg);
}

bool NatsClient::subscribe_results(ResultCallback callback) {
    if (!conn_) {
        return false;
    }

    result_callback_ = callback;
    natsStatus s = natsConnection_Subscribe(&sub_, conn_, "eyed.result", on_message, this);
    return s == NATS_OK;
}

bool NatsClient::is_connected() const {
    if (!conn_) {
        return false;
    }
    return natsConnection_Status(conn_) == NATS_CONN_STATUS_CONNECTED;
}

void NatsClient::close() {
    if (sub_) {
        natsSubscription_Unsubscribe(sub_);
        natsSubscription_Destroy(sub_);
        sub_ = nullptr;
    }
    if (conn_) {
        natsConnection_Drain(conn_);
        natsConnection_Destroy(conn_);
        conn_ = nullptr;
    }
}

} // namespace eyed
