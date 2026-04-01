#include "smpc.h"

#include <doctest/doctest.h>
#include <cstring>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>
#include <iris/crypto/smpc_gallery.hpp>

// Helper to create a PackedIrisCode with deterministic bit pattern
static iris::PackedIrisCode make_test_code(uint64_t seed) {
    iris::PackedIrisCode code;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        code.code_bits[i] = seed ^ (i * 0x9E3779B97F4A7C15ULL);
        code.mask_bits[i] = ~0ULL;  // all bits valid
    }
    return code;
}

// Helper to create a test IrisTemplate with N scales
static iris::IrisTemplate make_test_template(uint64_t seed, int n_scales = 2) {
    iris::IrisTemplate tmpl;
    for (int i = 0; i < n_scales; ++i) {
        tmpl.iris_codes.push_back(make_test_code(seed + static_cast<uint64_t>(i)));
        tmpl.mask_codes.push_back(make_test_code(seed + 1000 + static_cast<uint64_t>(i)));
    }
    tmpl.iris_code_version = "v2.0";
    return tmpl;
}

TEST_CASE("SMPCManager not initialized") {
    SMPCManager smpc;
    CHECK_FALSE(smpc.is_active());
    CHECK(smpc.mode().empty());
    CHECK(smpc.gallery() == nullptr);
}

TEST_CASE("SMPCManager initialize simulated mode") {
    SMPCManager smpc;
    bool ok = smpc.initialize("simulated");
    CHECK(ok);
    CHECK(smpc.is_active());
    CHECK(smpc.mode() == "simulated");
    CHECK(smpc.gallery() != nullptr);
}

TEST_CASE("SMPCManager initialize distributed mode without NATS URL fails") {
    SMPCManager smpc;
    bool ok = smpc.initialize("distributed", "");
    CHECK_FALSE(ok);
    CHECK_FALSE(smpc.is_active());
}

TEST_CASE("SMPCManager initialize distributed mode with NATS URL - no server") {
    SMPCManager smpc;
    // Without a running NATS server, distributed mode should fail to connect
    bool ok = smpc.initialize("distributed", "nats://localhost:14222");
    CHECK_FALSE(ok);
    CHECK_FALSE(smpc.is_active());
}

TEST_CASE("SMPCManager is_distributed") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));
    CHECK_FALSE(smpc.is_distributed());
    CHECK(smpc.gallery() != nullptr);
}

TEST_CASE("SMPCManager invalid mode") {
    SMPCManager smpc;
    bool ok = smpc.initialize("invalid_mode");
    CHECK_FALSE(ok);
    CHECK_FALSE(smpc.is_active());
}

TEST_CASE("SMPCManager invalid num_parties") {
    SMPCManager smpc;
    bool ok = smpc.initialize("simulated", "", 2);
    CHECK_FALSE(ok);
    CHECK_FALSE(smpc.is_active());
}

TEST_CASE("SMPCGallery add and match - same template produces HD near 0") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    auto* gallery = smpc.gallery();
    REQUIRE(gallery != nullptr);

    auto tmpl = make_test_template(42, 1);
    auto add_r = gallery->add_template("subject-1", tmpl);
    CHECK(add_r.has_value());

    auto results = gallery->match_probe(tmpl);
    REQUIRE(results.has_value());
    REQUIRE(results->size() == 1);
    CHECK((*results)[0].distance < 0.01);
}

TEST_CASE("SMPCGallery add and match - different templates produce HD > 0") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    auto* gallery = smpc.gallery();
    REQUIRE(gallery != nullptr);

    auto tmpl_a = make_test_template(42, 1);
    auto tmpl_b = make_test_template(999, 1);

    auto add_r = gallery->add_template("subject-1", tmpl_a);
    CHECK(add_r.has_value());

    auto results = gallery->match_probe(tmpl_b);
    REQUIRE(results.has_value());
    REQUIRE(results->size() == 1);
    CHECK((*results)[0].distance > 0.1);
}

TEST_CASE("SMPCGallery multiple entries") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    auto* gallery = smpc.gallery();
    REQUIRE(gallery != nullptr);

    auto tmpl_1 = make_test_template(1, 1);
    auto tmpl_2 = make_test_template(2, 1);
    auto tmpl_3 = make_test_template(3, 1);

    gallery->add_template("s1", tmpl_1);
    gallery->add_template("s2", tmpl_2);
    gallery->add_template("s3", tmpl_3);

    CHECK(gallery->size() == 3);

    // Match against tmpl_1 — best match should be index 0
    auto results = gallery->match_probe(tmpl_1);
    REQUIRE(results.has_value());
    REQUIRE(results->size() == 3);

    double best_dist = 1.0;
    size_t best_idx = 0;
    for (size_t i = 0; i < results->size(); ++i) {
        if ((*results)[i].distance < best_dist) {
            best_dist = (*results)[i].distance;
            best_idx = i;
        }
    }
    CHECK(best_idx == 0);
    CHECK(best_dist < 0.01);
}

TEST_CASE("SMPCGallery remove template") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    auto* gallery = smpc.gallery();
    REQUIRE(gallery != nullptr);

    gallery->add_template("s1", make_test_template(1, 1));
    gallery->add_template("s2", make_test_template(2, 1));
    CHECK(gallery->size() == 2);

    gallery->remove_template("s1");
    CHECK(gallery->size() == 1);

    gallery->remove_template("s2");
    CHECK(gallery->size() == 0);
}

TEST_CASE("SMPCGallery empty gallery match returns empty") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    auto* gallery = smpc.gallery();
    REQUIRE(gallery != nullptr);

    auto results = gallery->match_probe(make_test_template(42, 1));
    REQUIRE(results.has_value());
    CHECK(results->empty());
}
