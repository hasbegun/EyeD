#include "smpc2_nats_codec.h"

namespace iris {
namespace {

class ByteWriter2 {
  public:
    void write_u8(uint8_t v) { buf_.push_back(v); }

    void write_u32(uint32_t v) {
        buf_.push_back(static_cast<uint8_t>((v >>  0) & 0xFF));
        buf_.push_back(static_cast<uint8_t>((v >>  8) & 0xFF));
        buf_.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
        buf_.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
    }

    void write_u64(uint64_t v) {
        for (int i = 0; i < 8; ++i)
            buf_.push_back(static_cast<uint8_t>((v >> (8 * i)) & 0xFF));
    }

    void write_string(const std::string& s) {
        write_u32(static_cast<uint32_t>(s.size()));
        const auto* bytes = reinterpret_cast<const uint8_t*>(s.data());
        buf_.insert(buf_.end(), bytes, bytes + s.size());
    }

    void write_share(const ShamirShare& sh) {
        write_u8(sh.party_id);
        write_u64(sh.x_coord);
        for (uint64_t w : sh.code_share) write_u64(w);
        for (uint64_t w : sh.mask_share) write_u64(w);
    }

    [[nodiscard]] std::vector<uint8_t> take() { return std::move(buf_); }

  private:
    std::vector<uint8_t> buf_;
};

class ByteReader2 {
  public:
    explicit ByteReader2(const std::vector<uint8_t>& b) : b_(b) {}

    Result<uint8_t> read_u8() {
        if (pos_ + 1 > b_.size())
            return make_error(ErrorCode::ValidationFailed, "smpc2 codec: underflow (u8)");
        return b_[pos_++];
    }

    Result<uint32_t> read_u32() {
        if (pos_ + 4 > b_.size())
            return make_error(ErrorCode::ValidationFailed, "smpc2 codec: underflow (u32)");
        uint32_t v = 0;
        for (int i = 0; i < 4; ++i)
            v |= static_cast<uint32_t>(b_[pos_++]) << (8 * i);
        return v;
    }

    Result<uint64_t> read_u64() {
        if (pos_ + 8 > b_.size())
            return make_error(ErrorCode::ValidationFailed, "smpc2 codec: underflow (u64)");
        uint64_t v = 0;
        for (int i = 0; i < 8; ++i)
            v |= static_cast<uint64_t>(b_[pos_++]) << (8 * i);
        return v;
    }

    Result<std::string> read_string() {
        auto len_r = read_u32();
        if (!len_r.has_value()) return std::unexpected(len_r.error());
        const auto len = *len_r;
        if (pos_ + len > b_.size())
            return make_error(ErrorCode::ValidationFailed, "smpc2 codec: string underflow");
        std::string s(b_.begin() + static_cast<std::ptrdiff_t>(pos_),
                      b_.begin() + static_cast<std::ptrdiff_t>(pos_ + len));
        pos_ += len;
        return s;
    }

    Result<ShamirShare> read_share() {
        ShamirShare sh{};
        auto id_r = read_u8();
        if (!id_r.has_value()) return std::unexpected(id_r.error());
        sh.party_id = *id_r;

        auto x_r = read_u64();
        if (!x_r.has_value()) return std::unexpected(x_r.error());
        sh.x_coord = *x_r;

        for (auto& w : sh.code_share) {
            auto wr = read_u64();
            if (!wr.has_value()) return std::unexpected(wr.error());
            w = *wr;
        }
        for (auto& w : sh.mask_share) {
            auto wr = read_u64();
            if (!wr.has_value()) return std::unexpected(wr.error());
            w = *wr;
        }
        return sh;
    }

  private:
    const std::vector<uint8_t>& b_;
    size_t pos_ = 0;
};

}  // namespace

// ---------------------------------------------------------------------------

Result<std::vector<uint8_t>> encode_shamir_share_sync_job(const ShamirShareSyncJob& job) {
    ByteWriter2 w;
    w.write_string(job.subject_id);
    w.write_u8(job.participant_id);
    w.write_share(job.share);
    return w.take();
}

Result<ShamirShareSyncJob> decode_shamir_share_sync_job(const std::vector<uint8_t>& payload) {
    ByteReader2 r(payload);
    ShamirShareSyncJob job{};

    auto sid_r = r.read_string();
    if (!sid_r.has_value()) return std::unexpected(sid_r.error());
    job.subject_id = std::move(*sid_r);

    auto pid_r = r.read_u8();
    if (!pid_r.has_value()) return std::unexpected(pid_r.error());
    job.participant_id = *pid_r;

    auto sh_r = r.read_share();
    if (!sh_r.has_value()) return std::unexpected(sh_r.error());
    job.share = std::move(*sh_r);

    return job;
}

Result<std::vector<uint8_t>> encode_shamir_match_job(const ShamirMatchJob& job) {
    ByteWriter2 w;
    w.write_u8(job.participant_id);
    w.write_share(job.probe_share);
    return w.take();
}

Result<ShamirMatchJob> decode_shamir_match_job(const std::vector<uint8_t>& payload) {
    ByteReader2 r(payload);
    ShamirMatchJob job{};

    auto pid_r = r.read_u8();
    if (!pid_r.has_value()) return std::unexpected(pid_r.error());
    job.participant_id = *pid_r;

    auto sh_r = r.read_share();
    if (!sh_r.has_value()) return std::unexpected(sh_r.error());
    job.probe_share = std::move(*sh_r);

    return job;
}

Result<std::vector<uint8_t>> encode_shamir_match_response(const ShamirMatchResponse& resp) {
    ByteWriter2 w;
    w.write_u8(resp.participant_id);
    w.write_u32(static_cast<uint32_t>(resp.rows.size()));
    for (const auto& row : resp.rows) {
        w.write_string(row.subject_id);
        w.write_share(row.xor_share);
    }
    return w.take();
}

Result<ShamirMatchResponse> decode_shamir_match_response(const std::vector<uint8_t>& payload) {
    ByteReader2 r(payload);
    ShamirMatchResponse resp{};

    auto pid_r = r.read_u8();
    if (!pid_r.has_value()) return std::unexpected(pid_r.error());
    resp.participant_id = *pid_r;

    auto cnt_r = r.read_u32();
    if (!cnt_r.has_value()) return std::unexpected(cnt_r.error());
    const auto count = *cnt_r;

    resp.rows.reserve(count);
    for (uint32_t i = 0; i < count; ++i) {
        ShamirMatchRow row{};

        auto sid_r = r.read_string();
        if (!sid_r.has_value()) return std::unexpected(sid_r.error());
        row.subject_id = std::move(*sid_r);

        auto sh_r = r.read_share();
        if (!sh_r.has_value()) return std::unexpected(sh_r.error());
        row.xor_share = std::move(*sh_r);

        resp.rows.push_back(std::move(row));
    }
    return resp;
}

}  // namespace iris
