#pragma once

#include <memory>
#include <string>

#include <iris/crypto/smpc2_queue.hpp>
#include <iris/crypto/smpc_queue.hpp>

namespace iris {

/// NATS-backed implementation of ISMPC2Bus.
///
/// Subject layout (subject_prefix defaults to "smpc2"):
///   share_sync: <prefix>.party.<id>.share_sync    (publish)
///   match:      <prefix>.party.<id>.match          (request/reply)
class NatsSMPC2Bus : public ISMPC2Bus {
  public:
    NatsSMPC2Bus(std::shared_ptr<INatsClient> client,
                 std::string subject_prefix = "smpc2");

    Result<void> publish_share_sync(const ShamirShareSyncJob& job) const override;

    std::future<Result<ShamirMatchResponse>> request_match(
        const ShamirMatchJob& job) const override;

  private:
    std::shared_ptr<INatsClient> client_;
    std::string prefix_;
};

}  // namespace iris
