// Tests for SMPCShardedCoordinator + SMPCShardedParticipantService.
// Separate TU — uses smpc_sharded_gallery.hpp (no smpc_gallery.hpp conflict).

#include <doctest/doctest.h>
#include <cstdint>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>
#include <iris/crypto/smpc_sharded_gallery.hpp>
#include <iris/crypto/smpc_coordinator_service.hpp>
#include <iris/crypto/smpc_participant_service.hpp>
#include <iris/crypto/smpc_queue.hpp>

static iris::PackedIrisCode make_test_code(uint64_t seed) {
    iris::PackedIrisCode code;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        code.code_bits[i] = seed ^ (i * 0x9E3779B97F4A7C15ULL);
        code.mask_bits[i] = ~0ULL;
    }
    return code;
}

static iris::IrisTemplate make_test_template(uint64_t seed, int n_scales = 1) {
    iris::IrisTemplate tmpl;
    for (int i = 0; i < n_scales; ++i) {
        tmpl.iris_codes.push_back(make_test_code(seed + static_cast<uint64_t>(i)));
        tmpl.mask_codes.push_back(make_test_code(seed + 1000 + static_cast<uint64_t>(i)));
    }
    tmpl.iris_code_version = "v2.0";
    return tmpl;
}

TEST_CASE("ShardedParticipantService owns_subject") {
    // 2 shards: shard 0 and shard 1
    iris::SMPCShardedParticipantService shard0(1, 0, 2);
    iris::SMPCShardedParticipantService shard1(1, 1, 2);

    // Each subject should be owned by exactly one shard
    int owned_by_0 = 0, owned_by_1 = 0;
    for (int i = 0; i < 100; ++i) {
        std::string sid = "subject-" + std::to_string(i);
        bool o0 = shard0.owns_subject(sid);
        bool o1 = shard1.owns_subject(sid);
        CHECK((o0 || o1));       // at least one owns it
        CHECK(!(o0 && o1));      // not both
        if (o0) ++owned_by_0;
        if (o1) ++owned_by_1;
    }

    // Rough balance — each shard should own some subjects
    CHECK(owned_by_0 > 10);
    CHECK(owned_by_1 > 10);
}

TEST_CASE("ShardedCoordinator enroll and verify via InMemoryBus") {
    auto bus = std::make_shared<iris::InMemorySMPCBus>();

    // 3 participants, each unsharded (standard) for the bus
    auto p1 = std::make_shared<iris::SMPCParticipantService>(1);
    auto p2 = std::make_shared<iris::SMPCParticipantService>(2);
    auto p3 = std::make_shared<iris::SMPCParticipantService>(3);
    REQUIRE(bus->register_participant(1, p1).has_value());
    REQUIRE(bus->register_participant(2, p2).has_value());
    REQUIRE(bus->register_participant(3, p3).has_value());

    // Sharded coordinator with 1 shard per participant
    iris::SMPCShardedCoordinator coordinator(3, 1, bus);

    auto tmpl = make_test_template(42);
    auto enroll_r = coordinator.enroll("subject-1", tmpl);
    REQUIRE(enroll_r.has_value());
    CHECK(coordinator.total_gallery_size() == 1);

    // Verify with same template — should find match
    auto verify_r = coordinator.verify(tmpl);
    REQUIRE(verify_r.has_value());
    REQUIRE(verify_r->size() == 1);
    CHECK((*verify_r)[0].subject_id == "subject-1");
    CHECK((*verify_r)[0].distance < 0.01);
}

TEST_CASE("ShardedCoordinator multiple enrollments") {
    auto bus = std::make_shared<iris::InMemorySMPCBus>();
    auto p1 = std::make_shared<iris::SMPCParticipantService>(1);
    auto p2 = std::make_shared<iris::SMPCParticipantService>(2);
    auto p3 = std::make_shared<iris::SMPCParticipantService>(3);
    REQUIRE(bus->register_participant(1, p1).has_value());
    REQUIRE(bus->register_participant(2, p2).has_value());
    REQUIRE(bus->register_participant(3, p3).has_value());

    iris::SMPCShardedCoordinator coordinator(3, 1, bus);

    REQUIRE(coordinator.enroll("s1", make_test_template(1)).has_value());
    REQUIRE(coordinator.enroll("s2", make_test_template(2)).has_value());
    REQUIRE(coordinator.enroll("s3", make_test_template(3)).has_value());
    CHECK(coordinator.total_gallery_size() == 3);

    // Verify with s1's template — best match should be s1
    auto verify_r = coordinator.verify(make_test_template(1));
    REQUIRE(verify_r.has_value());
    REQUIRE(verify_r->size() == 3);
    CHECK((*verify_r)[0].subject_id == "s1");
    CHECK((*verify_r)[0].distance < 0.01);
}

TEST_CASE("ShardedCoordinator different templates produce high HD") {
    auto bus = std::make_shared<iris::InMemorySMPCBus>();
    auto p1 = std::make_shared<iris::SMPCParticipantService>(1);
    auto p2 = std::make_shared<iris::SMPCParticipantService>(2);
    auto p3 = std::make_shared<iris::SMPCParticipantService>(3);
    REQUIRE(bus->register_participant(1, p1).has_value());
    REQUIRE(bus->register_participant(2, p2).has_value());
    REQUIRE(bus->register_participant(3, p3).has_value());

    iris::SMPCShardedCoordinator coordinator(3, 1, bus);

    REQUIRE(coordinator.enroll("subject-a", make_test_template(42)).has_value());

    auto verify_r = coordinator.verify(make_test_template(999));
    REQUIRE(verify_r.has_value());
    REQUIRE(verify_r->size() == 1);
    CHECK((*verify_r)[0].distance > 0.1);
}
