#include <csignal>
#include <cstdlib>
#include <iostream>
#include <string>
#include <thread>
#include <chrono>

#include <nats.h>

#include "he_context.h"
#include "handlers.h"

namespace {

volatile sig_atomic_t g_running = 1;

void SignalHandler(int /*sig*/) {
    g_running = 0;
}

std::string GetEnv(const char* name, const std::string& default_val) {
    const char* val = std::getenv(name);
    return val ? std::string(val) : default_val;
}

}  // anonymous namespace

int main() {
    // --- Configuration from environment ---
    auto nats_url = GetEnv("EYED_NATS_URL", "nats://nats:4222");
    auto key_dir = GetEnv("EYED_HE_KEY_DIR", "/keys");
    auto log_level = GetEnv("EYED_LOG_LEVEL", "info");

    std::cout << "[key-service] Starting..." << std::endl;
    std::cout << "[key-service] NATS URL: " << nats_url << std::endl;
    std::cout << "[key-service] Key directory: " << key_dir << std::endl;

    // --- Initialize HE context (generate or load keys) ---
    if (!eyed::InitContext(key_dir)) {
        std::cerr << "[key-service] FATAL: Failed to initialize HE context" << std::endl;
        return 1;
    }

    std::cout << "[key-service] HE context ready (ring_dim="
              << eyed::GetRingDimension() << ")" << std::endl;

    // --- Connect to NATS ---
    natsConnection* nc = nullptr;
    natsOptions* opts = nullptr;
    natsStatus s;

    s = natsOptions_Create(&opts);
    if (s != NATS_OK) {
        std::cerr << "[key-service] FATAL: Failed to create NATS options: "
                  << natsStatus_GetText(s) << std::endl;
        return 1;
    }

    natsOptions_SetURL(opts, nats_url.c_str());
    natsOptions_SetMaxReconnect(opts, -1);  // Infinite reconnect
    natsOptions_SetReconnectWait(opts, 2000);  // 2 seconds

    // Retry connection with backoff
    int retries = 0;
    const int max_retries = 30;
    while (retries < max_retries) {
        s = natsConnection_Connect(&nc, opts);
        if (s == NATS_OK) break;

        retries++;
        std::cout << "[key-service] NATS connection attempt " << retries
                  << "/" << max_retries << " failed, retrying..." << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }

    natsOptions_Destroy(opts);

    if (s != NATS_OK) {
        std::cerr << "[key-service] FATAL: Could not connect to NATS at "
                  << nats_url << " after " << max_retries << " attempts" << std::endl;
        return 1;
    }

    std::cout << "[key-service] Connected to NATS" << std::endl;

    // --- Subscribe to NATS subjects ---
    natsSubscription* sub_decrypt_batch = nullptr;
    natsSubscription* sub_decrypt_template = nullptr;
    natsSubscription* sub_health = nullptr;

    s = natsConnection_Subscribe(&sub_decrypt_batch, nc,
        "eyed.key.decrypt_batch", eyed::HandleDecryptBatch, nullptr);
    if (s != NATS_OK) {
        std::cerr << "[key-service] Failed to subscribe to eyed.key.decrypt_batch" << std::endl;
        return 1;
    }

    s = natsConnection_Subscribe(&sub_decrypt_template, nc,
        "eyed.key.decrypt_template", eyed::HandleDecryptTemplate, nullptr);
    if (s != NATS_OK) {
        std::cerr << "[key-service] Failed to subscribe to eyed.key.decrypt_template" << std::endl;
        return 1;
    }

    s = natsConnection_Subscribe(&sub_health, nc,
        "eyed.key.health", eyed::HandleHealth, nullptr);
    if (s != NATS_OK) {
        std::cerr << "[key-service] Failed to subscribe to eyed.key.health" << std::endl;
        return 1;
    }

    std::cout << "[key-service] Subscribed to NATS subjects: "
              << "eyed.key.decrypt_batch, eyed.key.decrypt_template, eyed.key.health"
              << std::endl;
    std::cout << "[key-service] Ready." << std::endl;

    // --- Main loop: wait for shutdown signal ---
    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);

    while (g_running) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    // --- Cleanup ---
    std::cout << "[key-service] Shutting down..." << std::endl;

    natsSubscription_Destroy(sub_decrypt_batch);
    natsSubscription_Destroy(sub_decrypt_template);
    natsSubscription_Destroy(sub_health);
    natsConnection_Destroy(nc);

    std::cout << "[key-service] Shutdown complete." << std::endl;
    return 0;
}
