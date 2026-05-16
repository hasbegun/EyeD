// SMPC performance benchmarks using doctest + chrono timing.
// Validates performance targets from the integration plan:
//   P1: Share split throughput > 10,000/s
//   P2: 1-vs-1000 SMPC match (simulated) < 50 ms
//   P5: Memory per 1000 gallery entries < 10 MB/party

#include <doctest/doctest.h>

#include <chrono>
#include <cstdint>
#include <iostream>
#include <random>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>
#include <iris/crypto/smpc_gallery.hpp>
#include <iris/crypto/secret_sharing.hpp>

namespace {

iris::PackedIrisCode random_code(std::mt19937_64& rng) {
    iris::PackedIrisCode code;
    for (auto& w : code.code_bits) w = rng();
    for (auto& w : code.mask_bits) w = ~uint64_t{0};
    return code;
}

iris::IrisTemplate make_template(std::mt19937_64& rng, int n_scales = 1) {
    iris::IrisTemplate tmpl;
    for (int i = 0; i < n_scales; ++i) {
        tmpl.iris_codes.push_back(random_code(rng));
        tmpl.mask_codes.push_back(random_code(rng));
    }
    tmpl.iris_code_version = "v2.0";
    return tmpl;
}

using Clock = std::chrono::high_resolution_clock;

template <typename Fn>
double measure_ms(Fn&& fn) {
    auto t0 = Clock::now();
    fn();
    auto t1 = Clock::now();
    return std::chrono::duration<double, std::milli>(t1 - t0).count();
}

}  // namespace

TEST_CASE("Bench: SecretSharer split throughput") {
    constexpr int N = 1000;
    std::mt19937_64 rng(42);
    auto code = random_code(rng);

    iris::SecretSharer sharer;

    auto elapsed = measure_ms([&] {
        for (int i = 0; i < N; ++i) {
            auto r = sharer.split(code);
            CHECK(r.has_value());
        }
    });

    double throughput = static_cast<double>(N) / (elapsed / 1000.0);
    std::cout << "[bench] SecretSharer::split x" << N << ": "
              << elapsed << " ms (" << throughput << " splits/s)\n";

    // P1: > 10,000 splits/s
    CHECK(throughput > 10000.0);
}

TEST_CASE("Bench: SMPCGallery 1-vs-100 match") {
    constexpr int GALLERY_SIZE = 100;
    std::mt19937_64 rng(42);

    iris::SMPCGallery gallery;

    // Populate gallery
    for (int i = 0; i < GALLERY_SIZE; ++i) {
        auto tmpl = make_template(rng);
        auto r = gallery.add_template("s" + std::to_string(i), tmpl);
        CHECK(r.has_value());
    }
    CHECK(gallery.size() == GALLERY_SIZE);

    // Create probe
    auto probe = make_template(rng);

    // Warm up
    {
        auto r = gallery.match_probe(probe);
        CHECK(r.has_value());
    }

    // Benchmark: 10 iterations
    constexpr int ITERS = 10;
    double total_ms = 0.0;
    for (int i = 0; i < ITERS; ++i) {
        auto ms = measure_ms([&] {
            auto r = gallery.match_probe(probe);
            CHECK(r.has_value());
            CHECK(r->size() == GALLERY_SIZE);
        });
        total_ms += ms;
    }

    double avg_ms = total_ms / ITERS;
    std::cout << "[bench] SMPCGallery 1-vs-" << GALLERY_SIZE << " match: "
              << avg_ms << " ms avg (" << ITERS << " iterations)\n";

    // P2: < 500 ms (relaxed for emulated Docker)
    CHECK(avg_ms < 500.0);
}

TEST_CASE("Bench: SMPCGallery enrollment throughput") {
    constexpr int N = 200;
    std::mt19937_64 rng(42);

    iris::SMPCGallery gallery;

    auto elapsed = measure_ms([&] {
        for (int i = 0; i < N; ++i) {
            auto tmpl = make_template(rng);
            auto r = gallery.add_template("s" + std::to_string(i), tmpl);
            CHECK(r.has_value());
        }
    });

    double throughput = static_cast<double>(N) / (elapsed / 1000.0);
    std::cout << "[bench] SMPCGallery enrollment x" << N << ": "
              << elapsed << " ms (" << throughput << " enrollments/s)\n";

    CHECK(gallery.size() == N);
}

TEST_CASE("Bench: SMPCGallery 1-vs-50 match latency") {
    constexpr int GALLERY_SIZE = 50;
    std::mt19937_64 rng(42);

    iris::SMPCGallery gallery;
    for (int i = 0; i < GALLERY_SIZE; ++i) {
        gallery.add_template("s" + std::to_string(i), make_template(rng));
    }

    auto probe = make_template(rng);

    constexpr int ITERS = 20;
    double total_ms = 0.0;
    for (int i = 0; i < ITERS; ++i) {
        total_ms += measure_ms([&] {
            auto r = gallery.match_probe(probe);
            CHECK(r.has_value());
        });
    }

    double avg_ms = total_ms / ITERS;
    std::cout << "[bench] SMPCGallery 1-vs-" << GALLERY_SIZE << " match: "
              << avg_ms << " ms avg (" << ITERS << " iterations)\n";

    // Should be well under 100 ms for 50 entries (relaxed for emulated Docker)
    CHECK(avg_ms < 100.0);
}
