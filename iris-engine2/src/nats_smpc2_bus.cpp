#include "nats_smpc2_bus.h"
#include "smpc2_nats_codec.h"

#include <future>

namespace iris {

NatsSMPC2Bus::NatsSMPC2Bus(std::shared_ptr<INatsClient> client, std::string subject_prefix)
    : client_(std::move(client)), prefix_(std::move(subject_prefix)) {}

Result<void> NatsSMPC2Bus::publish_share_sync(const ShamirShareSyncJob& job) const {
    auto payload_r = encode_shamir_share_sync_job(job);
    if (!payload_r.has_value()) return std::unexpected(payload_r.error());

    const std::string subject =
        prefix_ + ".party." + std::to_string(job.participant_id) + ".share_sync";

    return client_->publish(subject, *payload_r);
}

std::future<Result<ShamirMatchResponse>> NatsSMPC2Bus::request_match(
    const ShamirMatchJob& job) const {
    std::promise<Result<ShamirMatchResponse>> p;

    auto payload_r = encode_shamir_match_job(job);
    if (!payload_r.has_value()) {
        p.set_value(std::unexpected(payload_r.error()));
        return p.get_future();
    }

    const std::string subject =
        prefix_ + ".party." + std::to_string(job.participant_id) + ".match";

    auto resp_payload_r = client_->request(subject, *payload_r);
    if (!resp_payload_r.has_value()) {
        p.set_value(std::unexpected(resp_payload_r.error()));
        return p.get_future();
    }

    p.set_value(decode_shamir_match_response(*resp_payload_r));
    return p.get_future();
}

}  // namespace iris
