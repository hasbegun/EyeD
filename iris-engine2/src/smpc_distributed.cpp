// Distributed-mode methods for SMPCManager.
// Isolated in a separate TU because smpc_coordinator_service.hpp and
// smpc_gallery.hpp both define iris::MatchResult (libiris header conflict).
#include "smpc.h"
#include "nats_client.h"

#include <iostream>

#include <iris/crypto/smpc_coordinator_service.hpp>
#include <iris/crypto/smpc_pipelined_coordinator.hpp>
#include <iris/crypto/smpc_sharded_gallery.hpp>
#include <iris/crypto/smpc_queue.hpp>
#include <iris/crypto/smpc_tls.hpp>
#include <iris/crypto/smpc_audit.hpp>

bool SMPCManager::init_security(const SecurityConfig& security) {
    security_config_ = security;

    // Audit logging
    if (!security.audit_log_path.empty()) {
        iris::AuditLogger::instance().set_log_file(security.audit_log_path);
        iris::AuditLogger::instance().log_event({
            iris::AuditEventType::ServiceStartup,
            std::chrono::system_clock::now(),
            "iris-engine2", "", "",
            "SMPC service starting (mode=" + mode_ + ")",
            true});
        std::cout << "[smpc] Audit logging enabled: " << security.audit_log_path << std::endl;
    }

    // TLS context (loaded here, used by init_distributed for NATS)
    if (!security.tls_cert_dir.empty()) {
        iris::TLSConfig tls_cfg{};
        tls_cfg.ca_cert_path = security.tls_cert_dir + "/ca.crt";
        tls_cfg.cert_path    = security.tls_cert_dir + "/coordinator.crt";
        tls_cfg.key_path     = security.tls_cert_dir + "/coordinator.key";

        auto ctx_r = iris::TLSContext::create(tls_cfg);
        if (!ctx_r.has_value()) {
            std::cerr << "[smpc] Failed to create TLS context: "
                      << ctx_r.error().message << std::endl;
            return false;
        }
        tls_context_ = std::shared_ptr<iris::TLSContext>(std::move(*ctx_r));
        std::cout << "[smpc] mTLS enabled (certs: " << security.tls_cert_dir << ")" << std::endl;
    }

    // Security monitor
    if (security.security_monitor_enabled) {
        security_monitor_ = std::make_shared<iris::SecurityMonitor>("iris-engine2");
        health_service_ = std::make_shared<iris::HealthCheckService>("iris-engine2", "1.0");
        std::cout << "[smpc] Security monitor enabled" << std::endl;
    }

    return true;
}

std::string SMPCManager::security_status() const {
    if (!security_monitor_) return "";
    return security_monitor_->get_status_report();
}

bool SMPCManager::init_distributed(const std::string& nats_url, int num_parties,
                                    int pipeline_depth, int shards_per_participant) {
    if (nats_url.empty()) {
        std::cerr << "[smpc] Distributed mode requires EYED_NATS_URL" << std::endl;
        return false;
    }

    // 1. Connect to NATS (with or without mTLS)
    nats_client_ = std::make_shared<CNatsClient>();
    bool connected = false;
    if (tls_context_) {
        const auto& cfg = tls_context_->config();
        NatsTLSConfig nats_tls{};
        nats_tls.ca_cert_path = cfg.ca_cert_path;
        nats_tls.cert_path    = cfg.cert_path;
        nats_tls.key_path     = cfg.key_path;
        connected = nats_client_->connect(nats_url, nats_tls);
    } else {
        connected = nats_client_->connect(nats_url);
    }
    if (!connected) {
        std::cerr << "[smpc] Failed to connect to NATS at " << nats_url << std::endl;
        nats_client_.reset();
        return false;
    }

    // 2. Create NATSSMPCBus over the NATS connection
    bus_ = std::make_shared<iris::NATSSMPCBus>(
        std::shared_ptr<iris::INatsClient>(nats_client_.get(), [](iris::INatsClient*){}),
        "smpc");

    pipeline_depth_ = pipeline_depth;
    shards_per_participant_ = shards_per_participant;

    // 3. Create the appropriate coordinator variant
    if (shards_per_participant > 0) {
        // Sharded coordinator — routes subjects to shards by hash
        sharded_ = std::make_shared<iris::SMPCShardedCoordinator>(
            num_parties,
            static_cast<size_t>(shards_per_participant),
            bus_);
        std::cout << "[smpc] Initialized in distributed mode (sharded coordinator, NATS: "
                  << nats_url << ", parties: " << num_parties
                  << ", shards/participant: " << shards_per_participant << ")" << std::endl;
    } else {
        // Plain coordinator
        coordinator_ = std::make_shared<iris::SMPCCoordinatorService>(num_parties, bus_);

        if (pipeline_depth > 0) {
            // Pipelined coordinator — wraps coordinator for async verification
            pipelined_ = std::make_shared<iris::SMPCPipelinedCoordinator>(
                num_parties, bus_,
                static_cast<size_t>(pipeline_depth));
            std::cout << "[smpc] Initialized in distributed mode (pipelined coordinator, NATS: "
                      << nats_url << ", parties: " << num_parties
                      << ", pipeline_depth: " << pipeline_depth << ")" << std::endl;
        } else {
            std::cout << "[smpc] Initialized in distributed mode (coordinator, NATS: "
                      << nats_url << ", parties: " << num_parties << ")" << std::endl;
        }
    }

    return true;
}

