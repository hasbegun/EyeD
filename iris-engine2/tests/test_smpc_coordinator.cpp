// Coordinator + Participant tests using InMemorySMPCBus.
// Separate TU from test_smpc.cpp to avoid the iris::MatchResult
// redefinition conflict between smpc_gallery.hpp and smpc_coordinator_service.hpp.

#include <doctest/doctest.h>
#include <cstring>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>
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

static iris::IrisTemplate make_test_template(uint64_t seed, int n_scales = 2) {
    iris::IrisTemplate tmpl;
    for (int i = 0; i < n_scales; ++i) {
        tmpl.iris_codes.push_back(make_test_code(seed + static_cast<uint64_t>(i)));
        tmpl.mask_codes.push_back(make_test_code(seed + 1000 + static_cast<uint64_t>(i)));
    }
    tmpl.iris_code_version = "v2.0";
    return tmpl;
}

TEST_CASE("Coordinator + Participant via InMemorySMPCBus - enroll and verify") {
    auto bus = std::make_shared<iris::InMemorySMPCBus>();

    auto p1 = std::make_shared<iris::SMPCParticipantService>(1);
    auto p2 = std::make_shared<iris::SMPCParticipantService>(2);
    auto p3 = std::make_shared<iris::SMPCParticipantService>(3);

    REQUIRE(bus->register_participant(1, p1).has_value());
    REQUIRE(bus->register_participant(2, p2).has_value());
    REQUIRE(bus->register_participant(3, p3).has_value());

    iris::SMPCCoordinatorService coordinator(3, bus);

    auto tmpl = make_test_template(42, 1);
    auto enroll_r = coordinator.enroll("subject-1", tmpl);
    REQUIRE(enroll_r.has_value());

    CHECK(p1->size() == 1);
    CHECK(p2->size() == 1);
    CHECK(p3->size() == 1);

    auto verify_r = coordinator.verify(tmpl);
    REQUIRE(verify_r.has_value());
    REQUIRE(verify_r->size() == 1);
    CHECK((*verify_r)[0].subject_id == "subject-1");
    CHECK((*verify_r)[0].distance < 0.01);
}

TEST_CASE("Coordinator + Participant - different templates produce high HD") {
    auto bus = std::make_shared<iris::InMemorySMPCBus>();
    auto p1 = std::make_shared<iris::SMPCParticipantService>(1);
    auto p2 = std::make_shared<iris::SMPCParticipantService>(2);
    auto p3 = std::make_shared<iris::SMPCParticipantService>(3);
    REQUIRE(bus->register_participant(1, p1).has_value());
    REQUIRE(bus->register_participant(2, p2).has_value());
    REQUIRE(bus->register_participant(3, p3).has_value());

    iris::SMPCCoordinatorService coordinator(3, bus);

    auto tmpl_a = make_test_template(42, 1);
    auto tmpl_b = make_test_template(999, 1);

    REQUIRE(coordinator.enroll("subject-a", tmpl_a).has_value());

    auto verify_r = coordinator.verify(tmpl_b);
    REQUIRE(verify_r.has_value());
    REQUIRE(verify_r->size() == 1);
    CHECK((*verify_r)[0].distance > 0.1);
}

TEST_CASE("Coordinator + Participant - multiple enrollments") {
    auto bus = std::make_shared<iris::InMemorySMPCBus>();
    auto p1 = std::make_shared<iris::SMPCParticipantService>(1);
    auto p2 = std::make_shared<iris::SMPCParticipantService>(2);
    auto p3 = std::make_shared<iris::SMPCParticipantService>(3);
    REQUIRE(bus->register_participant(1, p1).has_value());
    REQUIRE(bus->register_participant(2, p2).has_value());
    REQUIRE(bus->register_participant(3, p3).has_value());

    iris::SMPCCoordinatorService coordinator(3, bus);

    REQUIRE(coordinator.enroll("s1", make_test_template(1, 1)).has_value());
    REQUIRE(coordinator.enroll("s2", make_test_template(2, 1)).has_value());
    REQUIRE(coordinator.enroll("s3", make_test_template(3, 1)).has_value());

    CHECK(coordinator.size() == 3);
    CHECK(p1->size() == 3);

    auto verify_r = coordinator.verify(make_test_template(1, 1));
    REQUIRE(verify_r.has_value());
    REQUIRE(verify_r->size() == 3);
    CHECK((*verify_r)[0].subject_id == "s1");
    CHECK((*verify_r)[0].distance < 0.01);
}
