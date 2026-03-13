#include "archive_handler.h"
#include "config.h"
#include "local_store.h"
#include "retention_purger.h"

#include <atomic>
#include <chrono>
#include <csignal>
#include <iostream>
#include <string>
#include <thread>

#include <nats.h>
#include <nlohmann/json.hpp>
#include <httplib.h>

// ---------------------------------------------------------------------------
// JSON structured logger (stdout, one JSON object per line)
// ---------------------------------------------------------------------------
namespace {

void log_json(const std::string& level, const std::string& msg) {
    nlohmann::json j;
    j["level"] = level;
    j["msg"]   = msg;
    // Thread-safe: cout is locked internally in C++11+
    std::cout << j.dump() << "\n" << std::flush;
}

// ---------------------------------------------------------------------------
// Signal handling
// ---------------------------------------------------------------------------
volatile sig_atomic_t g_running = 1;  // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)

void on_signal(int) { g_running = 0; }

// ---------------------------------------------------------------------------
// NATS message callback — bridges nats.c C API to ArchiveHandler
// ---------------------------------------------------------------------------
void nats_archive_cb(natsConnection*, natsSubscription*, natsMsg* msg, void* closure) {
    auto* handler = static_cast<eyed::ArchiveHandler*>(closure);
    const char* data = natsMsg_GetData(msg);
    int          len  = natsMsg_GetDataLength(msg);
    if (data && len > 0) {
        handler->handle_message(reinterpret_cast<const uint8_t*>(data),
                                static_cast<size_t>(len));
    }
    natsMsg_Destroy(msg);
}

// ---------------------------------------------------------------------------
// NATS connect with retry (mirrors Go storage main reconnect logic)
// ---------------------------------------------------------------------------
natsConnection* connect_nats(const std::string& url) {
    constexpr int kMaxRetries    = 30;
    constexpr int kRetryDelaySec = 2;

    natsOptions* opts = nullptr;
    natsOptions_Create(&opts);
    natsOptions_SetURL(opts, url.c_str());
    natsOptions_SetMaxReconnect(opts, -1);        // infinite in-session reconnects
    natsOptions_SetReconnectWait(opts, 2000);     // 2 s between auto-reconnects

    natsConnection* nc = nullptr;
    for (int i = 1; i <= kMaxRetries; ++i) {
        natsStatus s = natsConnection_Connect(&nc, opts);
        if (s == NATS_OK) {
            natsOptions_Destroy(opts);
            return nc;
        }
        log_json("warn", "NATS connect attempt " + std::to_string(i) + "/" +
                         std::to_string(kMaxRetries) + " failed, retrying in " +
                         std::to_string(kRetryDelaySec) + "s");
        std::this_thread::sleep_for(std::chrono::seconds(kRetryDelaySec));
    }
    natsOptions_Destroy(opts);
    return nullptr;
}

}  // anonymous namespace

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main() {
    auto cfg = eyed::Config::from_env();

    {
        nlohmann::json j;
        j["level"]        = "info";
        j["msg"]          = "EyeD storage service (C++) starting";
        j["nats_url"]     = cfg.nats_url;
        j["archive_root"] = cfg.archive_root;
        j["http_port"]    = cfg.http_port;
        std::cout << j.dump() << "\n" << std::flush;
    }

    // ----- Store & handler -----
    eyed::LocalStore      store(cfg.archive_root);
    eyed::ArchiveHandler  handler(&store);
    eyed::RetentionPurger purger(&store, cfg.retention_raw_days);

    // ----- NATS -----
    natsConnection* nc = connect_nats(cfg.nats_url);
    if (!nc) {
        log_json("error", "Failed to connect to NATS after all retries — exiting");
        return 1;
    }
    log_json("info", "Connected to NATS at " + cfg.nats_url);

    natsSubscription* sub = nullptr;
    natsStatus s = natsConnection_Subscribe(&sub, nc, "eyed.archive",
                                            nats_archive_cb, &handler);
    if (s != NATS_OK) {
        log_json("error", "Failed to subscribe to eyed.archive");
        natsConnection_Destroy(nc);
        return 1;
    }
    log_json("info", "Subscribed to eyed.archive");
    purger.start();
    log_json("info", "Retention purger started (raw_days=" +
             std::to_string(cfg.retention_raw_days) + ")");

    // ----- HTTP health server -----
    httplib::Server svr;

    svr.Get("/health/alive", [](const httplib::Request&, httplib::Response& res) {
        res.set_content(R"({"alive":true})", "application/json");
    });

    svr.Get("/health/ready", [&](const httplib::Request&, httplib::Response& res) {
        bool connected = (natsConnection_Status(nc) == NATS_CONN_STATUS_CONNECTED);
        nlohmann::json j;
        j["alive"]          = true;
        j["ready"]          = connected;
        j["nats_connected"] = connected;
        j["archived"]       = handler.archived();
        j["errors"]         = handler.errors();
        j["version"]        = "0.1.0";
        res.set_content(j.dump(), "application/json");
    });

    int http_port = std::stoi(cfg.http_port);
    std::thread http_thread([&]() {
        log_json("info", "HTTP health server on port " + cfg.http_port);
        svr.listen("0.0.0.0", http_port);
    });

    // ----- Signals -----
    std::signal(SIGINT,  on_signal);
    std::signal(SIGTERM, on_signal);

    log_json("info", "Service ready");

    // ----- Main loop -----
    while (g_running) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    // ----- Graceful shutdown -----
    log_json("info", "Shutting down...");

    purger.stop();
    svr.stop();
    if (http_thread.joinable()) http_thread.join();

    natsSubscription_Destroy(sub);
    natsConnection_Drain(nc);
    natsConnection_Destroy(nc);

    log_json("info", "Shutdown complete — archived=" +
             std::to_string(handler.archived()) +
             " errors=" + std::to_string(handler.errors()));
    return 0;
}
