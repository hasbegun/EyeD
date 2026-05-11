#include "smpc2_manager.h"
#include "smpc2_nats_codec.h"

#include <doctest/doctest.h>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>
#include <iris/crypto/smpc2_queue.hpp>

namespace {

static iris::PackedIrisCode make_code(uint64_t seed) {
    iris::PackedIrisCode code;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        code.code_bits[i] = seed ^ (i * 0x9E3779B97F4A7C15ULL);
        code.mask_bits[i] = ~uint64_t{0};
    }
    return code;
}

static iris::IrisTemplate make_template(uint64_t seed) {
    iris::IrisTemplate tmpl;
    iris::PackedIrisCode ic = make_code(seed);
    tmpl.iris_codes.push_back(ic);
    return tmpl;
}

}  // namespace

// ---------------------------------------------------------------------------
// Codec round-trip tests
// ---------------------------------------------------------------------------

TEST_CASE("SMPC2Codec: ShamirShare encode/decode round-trip") {
    iris::ShamirShare sh{};
    sh.party_id = 3;
    sh.x_coord  = 0xDEADBEEFCAFEBABEULL;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        sh.code_share[i] = static_cast<uint64_t>(i * 13 + 7);
        sh.mask_share[i] = ~static_cast<uint64_t>(i);
    }

    iris::ShamirMatchJob job{};
    job.participant_id = 3;
    job.probe_share = sh;

    auto enc = iris::encode_shamir_match_job(job);
    REQUIRE(enc.has_value());

    auto dec = iris::decode_shamir_match_job(*enc);
    REQUIRE(dec.has_value());
    CHECK(dec->participant_id == job.participant_id);
    CHECK(dec->probe_share.party_id == sh.party_id);
    CHECK(dec->probe_share.x_coord  == sh.x_coord);
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        CHECK(dec->probe_share.code_share[i] == sh.code_share[i]);
        CHECK(dec->probe_share.mask_share[i] == sh.mask_share[i]);
    }
}

TEST_CASE("SMPC2Codec: ShamirShareSyncJob encode/decode round-trip") {
    iris::ShamirShareSyncJob job{};
    job.subject_id     = "test-subject-xyz";
    job.participant_id = 2;
    job.share.party_id = 2;
    job.share.x_coord  = 0xABCDEF0123456789ULL;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        job.share.code_share[i] = static_cast<uint64_t>(i * 17);
        job.share.mask_share[i] = static_cast<uint64_t>(i * 31 + 1);
    }

    auto enc = iris::encode_shamir_share_sync_job(job);
    REQUIRE(enc.has_value());

    auto dec = iris::decode_shamir_share_sync_job(*enc);
    REQUIRE(dec.has_value());
    CHECK(dec->subject_id     == job.subject_id);
    CHECK(dec->participant_id == job.participant_id);
    CHECK(dec->share.x_coord  == job.share.x_coord);
}

TEST_CASE("SMPC2Codec: ShamirMatchResponse encode/decode round-trip") {
    iris::ShamirMatchResponse resp{};
    resp.participant_id = 4;

    iris::ShamirMatchRow row{};
    row.subject_id        = "alice";
    row.xor_share.party_id = 4;
    row.xor_share.x_coord  = 0x1122334455667788ULL;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        row.xor_share.code_share[i] = static_cast<uint64_t>(i + 100);
        row.xor_share.mask_share[i] = static_cast<uint64_t>(i + 200);
    }
    resp.rows.push_back(row);
    resp.rows.push_back(row);
    resp.rows.back().subject_id = "bob";

    auto enc = iris::encode_shamir_match_response(resp);
    REQUIRE(enc.has_value());

    auto dec = iris::decode_shamir_match_response(*enc);
    REQUIRE(dec.has_value());
    CHECK(dec->participant_id == resp.participant_id);
    REQUIRE(dec->rows.size() == 2u);
    CHECK(dec->rows[0].subject_id == "alice");
    CHECK(dec->rows[1].subject_id == "bob");
    CHECK(dec->rows[0].xor_share.x_coord == row.xor_share.x_coord);
}

TEST_CASE("SMPC2Codec: empty response encode/decode") {
    iris::ShamirMatchResponse resp{};
    resp.participant_id = 1;

    auto enc = iris::encode_shamir_match_response(resp);
    REQUIRE(enc.has_value());

    auto dec = iris::decode_shamir_match_response(*enc);
    REQUIRE(dec.has_value());
    CHECK(dec->rows.empty());
}

