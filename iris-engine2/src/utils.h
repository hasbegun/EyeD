#pragma once

#include <cstdint>
#include <cstdio>
#include <random>
#include <string>

namespace eyed {

inline std::string generate_uuid() {
    static thread_local std::mt19937_64 gen{std::random_device{}()};
    std::uniform_int_distribution<uint64_t> dis;
    uint64_t a = dis(gen);
    uint64_t b = dis(gen);
    a = (a & 0xFFFFFFFFFFFF0FFFULL) | 0x0000000000004000ULL;
    b = (b & 0x3FFFFFFFFFFFFFFFULL) | 0x8000000000000000ULL;
    char buf[37];
    std::snprintf(buf, sizeof(buf), "%08x-%04x-%04x-%04x-%012llx",
                  static_cast<uint32_t>(a >> 32),
                  static_cast<uint16_t>((a >> 16) & 0xFFFF),
                  static_cast<uint16_t>(a & 0xFFFF),
                  static_cast<uint16_t>((b >> 48) & 0xFFFF),
                  static_cast<unsigned long long>(b & 0x0000FFFFFFFFFFFFULL));
    return buf;
}

} // namespace eyed
