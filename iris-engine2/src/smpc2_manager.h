#pragma once

#include <memory>
#include <string>
#include <vector>

#include <iris/core/error.hpp>
#include <iris/core/types.hpp>

namespace iris {
class SMPC2Coordinator;
class ISMPC2Bus;
}

class CNatsClient;

/// Result row from SMPC2 verify — parallel to CoordinatorVerifyResult.
struct SMPC2VerifyResult {
    std::string subject_id;
    double distance = 1.0;
    bool is_match = false;
};

/// SMPC2 manager for iris-engine2.
///
/// Wraps SMPC2Coordinator (Shamir (k,n) with random placement).
/// Supports two modes:
///   "simulated"   – in-process InMemorySMPC2Bus (no NATS)
///   "distributed" – NatsSMPC2Bus over NATS (requires nats_url + party containers)
class SMPC2Manager {
  public:
    SMPC2Manager();
    ~SMPC2Manager();
    SMPC2Manager(SMPC2Manager&&) noexcept;
    SMPC2Manager& operator=(SMPC2Manager&&) noexcept;

    /// Initialize. Returns true on success.
    /// @param mode         "simulated" or "distributed"
    /// @param nats_url     Required for distributed mode
    /// @param total_parties Number of Shamir parties (3–15; default 5)
    /// @param tls_cert_dir  mTLS certs dir (empty = TLS disabled)
    bool init(const std::string& mode,
              const std::string& nats_url,
              int total_parties = 5,
              const std::string& tls_cert_dir = "");

    [[nodiscard]] bool is_active()       const noexcept { return active_; }
    [[nodiscard]] bool is_distributed()  const noexcept { return mode_ == "distributed"; }
    [[nodiscard]] bool is_nats_connected() const noexcept;
    [[nodiscard]] const std::string& mode() const noexcept { return mode_; }
    [[nodiscard]] uint8_t total_parties() const noexcept;
    [[nodiscard]] uint8_t threshold()    const noexcept;

    iris::Result<void> enroll(const std::string& subject_id,
                               const iris::IrisTemplate& tmpl);

    iris::Result<std::vector<SMPC2VerifyResult>> verify(
        const iris::IrisTemplate& probe) const;

    [[nodiscard]] size_t size() const;

  private:
    bool active_ = false;
    std::string mode_;
    // Order matters: nats_client_ must outlive bus_, which must outlive coordinator_.
    std::shared_ptr<CNatsClient> nats_client_;
    std::shared_ptr<iris::ISMPC2Bus> bus_;
    std::unique_ptr<iris::SMPC2Coordinator> coordinator_;
};
