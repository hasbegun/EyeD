#include "nats_service.h"

#include <csignal>
#include <cstdlib>
#include <chrono>
#include <iostream>
#include <thread>
#include <vector>

#include "handlers.h"

namespace {

// ---------------------------------------------------------------------------
// Signal handling
// ---------------------------------------------------------------------------

volatile sig_atomic_t g_running = 1;

void SignalHandler(int /*sig*/) { g_running = 0; }

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

std::string GetEnv(const char* name, const std::string& default_val) {
    const char* val = std::getenv(name);
    return val ? std::string(val) : default_val;
}

// Active subscriptions (tracked for cleanup).
std::vector<natsSubscription*> g_subscriptions;

}  // anonymous namespace

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

namespace eyed {

Config LoadConfig() {
    return Config{
        .nats_url  = GetEnv("EYED_NATS_URL",   "nats://nats:4222"),
        .key_dir   = GetEnv("EYED_HE_KEY_DIR",  "/keys"),
        .log_level = GetEnv("EYED_LOG_LEVEL",    "info"),
    };
}

natsConnection* ConnectNats(const std::string& url) {
    natsOptions* opts = nullptr;
    natsStatus s = natsOptions_Create(&opts);
    if (s != NATS_OK) {
        std::cerr << "[key-service] FATAL: NATS options: "
                  << natsStatus_GetText(s) << std::endl;
        return nullptr;
    }

    natsOptions_SetURL(opts, url.c_str());
    natsOptions_SetMaxReconnect(opts, -1);     // infinite reconnect
    natsOptions_SetReconnectWait(opts, 2000);  // 2 s

    natsConnection* nc = nullptr;
    constexpr int kMaxRetries = 30;

    for (int i = 1; i <= kMaxRetries; ++i) {
        s = natsConnection_Connect(&nc, opts);
        if (s == NATS_OK) break;

        std::cout << "[key-service] NATS attempt " << i << "/" << kMaxRetries
                  << " failed, retrying..." << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }

    natsOptions_Destroy(opts);

    if (s != NATS_OK) {
        std::cerr << "[key-service] FATAL: Could not connect to NATS at "
                  << url << std::endl;
        return nullptr;
    }

    std::cout << "[key-service] Connected to NATS" << std::endl;
    return nc;
}

bool SubscribeAll(natsConnection* nc) {
    struct SubInfo {
        const char* subject;
        natsMsgHandler handler;
    };

    const SubInfo subs[] = {
        {"eyed.key.decrypt_batch",    HandleDecryptBatch},
        {"eyed.key.decrypt_template", HandleDecryptTemplate},
        {"eyed.key.health",           HandleHealth},
    };

    for (const auto& info : subs) {
        natsSubscription* sub = nullptr;
        natsStatus s = natsConnection_Subscribe(
            &sub, nc, info.subject, info.handler, nullptr);
        if (s != NATS_OK) {
            std::cerr << "[key-service] Failed to subscribe to "
                      << info.subject << std::endl;
            return false;
        }
        g_subscriptions.push_back(sub);
    }

    std::cout << "[key-service] Subscribed to "
              << g_subscriptions.size() << " subjects" << std::endl;
    return true;
}

void WaitForShutdown() {
    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);

    while (g_running) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

void Cleanup(natsConnection* nc) {
    std::cout << "[key-service] Shutting down..." << std::endl;

    for (auto* sub : g_subscriptions) {
        natsSubscription_Destroy(sub);
    }
    g_subscriptions.clear();

    natsConnection_Destroy(nc);
    std::cout << "[key-service] Shutdown complete." << std::endl;
}

}  // namespace eyed
