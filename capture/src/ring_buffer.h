#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <optional>

#include <opencv2/core.hpp>

struct Frame {
    cv::Mat    image;
    uint32_t   frame_id;
    uint64_t   timestamp_us;
};

// Fixed-size, lock-free, single-producer single-consumer ring buffer.
// N must be a power of two.
template <typename T, std::size_t N>
class RingBuffer {
    static_assert((N & (N - 1)) == 0, "N must be a power of two");
    static constexpr std::size_t MASK = N - 1;

    std::array<T, N> slots_{};
    alignas(64) std::atomic<std::size_t> head_{0}; // producer writes here
    alignas(64) std::atomic<std::size_t> tail_{0}; // consumer reads here

public:
    // Producer: returns false if buffer is full (caller should drop the frame).
    bool try_push(T value) {
        const auto h    = head_.load(std::memory_order_relaxed);
        const auto next = (h + 1) & MASK;
        if (next == tail_.load(std::memory_order_acquire))
            return false;
        slots_[h] = std::move(value);
        head_.store(next, std::memory_order_release);
        return true;
    }

    // Consumer: returns std::nullopt if buffer is empty.
    std::optional<T> try_pop() {
        const auto t = tail_.load(std::memory_order_relaxed);
        if (t == head_.load(std::memory_order_acquire))
            return std::nullopt;
        T value = std::move(slots_[t]);
        tail_.store((t + 1) & MASK, std::memory_order_release);
        return value;
    }
};
