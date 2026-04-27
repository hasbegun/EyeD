// Migration tests — verify plaintext→SMPC re-enrollment and rollback behavior.

#include <doctest/doctest.h>

#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>
#include <iris/crypto/smpc_gallery.hpp>

#include "smpc.h"
#include "gallery.h"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static iris::PackedIrisCode make_code(uint64_t seed) {
    iris::PackedIrisCode code;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        code.code_bits[i] = seed ^ (i * 0x9E3779B97F4A7C15ULL);
        code.mask_bits[i] = ~0ULL;
    }
    return code;
}

static iris::IrisTemplate make_template(uint64_t seed) {
    iris::IrisTemplate tmpl;
    tmpl.iris_codes.push_back(make_code(seed));
    tmpl.mask_codes.push_back(make_code(seed + 1000));
    tmpl.iris_code_version = "v2.0";
    return tmpl;
}

// ===========================================================================
// migrate_templates — simulated mode
// ===========================================================================

TEST_CASE("migrate_templates: bulk enroll into simulated SMPC gallery") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    std::vector<std::pair<std::string, iris::IrisTemplate>> pairs;
    for (int i = 0; i < 50; ++i) {
        pairs.emplace_back("tmpl-" + std::to_string(i),
                           make_template(static_cast<uint64_t>(i)));
    }

    auto stats = smpc.migrate_templates(pairs);
    CHECK(stats.total == 50);
    CHECK(stats.succeeded == 50);
    CHECK(stats.failed == 0);
    CHECK(stats.elapsed_ms >= 0.0);

    // Gallery should contain all 50 templates
    auto* gallery = smpc.gallery();
    REQUIRE(gallery != nullptr);
    CHECK(gallery->size() == 50);
}

TEST_CASE("migrate_templates: empty list is a no-op") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    std::vector<std::pair<std::string, iris::IrisTemplate>> empty;
    auto stats = smpc.migrate_templates(empty);
    CHECK(stats.total == 0);
    CHECK(stats.succeeded == 0);
    CHECK(stats.failed == 0);
}

TEST_CASE("migrate_templates: migrated templates are matchable") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    auto tmpl = make_template(42);
    std::vector<std::pair<std::string, iris::IrisTemplate>> pairs;
    pairs.emplace_back("subject-42", tmpl);

    auto stats = smpc.migrate_templates(pairs);
    REQUIRE(stats.succeeded == 1);

    // Should be able to match the migrated template
    auto results = smpc.gallery()->match_probe(tmpl);
    REQUIRE(results.has_value());
    REQUIRE(results->size() == 1);
    CHECK((*results)[0].distance < 0.01);
}

// ===========================================================================
// add_metadata_only — no double SMPC enrollment
// ===========================================================================

TEST_CASE("add_metadata_only: adds to gallery without SMPC enrollment") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    Gallery gallery(0.39, 0.32);
    gallery.enable_smpc(smpc.gallery());

    // Migrate 5 templates into SMPC directly
    std::vector<std::pair<std::string, iris::IrisTemplate>> pairs;
    for (int i = 0; i < 5; ++i) {
        pairs.emplace_back("tmpl-" + std::to_string(i),
                           make_template(static_cast<uint64_t>(i)));
    }
    auto stats = smpc.migrate_templates(pairs);
    REQUIRE(stats.succeeded == 5);

    // add_metadata_only should NOT re-enroll into SMPC gallery
    for (int i = 0; i < 5; ++i) {
        GalleryEntry e;
        e.template_id = "tmpl-" + std::to_string(i);
        e.identity_id = "identity-" + std::to_string(i);
        e.identity_name = "Name " + std::to_string(i);
        e.eye_side = "left";
        e.tmpl = make_template(static_cast<uint64_t>(i));
        gallery.add_metadata_only(std::move(e));
    }

    // Gallery metadata should have 5 entries
    CHECK(gallery.size() == 5);

    // SMPC gallery should also have exactly 5 (not 10 — no double enrollment)
    CHECK(smpc.gallery()->size() == 5);
}

TEST_CASE("add vs add_metadata_only: add triggers SMPC enrollment") {
    SMPCManager smpc;
    REQUIRE(smpc.initialize("simulated"));

    Gallery gallery(0.39, 0.32);
    gallery.enable_smpc(smpc.gallery());

    // Regular add should enroll into SMPC
    GalleryEntry e;
    e.template_id = "tmpl-1";
    e.identity_id = "id-1";
    e.tmpl = make_template(1);
    gallery.add(std::move(e));

    CHECK(gallery.size() == 1);
    CHECK(smpc.gallery()->size() == 1);

    // add_metadata_only should NOT enroll
    GalleryEntry e2;
    e2.template_id = "tmpl-2";
    e2.identity_id = "id-2";
    e2.tmpl = make_template(2);
    gallery.add_metadata_only(std::move(e2));

    CHECK(gallery.size() == 2);
    CHECK(smpc.gallery()->size() == 1);  // Still 1 — metadata-only didn't enroll
}

// ===========================================================================
// Rollback / fallback behavior
// ===========================================================================

TEST_CASE("SMPCManager: uninitialized manager is not active") {
    SMPCManager smpc;
    CHECK_FALSE(smpc.is_active());
    CHECK_FALSE(smpc.is_distributed());
}

TEST_CASE("Gallery: works without SMPC (plaintext fallback)") {
    Gallery gallery(0.39, 0.32);
    // No enable_smpc called — plaintext mode

    GalleryEntry e;
    e.template_id = "tmpl-1";
    e.identity_id = "id-1";
    e.identity_name = "Alice";
    e.eye_side = "left";
    e.tmpl = make_template(42);
    gallery.add(std::move(e));

    CHECK(gallery.size() == 1);
    CHECK_FALSE(gallery.smpc_active());

    // Match should work in plaintext mode
    auto match = gallery.match(make_template(42));
    REQUIRE(match.has_value());
    CHECK(match->is_match);
    CHECK(match->matched_identity_id == "id-1");
}
