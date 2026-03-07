#pragma once

#include <string>

#include <nats.h>

namespace eyed {

// ---------------------------------------------------------------------------
// Configuration (loaded from EYED_* environment variables)
// ---------------------------------------------------------------------------

struct Config {
    std::string nats_url;
    std::string key_dir;
    std::string log_level;
};

Config LoadConfig();

// ---------------------------------------------------------------------------
// NATS lifecycle
// ---------------------------------------------------------------------------

/// Connect to NATS with retry. Returns nullptr on failure.
natsConnection* ConnectNats(const std::string& url);

/// Subscribe to all key-service subjects. Returns false on failure.
bool SubscribeAll(natsConnection* nc);

/// Block until SIGINT or SIGTERM.
void WaitForShutdown();

/// Tear down subscriptions and connection.
void Cleanup(natsConnection* nc);

}  // namespace eyed
