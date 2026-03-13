#pragma once

#include <chrono>
#include <mutex>
#include <string>

namespace eyed {

enum class State {
    Closed,   // Normal: accepting frames
    Open,     // Tripped: rejecting frames
    HalfOpen  // Probing: allowing one frame to test recovery
};

inline std::string state_string(State s) {
    switch (s) {
        case State::Closed:   return "closed";
        case State::Open:     return "open";
        case State::HalfOpen: return "half-open";
        default:              return "unknown";
    }
}

class Breaker {
public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    using Duration = std::chrono::milliseconds;

    Breaker(Duration timeout, Duration probe_interval);

    // Check whether a frame should be accepted.
    // Returns true if the frame should be processed, false if rejected.
    bool allow();

    // Signal that a result was received from iris-engine.
    void record_result();

    // Get the current circuit breaker state.
    State state();

    std::string state_string() const;

private:
    mutable std::mutex mu_;
    State state_;
    Duration timeout_;
    Duration probe_interval_;
    TimePoint last_sent_;
    TimePoint last_result_;
    TimePoint last_probe_;

    // Evaluate and update state based on timing (must be called with lock held).
    void evaluate(TimePoint now);
};

} // namespace eyed
