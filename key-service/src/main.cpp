#include <iostream>

#include "he_context.h"
#include "nats_service.h"

int main() {
    auto config = eyed::LoadConfig();

    std::cout << "[key-service] Starting..." << std::endl;
    std::cout << "[key-service] NATS URL: " << config.nats_url << std::endl;
    std::cout << "[key-service] Key dir:  " << config.key_dir << std::endl;

    if (!eyed::InitContext(config.key_dir)) {
        std::cerr << "[key-service] FATAL: HE context init failed" << std::endl;
        return 1;
    }
    std::cout << "[key-service] HE context ready (ring_dim="
              << eyed::GetRingDimension() << ")" << std::endl;

    auto* nc = eyed::ConnectNats(config.nats_url);
    if (!nc) return 1;

    if (!eyed::SubscribeAll(nc)) return 1;

    std::cout << "[key-service] Ready." << std::endl;

    eyed::WaitForShutdown();
    eyed::Cleanup(nc);
    return 0;
}
