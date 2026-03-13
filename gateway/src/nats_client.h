#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <string>
#include <nlohmann/json.hpp>
#include <nats.h>

namespace eyed {

using json = nlohmann::json;
using ResultCallback = std::function<void(const json&)>;

class NatsClient {
public:
    NatsClient(const std::string& url);
    ~NatsClient();

    // Connect to NATS with infinite reconnect (2s wait between attempts)
    bool connect();

    // Publish AnalyzeRequest JSON to eyed.analyze
    bool publish_analyze(const json& request);

    // Subscribe to eyed.result and invoke callback for each message
    bool subscribe_results(ResultCallback callback);

    // Check if connected
    bool is_connected() const;

    // Get count of published messages
    uint64_t published() const { return published_.load(); }

    // Close connection
    void close();

private:
    std::string url_;
    natsConnection* conn_ = nullptr;
    natsSubscription* sub_ = nullptr;
    std::atomic<uint64_t> published_{0};
    ResultCallback result_callback_;

    static void on_message(natsConnection* nc, natsSubscription* sub, natsMsg* msg, void* closure);
};

} // namespace eyed