void SMPCManager::destroy_distributed() {
    sharded_.reset();
    pipelined_.reset();
    coordinator_.reset();
    bus_.reset();
    if (nats_client_) {
        nats_client_->disconnect();
    }
    nats_client_.reset();
}

iris::Result<void> SMPCManager::enroll_distributed(
    const std::string& subject_id,
    const iris::IrisTemplate& tmpl) {
    iris::Result<void> result;
    if (sharded_) {
        result = sharded_->enroll(subject_id, tmpl);
    } else if (coordinator_) {
        result = coordinator_->enroll(subject_id, tmpl);
    } else {
        return iris::make_error(iris::ErrorCode::ConfigInvalid,
                                "Coordinator not initialized");
    }

    // Audit log
    if (!security_config_.audit_log_path.empty()) {
        iris::AuditLogger::instance().log_enrollment(
            "iris-engine2", subject_id, result.has_value(),
            result.has_value() ? "" : result.error().message);
    }
    if (health_service_) {
        if (result.has_value()) health_service_->record_request_success();
        else health_service_->record_request_failure(result.error().message);
    }

    return result;
}

iris::Result<std::vector<CoordinatorVerifyResult>> SMPCManager::verify_distributed(
    const iris::IrisTemplate& probe) const {
    iris::Result<std::vector<CoordinatorVerifyResult>> result;

    // Sharded coordinator path
    if (sharded_) {
        auto r = sharded_->verify(probe);
        if (!r.has_value()) {
            result = std::unexpected(r.error());
        } else {
            std::vector<CoordinatorVerifyResult> out;
            out.reserve(r->size());
            for (const auto& row : *r) {
                out.push_back({row.subject_id, row.distance});
            }
            result = std::move(out);
        }
    }
    // Pipelined coordinator path — blocking verify_sync
    else if (pipelined_) {
        auto r = pipelined_->verify_sync(probe);
        if (!r.has_value()) {
            result = std::unexpected(r.error());
        } else {
            result = std::vector<CoordinatorVerifyResult>{{r->subject_id, r->distance}};
        }
    }
    // Plain coordinator path
    else if (coordinator_) {
        auto r = coordinator_->verify(probe);
        if (!r.has_value()) {
            result = std::unexpected(r.error());
        } else {
            std::vector<CoordinatorVerifyResult> out;
            out.reserve(r->size());
            for (const auto& row : *r) {
                out.push_back({row.subject_id, row.distance});
            }
            result = std::move(out);
        }
    } else {
        return iris::make_error(iris::ErrorCode::ConfigInvalid,
                                "Coordinator not initialized");
    }

    // Audit log
    if (!security_config_.audit_log_path.empty()) {
        if (result.has_value() && !result->empty()) {
            const auto& best = result->front();
            iris::AuditLogger::instance().log_verification(
                "iris-engine2", best.subject_id, true, best.distance);
        } else if (!result.has_value()) {
            iris::AuditLogger::instance().log_verification(
                "iris-engine2", "", false, 1.0, result.error().message);
        }
    }
    if (health_service_) {
        if (result.has_value()) health_service_->record_request_success();
        else health_service_->record_request_failure(result.error().message);
    }

    return result;
}

size_t SMPCManager::coordinator_size() const {
    if (sharded_) return sharded_->total_gallery_size();
    return coordinator_ ? coordinator_->size() : 0;
}
