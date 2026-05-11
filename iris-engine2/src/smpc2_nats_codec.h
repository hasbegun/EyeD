#pragma once

#include <vector>
#include <cstdint>

#include <iris/core/error.hpp>
#include <iris/crypto/smpc2_queue.hpp>

namespace iris {

/// Binary codec for SMPC2 (Shamir) messages over NATS.
///
/// Wire format (all little-endian):
///
/// ShamirShare:
///   party_id   u8
///   x_coord    u64
///   code_share 128 × u64
///   mask_share 128 × u64
///
/// ShamirShareSyncJob:
///   subject_id  u32-len-prefixed string
///   participant_id u8
///   share       ShamirShare
///
/// ShamirMatchJob:
///   participant_id u8
///   probe_share   ShamirShare
///
/// ShamirMatchResponse:
///   participant_id u8
///   row_count      u32
///   rows[]:
///     subject_id  u32-len-prefixed string
///     xor_share   ShamirShare

[[nodiscard]] Result<std::vector<uint8_t>> encode_shamir_share_sync_job(
    const ShamirShareSyncJob& job);

[[nodiscard]] Result<ShamirShareSyncJob> decode_shamir_share_sync_job(
    const std::vector<uint8_t>& payload);

[[nodiscard]] Result<std::vector<uint8_t>> encode_shamir_match_job(
    const ShamirMatchJob& job);

[[nodiscard]] Result<ShamirMatchJob> decode_shamir_match_job(
    const std::vector<uint8_t>& payload);

[[nodiscard]] Result<std::vector<uint8_t>> encode_shamir_match_response(
    const ShamirMatchResponse& resp);

[[nodiscard]] Result<ShamirMatchResponse> decode_shamir_match_response(
    const std::vector<uint8_t>& payload);

}  // namespace iris
