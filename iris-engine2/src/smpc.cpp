// Simulated-mode methods and shared logic for SMPCManager.
// Distributed-mode methods live in smpc_distributed.cpp to avoid
// the iris::MatchResult redefinition between smpc_gallery.hpp and
// smpc_coordinator_service.hpp.
#include "smpc.h"
#include "secure_memory.h"

#include <chrono>
#include <iostream>

#include <iris/crypto/smpc_gallery.hpp>

SMPCManager::SMPCManager() = default;
SMPCManager::~SMPCManager() = default;
SMPCManager::SMPCManager(SMPCManager&&) noexcept = default;
SMPCManager& SMPCManager::operator=(SMPCManager&&) noexcept = default;

bool SMPCManager::initialize(const std::string& mode,
                             const std::string& nats_url,
                             int num_parties,
                             int pipeline_depth,
                             int shards_per_participant,
                             const SecurityConfig& security) {
    if (mode != "simulated" && mode != "distributed") {
        std::cerr << "[smpc] Invalid mode: " << mode
                  << " (expected 'simulated' or 'distributed')" << std::endl;
        return false;
    }

    if (num_parties != 3) {
        std::cerr << "[smpc] Only 3-party SMPC is supported (got "
                  << num_parties << ")" << std::endl;
        return false;
    }

    mode_ = mode;

    // Initialize security features (audit, TLS context, monitoring)
    // This is safe for both modes — features are opt-in.
    if (!init_security(security)) {
        return false;
    }

    if (mode_ == "simulated") {
        gallery_ = std::make_unique<iris::SMPCGallery>();
        active_ = true;
        std::cout << "[smpc] Initialized in simulated mode (3-party in-process)"
                  << std::endl;
        return true;
    }

    // Distributed mode — delegated to smpc_distributed.cpp
    if (!init_distributed(nats_url, num_parties, pipeline_depth, shards_per_participant)) {
        return false;
    }
    active_ = true;
    return true;
}

bool SMPCManager::is_active() const noexcept {
    return active_;
}

const std::string& SMPCManager::mode() const noexcept {
    return mode_;
}

bool SMPCManager::is_distributed() const noexcept {
    return active_ && mode_ == "distributed";
}

iris::SMPCGallery* SMPCManager::gallery() noexcept {
    return gallery_.get();
}

const iris::SMPCGallery* SMPCManager::gallery() const noexcept {
    return gallery_.get();
}

bool SMPCManager::tls_enabled() const noexcept {
    return tls_context_ != nullptr;
}

bool SMPCManager::audit_enabled() const noexcept {
    return !security_config_.audit_log_path.empty();
}

SMPCManager::MigrationStats SMPCManager::migrate_templates(
    const std::vector<std::pair<std::string, iris::IrisTemplate>>& templates) {
    MigrationStats stats;
    stats.total = static_cast<int>(templates.size());

    auto t0 = std::chrono::steady_clock::now();

    for (const auto& [subject_id, tmpl] : templates) {
        if (mode_ == "simulated" && gallery_) {
            auto r = gallery_->add_template(subject_id, tmpl);
            if (r.has_value()) ++stats.succeeded;
            else {
                ++stats.failed;
                std::cerr << "[smpc] Migration failed for " << subject_id
                          << ": " << r.error().message << std::endl;
            }
        } else if (is_distributed()) {
            auto r = enroll_distributed(subject_id, tmpl);
            if (r.has_value()) ++stats.succeeded;
            else {
                ++stats.failed;
                std::cerr << "[smpc] Migration failed for " << subject_id
                          << ": " << r.error().message << std::endl;
            }
        } else {
            ++stats.failed;
        }
    }

    auto t1 = std::chrono::steady_clock::now();
    stats.elapsed_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    std::cout << "[smpc] Migration complete: " << stats.succeeded << "/"
              << stats.total << " templates in " << stats.elapsed_ms << " ms";
    if (stats.failed > 0) {
        std::cout << " (" << stats.failed << " failed)";
    }
    std::cout << std::endl;

    return stats;
}
