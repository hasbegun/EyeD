#pragma once

#include <memory>
#include <string>

#include <iris/core/error.hpp>
#include <iris/core/types.hpp>

namespace iris {
class SMPCGallery;
class SMPCCoordinatorService;
class SMPCPipelinedCoordinator;
class SMPCShardedCoordinator;
class ISMPCBus;
class TLSContext;
class SecurityMonitor;
class HealthCheckService;
}

class CNatsClient;

/// Result from coordinator verify — avoids including smpc_coordinator_service.hpp
/// (which conflicts with hamming_distance_matcher.hpp via duplicate MatchResult).
struct CoordinatorVerifyResult {
    std::string subject_id;
    double distance = 1.0;
};

/// Security configuration for mTLS, audit logging, and monitoring.
struct SMPCSecurityConfig {
    std::string tls_cert_dir;              // empty = TLS disabled
    std::string audit_log_path;            // empty = audit disabled
    bool security_monitor_enabled = false;
};

/// SMPC manager for iris-engine2.
///
/// Wraps libiris SMPC classes to provide template protection via
/// 3-party replicated secret sharing.  Two modes:
///
///   - "simulated":   All 3 parties run in-process via SMPCGallery.
///                    No network required.  Same cryptographic protocol.
///
///   - "distributed": Coordinator + 3 participants over NATS message bus.
///                    Requires NATS URL and running participant services.
class SMPCManager {
  public:
    SMPCManager();
    ~SMPCManager();
    SMPCManager(SMPCManager&&) noexcept;
    SMPCManager& operator=(SMPCManager&&) noexcept;

    using SecurityConfig = SMPCSecurityConfig;

    /// Initialize the SMPC subsystem.
    /// @param mode                    "simulated" or "distributed"
    /// @param nats_url                NATS URL (required for distributed mode)
    /// @param num_parties             Number of parties (must be 3)
    /// @param pipeline_depth          0 = disabled, >0 = pipelined coordinator
    /// @param shards_per_participant  0 = no sharding, >0 = sharded coordinator
    /// @param security                Security config (all disabled by default)
    /// @return true on success
    bool initialize(const std::string& mode,
                    const std::string& nats_url = "",
                    int num_parties = 3,
                    int pipeline_depth = 0,
                    int shards_per_participant = 0,
                    const SecurityConfig& security = SecurityConfig{});

    /// Whether SMPC is initialized and ready.
    [[nodiscard]] bool is_active() const noexcept;

    /// Current mode ("simulated" or "distributed").
    [[nodiscard]] const std::string& mode() const noexcept;

    /// Whether running in distributed mode.
    [[nodiscard]] bool is_distributed() const noexcept;

    /// Access the in-process SMPC gallery (simulated mode).
    /// Returns nullptr if not in simulated mode or not initialized.
    [[nodiscard]] iris::SMPCGallery* gallery() noexcept;
    [[nodiscard]] const iris::SMPCGallery* gallery() const noexcept;

    /// Enroll a template via the coordinator (distributed mode).
    /// Splits into shares and distributes to participants over NATS.
    iris::Result<void> enroll_distributed(const std::string& subject_id,
                                          const iris::IrisTemplate& tmpl);

    /// Verify a probe via the coordinator (distributed mode).
    /// Sends probe shares to participants and reconstructs distances.
    iris::Result<std::vector<CoordinatorVerifyResult>> verify_distributed(
        const iris::IrisTemplate& probe) const;

    /// Number of enrolled templates in the coordinator.
    size_t coordinator_size() const;

    /// Whether mTLS is enabled.
    [[nodiscard]] bool tls_enabled() const noexcept;

    /// Whether audit logging is enabled.
    [[nodiscard]] bool audit_enabled() const noexcept;

    /// Get security monitor status report (empty string if disabled).
    [[nodiscard]] std::string security_status() const;

    /// Bulk re-enroll plaintext templates into SMPC (migration helper).
    /// Returns the number of successfully migrated templates.
    struct MigrationStats {
        int total = 0;
        int succeeded = 0;
        int failed = 0;
        double elapsed_ms = 0.0;
    };
    MigrationStats migrate_templates(
        const std::vector<std::pair<std::string, iris::IrisTemplate>>& templates);

  private:
    std::string mode_;
    bool active_ = false;

    // Simulated mode
    std::unique_ptr<iris::SMPCGallery> gallery_;

    // Distributed mode (implemented in smpc_distributed.cpp)
    // shared_ptr used for nats_client_ and coordinator_ because their
    // complete types cannot coexist with smpc_gallery.hpp in one TU
    // (iris::MatchResult redefinition).  shared_ptr dtor is type-erased.
    std::shared_ptr<CNatsClient> nats_client_;
    std::shared_ptr<iris::ISMPCBus> bus_;
    std::shared_ptr<iris::SMPCCoordinatorService> coordinator_;
    std::shared_ptr<iris::SMPCPipelinedCoordinator> pipelined_;
    std::shared_ptr<iris::SMPCShardedCoordinator> sharded_;
    int pipeline_depth_ = 0;
    int shards_per_participant_ = 0;

    // Security (Phase 4)
    SecurityConfig security_config_;
    std::shared_ptr<iris::TLSContext> tls_context_;
    std::shared_ptr<iris::SecurityMonitor> security_monitor_;
    std::shared_ptr<iris::HealthCheckService> health_service_;

    bool init_distributed(const std::string& nats_url, int num_parties,
                          int pipeline_depth, int shards_per_participant);
    void destroy_distributed();
    bool init_security(const SecurityConfig& security);
};