// ---------------------------------------------------------------------------
// SMPC2Manager simulated mode tests
// ---------------------------------------------------------------------------

TEST_CASE("SMPC2Manager: init simulated mode (n=5)") {
    SMPC2Manager mgr;
    REQUIRE(mgr.init("simulated", "", 5));
    CHECK(mgr.is_active());
    CHECK_FALSE(mgr.is_distributed());
    CHECK(mgr.total_parties() == 5);
    CHECK(mgr.threshold()     == 3);
    CHECK(mgr.size()          == 0u);
}

TEST_CASE("SMPC2Manager: init simulated mode (n=3)") {
    SMPC2Manager mgr;
    REQUIRE(mgr.init("simulated", "", 3));
    CHECK(mgr.total_parties() == 3);
    CHECK(mgr.threshold()     == 2);
}

TEST_CASE("SMPC2Manager: init simulated mode (n=7)") {
    SMPC2Manager mgr;
    REQUIRE(mgr.init("simulated", "", 7));
    CHECK(mgr.total_parties() == 7);
    CHECK(mgr.threshold()     == 4);
}

TEST_CASE("SMPC2Manager: enroll and verify — exact match (HD=0)") {
    SMPC2Manager mgr;
    REQUIRE(mgr.init("simulated", "", 5));

    auto tmpl = make_template(0xAAAAAAAAAAAAAAAAULL);
    auto enroll_r = mgr.enroll("s1", tmpl);
    REQUIRE(enroll_r.has_value());
    CHECK(mgr.size() == 1u);

    auto verify_r = mgr.verify(tmpl);
    REQUIRE(verify_r.has_value());
    REQUIRE_FALSE(verify_r->empty());
    CHECK((*verify_r)[0].subject_id == "s1");
    CHECK((*verify_r)[0].distance   == doctest::Approx(0.0).epsilon(1e-9));
    CHECK((*verify_r)[0].is_match   == true);
}

TEST_CASE("SMPC2Manager: enroll and verify — non-match (HD>0.35)") {
    SMPC2Manager mgr;
    REQUIRE(mgr.init("simulated", "", 5));

    REQUIRE(mgr.enroll("s1", make_template(0x0000000000000000ULL)).has_value());

    auto verify_r = mgr.verify(make_template(0xFFFFFFFFFFFFFFFFULL));
    REQUIRE(verify_r.has_value());
    REQUIRE_FALSE(verify_r->empty());
    CHECK((*verify_r)[0].distance > 0.35);
    CHECK_FALSE((*verify_r)[0].is_match);
}

TEST_CASE("SMPC2Manager: enroll N subjects — each self-matches best") {
    SMPC2Manager mgr;
    REQUIRE(mgr.init("simulated", "", 5));

    constexpr int N = 10;
    for (int i = 0; i < N; ++i) {
        auto r = mgr.enroll("s" + std::to_string(i),
                             make_template(static_cast<uint64_t>(i * 1000)));
        REQUIRE(r.has_value());
    }
    CHECK(mgr.size() == static_cast<size_t>(N));

    for (int i = 0; i < N; ++i) {
        auto verify_r = mgr.verify(make_template(static_cast<uint64_t>(i * 1000)));
        REQUIRE(verify_r.has_value());
        REQUIRE_FALSE(verify_r->empty());
        CHECK((*verify_r)[0].subject_id == "s" + std::to_string(i));
        CHECK((*verify_r)[0].distance == doctest::Approx(0.0).epsilon(1e-9));
    }
}

TEST_CASE("SMPC2Manager: distributed mode fails without NATS URL") {
    SMPC2Manager mgr;
    CHECK_FALSE(mgr.init("distributed", ""));
    CHECK_FALSE(mgr.is_active());
}

TEST_CASE("SMPC2Manager: verify on empty gallery returns empty results") {
    SMPC2Manager mgr;
    REQUIRE(mgr.init("simulated", "", 5));

    auto verify_r = mgr.verify(make_template(0x1234567890ABCDEFULL));
    REQUIRE(verify_r.has_value());
    CHECK(verify_r->empty());
}
