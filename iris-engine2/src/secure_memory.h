#pragma once

#include <cstddef>
#include <cstring>
#include <vector>

#ifdef __linux__
#include <sys/mman.h>
#elif defined(__APPLE__)
#include <sys/mman.h>
#endif

namespace secure {

/// Zero-fill a memory region in a way the compiler cannot optimize out.
inline void wipe(void* ptr, size_t len) {
    if (!ptr || len == 0) return;
#if defined(__STDC_LIB_EXT1__)
    memset_s(ptr, len, 0, len);
#else
    explicit_bzero(ptr, len);
#endif
}

/// Zero-fill a vector and release its memory.
template <typename T>
void wipe_vector(std::vector<T>& v) {
    if (!v.empty()) {
        wipe(v.data(), v.size() * sizeof(T));
    }
    v.clear();
    v.shrink_to_fit();
}

/// Lock a memory region to prevent swapping to disk.
/// Returns true on success, false on failure (non-fatal — just a warning).
inline bool lock_memory(const void* ptr, size_t len) {
#if defined(__linux__) || defined(__APPLE__)
    return mlock(ptr, len) == 0;
#else
    (void)ptr; (void)len;
    return false;
#endif
}

/// Unlock a previously locked memory region.
inline void unlock_memory(const void* ptr, size_t len) {
#if defined(__linux__) || defined(__APPLE__)
    munlock(ptr, len);
#else
    (void)ptr; (void)len;
#endif
}

/// Advise the kernel not to include this region in core dumps.
/// Only effective on Linux; no-op on other platforms.
inline void no_coredump(void* ptr, size_t len) {
#ifdef __linux__
    madvise(ptr, len, MADV_DONTDUMP);
#else
    (void)ptr; (void)len;
#endif
}

/// RAII guard that locks memory on construction and wipes+unlocks on destruction.
class LockedBuffer {
  public:
    explicit LockedBuffer(size_t size)
        : data_(size, 0) {
        if (!data_.empty()) {
            lock_memory(data_.data(), data_.size());
            no_coredump(data_.data(), data_.size());
        }
    }

    ~LockedBuffer() {
        if (!data_.empty()) {
            wipe(data_.data(), data_.size());
            unlock_memory(data_.data(), data_.size());
        }
    }

    LockedBuffer(const LockedBuffer&) = delete;
    LockedBuffer& operator=(const LockedBuffer&) = delete;
    LockedBuffer(LockedBuffer&&) = default;
    LockedBuffer& operator=(LockedBuffer&&) = default;

    uint8_t* data() { return data_.data(); }
    const uint8_t* data() const { return data_.data(); }
    size_t size() const { return data_.size(); }

  private:
    std::vector<uint8_t> data_;
};

}  // namespace secure
