#include "breaker.h"

namespace eyed {

Breaker::Breaker(Duration timeout, Duration probe_interval)
    : state_(State::Closed),
      timeout_(timeout),
      probe_interval_(probe_interval),
      last_sent_(TimePoint{}),
      last_result_(TimePoint{}),
      last_probe_(TimePoint{}) {}

bool Breaker::allow() {
    std::lock_guard<std::mutex> lock(mu_);

    auto now = Clock::now();
    evaluate(now);

    switch (state_) {
        case State::Closed:
            last_sent_ = now;
            return true;

        case State::HalfOpen:
            last_sent_ = now;
            last_probe_ = now;
            state_ = State::Open;  // Back to open until we get a result
            return true;

        case State::Open:
            return false;
    }

    return false;
}

void Breaker::record_result() {
    std::lock_guard<std::mutex> lock(mu_);
    last_result_ = Clock::now();
    state_ = State::Closed;
}

State Breaker::state() {
    std::lock_guard<std::mutex> lock(mu_);
    evaluate(Clock::now());
    return state_;
}

std::string Breaker::state_string() const {
    std::lock_guard<std::mutex> lock(mu_);
    return eyed::state_string(state_);
}

void Breaker::evaluate(TimePoint now) {
    switch (state_) {
        case State::Closed:
            // Trip if we've sent frames but got no results within timeout
            if (last_sent_.time_since_epoch().count() != 0 &&
                last_sent_ > last_result_ &&
                (now - last_sent_) > timeout_) {
                state_ = State::Open;
                last_probe_ = now;  // Start probe interval from when we opened
            }
            break;

        case State::Open:
            // Transition to half-open if enough time has passed since last probe
            if ((now - last_probe_) > probe_interval_) {
                state_ = State::HalfOpen;
            }
            break;

        case State::HalfOpen:
            // No automatic transition from HalfOpen
            break;
    }
}

} // namespace eyed
