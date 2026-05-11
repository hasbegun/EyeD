#include "smpc2_manager.h"
#include "nats_smpc2_bus.h"
#include "nats_client.h"

#include <algorithm>
#include <iostream>

#include <iris/crypto/smpc2_coordinator.hpp>
#include <iris/crypto/smpc2_participant.hpp>
#include <iris/crypto/smpc2_queue.hpp>
#include <iris/crypto/smpc_config.hpp>

SMPC2Manager::SMPC2Manager() = default;
SMPC2Manager::~SMPC2Manager() = default;
SMPC2Manager::SMPC2Manager(SMPC2Manager&&) noexcept = default;
SMPC2Manager& SMPC2Manager::operator=(SMPC2Manager&&) noexcept = default;

bool SMPC2Manager::init(const std::string& mode,
                         const std::string& nats_url,
                         int total_parties,
                         const std::string& tls_cert_dir) {
    mode_ = mode;

    iris::SMPCConfig cfg{};
    cfg.total_parties = static_cast<uint8_t>(std::clamp(total_parties, 3, 15));
    cfg.threshold     = static_cast<uint8_t>((cfg.total_parties + 1) / 2);
    if (cfg.threshold < 2) cfg.threshold = 2;
    cfg.store_count   = cfg.threshold;

    if (mode == "simulated") {
        auto mem_bus = std::make_shared<iris::InMemorySMPC2Bus>();
        for (int i = 1; i <= cfg.total_parties; ++i) {
            auto participant = std::make_shared<iris::SMPC2ParticipantService>(
                static_cast<uint8_t>(i));
            auto reg_r = mem_bus->register_participant(
                static_cast<uint8_t>(i), participant);
            if (!reg_r.has_value()) {
                std::cerr << "[smpc2] Failed to register in-process participant "
                          << i << ": " << reg_r.error().message << "\n";
                return false;
            }
        }
        bus_ = mem_bus;
        coordinator_ = std::make_unique<iris::SMPC2Coordinator>(cfg, bus_);
        active_ = true;
        std::cout << "[smpc2] Initialized in simulated mode ("
                  << cfg.to_string() << ", "
                  << static_cast<int>(cfg.total_parties) << " in-process participants)\n";
        return true;
    }

    // distributed mode
    if (nats_url.empty()) {
        std::cerr << "[smpc2] Distributed mode requires EYED_NATS_URL\n";
        return false;
    }

    nats_client_ = std::make_shared<CNatsClient>();
    bool connected = false;

    if (!tls_cert_dir.empty()) {
        NatsTLSConfig tls_cfg;
        tls_cfg.ca_cert_path = tls_cert_dir + "/ca.crt";
        tls_cfg.cert_path    = tls_cert_dir + "/coordinator.crt";
        tls_cfg.key_path     = tls_cert_dir + "/coordinator.key";
        connected = nats_client_->connect(nats_url, tls_cfg);
    } else {
        connected = nats_client_->connect(nats_url);
    }

    if (!connected) {
        std::cerr << "[smpc2] Failed to connect to NATS at " << nats_url << "\n";
        nats_client_.reset();
        return false;
    }

    bus_ = std::make_shared<iris::NatsSMPC2Bus>(
        std::shared_ptr<iris::INatsClient>(nats_client_.get(), [](iris::INatsClient*){}),
        "smpc2");

    coordinator_ = std::make_unique<iris::SMPC2Coordinator>(cfg, bus_);
    active_ = true;

    std::cout << "[smpc2] Initialized in distributed mode ("
              << cfg.to_string() << ", NATS: " << nats_url << ")\n";
    return true;
}

bool SMPC2Manager::is_nats_connected() const noexcept {
    return nats_client_ && nats_client_->is_connected();
}

uint8_t SMPC2Manager::total_parties() const noexcept {
    return coordinator_ ? coordinator_->config().total_parties : 0;
}

uint8_t SMPC2Manager::threshold() const noexcept {
    return coordinator_ ? coordinator_->config().threshold : 0;
}

iris::Result<void> SMPC2Manager::enroll(const std::string& subject_id,
                                         const iris::IrisTemplate& tmpl) {
    if (!coordinator_) {
        return iris::make_error(iris::ErrorCode::ConfigInvalid,
                                "SMPC2Coordinator not initialized");
    }
    return coordinator_->enroll(subject_id, tmpl);
}

iris::Result<std::vector<SMPC2VerifyResult>> SMPC2Manager::verify(
    const iris::IrisTemplate& probe) const {
    if (!coordinator_) {
        return iris::make_error(iris::ErrorCode::ConfigInvalid,
                                "SMPC2Coordinator not initialized");
    }

    auto rows_r = coordinator_->verify(probe);
    if (!rows_r.has_value()) return std::unexpected(rows_r.error());

    std::vector<SMPC2VerifyResult> out;
    out.reserve(rows_r->size());
    for (const auto& row : *rows_r) {
        out.push_back({row.subject_id, row.distance, row.is_match});
    }
    return out;
}

size_t SMPC2Manager::size() const {
    return coordinator_ ? coordinator_->size() : 0;
}
