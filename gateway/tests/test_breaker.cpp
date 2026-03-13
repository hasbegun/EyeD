#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
#include "breaker.h"
#include <thread>
#include <chrono>

using namespace eyed;
using namespace std::chrono_literals;

TEST_CASE("Breaker: initial state is Closed") {
    Breaker cb(30s, 10s);
    CHECK(cb.state() == State::Closed);
    CHECK(cb.state_string() == "closed");
}

TEST_CASE("Breaker: allow() returns true when Closed") {
    Breaker cb(30s, 10s);
    CHECK(cb.allow() == true);
    CHECK(cb.state() == State::Closed);
}

TEST_CASE("Breaker: trips to Open after timeout with no results") {
    Breaker cb(100ms, 50ms);

    // Send a frame
    CHECK(cb.allow() == true);
    CHECK(cb.state() == State::Closed);

    // Wait for timeout
    std::this_thread::sleep_for(150ms);

    // Should now be Open
    CHECK(cb.state() == State::Open);
    CHECK(cb.state_string() == "open");
}

TEST_CASE("Breaker: Open rejects frames") {
    Breaker cb(100ms, 50ms);

    // Send a frame and wait for trip
    cb.allow();
    std::this_thread::sleep_for(150ms);

    CHECK(cb.state() == State::Open);
    CHECK(cb.allow() == false);
    CHECK(cb.allow() == false);
}

TEST_CASE("Breaker: Open transitions to HalfOpen after probe interval") {
    Breaker cb(100ms, 50ms);

    // Trip the breaker
    cb.allow();
    std::this_thread::sleep_for(150ms);
    CHECK(cb.state() == State::Open);

    // Wait for probe interval
    std::this_thread::sleep_for(60ms);

    // Should now be HalfOpen
    CHECK(cb.state() == State::HalfOpen);
    CHECK(cb.state_string() == "half-open");
}

TEST_CASE("Breaker: HalfOpen allows one frame then goes back to Open") {
    Breaker cb(100ms, 50ms);

    // Trip the breaker (send frame, wait for timeout)
    cb.allow();
    std::this_thread::sleep_for(150ms);
    CHECK(cb.state() == State::Open);

    // Wait for probe interval (50ms from when it opened, which was ~150ms ago)
    // So we need to wait at least 50ms more from the open transition
    std::this_thread::sleep_for(60ms);
    CHECK(cb.state() == State::HalfOpen);

    // First allow() should succeed and transition to Open
    CHECK(cb.allow() == true);
    CHECK(cb.state() == State::Open);

    // Subsequent calls should fail
    CHECK(cb.allow() == false);
}

TEST_CASE("Breaker: record_result() always resets to Closed") {
    Breaker cb(100ms, 50ms);

    // Trip the breaker
    cb.allow();
    std::this_thread::sleep_for(150ms);
    CHECK(cb.state() == State::Open);

    // Record a result
    cb.record_result();
    CHECK(cb.state() == State::Closed);
    CHECK(cb.allow() == true);
}

TEST_CASE("Breaker: record_result() from HalfOpen goes to Closed") {
    Breaker cb(100ms, 50ms);

    // Trip the breaker
    cb.allow();
    std::this_thread::sleep_for(150ms);
    CHECK(cb.state() == State::Open);

    // Wait for probe interval to reach HalfOpen
    std::this_thread::sleep_for(60ms);
    CHECK(cb.state() == State::HalfOpen);

    // Record result
    cb.record_result();
    CHECK(cb.state() == State::Closed);
}

TEST_CASE("Breaker: does not trip if results keep coming") {
    Breaker cb(100ms, 50ms);

    for (int i = 0; i < 5; i++) {
        cb.allow();
        std::this_thread::sleep_for(20ms);
        cb.record_result();
    }

    CHECK(cb.state() == State::Closed);
}

TEST_CASE("Breaker: multiple rapid allow() calls while Open all return false") {
    Breaker cb(100ms, 50ms);

    // Trip
    cb.allow();
    std::this_thread::sleep_for(150ms);

    // All should fail
    for (int i = 0; i < 10; i++) {
        CHECK(cb.allow() == false);
    }
}

TEST_CASE("Breaker: thread safety - concurrent allow and record_result") {
    Breaker cb(200ms, 100ms);

    std::atomic<int> allowed{0};
    std::atomic<int> rejected{0};

    auto allow_thread = [&]() {
        for (int i = 0; i < 100; i++) {
            if (cb.allow()) {
                allowed++;
            } else {
                rejected++;
            }
            std::this_thread::sleep_for(5ms);
        }
    };

    auto result_thread = [&]() {
        for (int i = 0; i < 50; i++) {
            std::this_thread::sleep_for(10ms);
            cb.record_result();
        }
    };

    std::thread t1(allow_thread);
    std::thread t2(result_thread);

    t1.join();
    t2.join();

    // Should have some allowed and some rejected
    CHECK(allowed.load() > 0);
    CHECK(rejected.load() >= 0);
    CHECK(allowed.load() + rejected.load() == 100);
}

TEST_CASE("Breaker: state_string() returns correct values") {
    CHECK(state_string(State::Closed) == "closed");
    CHECK(state_string(State::Open) == "open");
    CHECK(state_string(State::HalfOpen) == "half-open");
}
