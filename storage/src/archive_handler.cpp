#include "archive_handler.h"

#include <array>
#include <chrono>
#include <cstring>
#include <ctime>
#include <stdexcept>

#include <nlohmann/json.hpp>

namespace eyed {

// ---------------------------------------------------------------------------
// base64_decode
// ---------------------------------------------------------------------------

static const std::array<int8_t, 256> kBase64Table = [] {
    std::array<int8_t, 256> t;
    t.fill(-1);
    for (int i = 0; i < 26; ++i) { t['A' + i] = i;      t['a' + i] = 26 + i; }
    for (int i = 0; i < 10; ++i) { t['0' + i] = 52 + i; }
    t['+'] = 62; t['/'] = 63;
    return t;
}();

std::vector<uint8_t> base64_decode(const std::string& encoded) {
    if (encoded.empty()) return {};

    std::vector<uint8_t> out;
    out.reserve((encoded.size() * 3) / 4);

    uint32_t buf  = 0;
    int      bits = 0;

    for (unsigned char c : encoded) {
        if (c == '\r' || c == '\n' || c == ' ') continue;    // skip MIME whitespace
        if (c == '=') break;                                 // padding: end of data

        int8_t val = kBase64Table[c];
        if (val < 0) return {};  // invalid character → reject whole input

        buf   = (buf << 6) | static_cast<uint32_t>(val);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back(static_cast<uint8_t>((buf >> bits) & 0xFF));
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// sanitize_path
// ---------------------------------------------------------------------------

std::string sanitize_path(const std::string& s) {
    if (s.empty()) return "_";

    std::string out;
    out.reserve(s.size());

    bool prev_unsafe = false;
    for (unsigned char c : s) {
        bool unsafe = (c == '/' || c == '\\' || c == ':' || c < 32 || c == 127);
        if (unsafe) {
            if (!prev_unsafe) out += '_';
            prev_unsafe = true;
        } else {
            out += static_cast<char>(c);
            prev_unsafe = false;
        }
    }

    if (out.empty())   return "_";
    if (out == ".")    return "_";
    if (out == "..")   return "_";

    // Reject any remaining path traversal sequences (e.g. "foo..bar" is fine,
    // but "foo/../bar" would have been collapsed already; catch "..something").
    if (out.size() >= 2 && out[0] == '.' && out[1] == '.') return "_";

    return out;
}

// ---------------------------------------------------------------------------
// extract_date
// ---------------------------------------------------------------------------

std::string extract_date(const std::string& iso8601) {
    // Fast path: validate YYYY-MM-DD prefix
    if (iso8601.size() >= 10) {
        const char* s = iso8601.c_str();
        auto is_digit = [](char c) { return c >= '0' && c <= '9'; };

        if (is_digit(s[0]) && is_digit(s[1]) && is_digit(s[2]) && is_digit(s[3]) &&
            s[4] == '-' &&
            is_digit(s[5]) && is_digit(s[6]) &&
            s[7] == '-' &&
            is_digit(s[8]) && is_digit(s[9])) {

            int year  = std::stoi(iso8601.substr(0, 4));
            int month = std::stoi(iso8601.substr(5, 2));
            int day   = std::stoi(iso8601.substr(8, 2));

            if (year  >= 1970 && year  <= 9999 &&
                month >= 1    && month <= 12   &&
                day   >= 1    && day   <= 31) {
                return iso8601.substr(0, 10);
            }
        }
    }

    // Fallback: today's UTC date
    auto now = std::chrono::system_clock::now();
    auto t   = std::chrono::system_clock::to_time_t(now);
    std::tm tm{};
    gmtime_r(&t, &tm);
    char buf[11];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d", &tm);
    return std::string(buf);
}

// ---------------------------------------------------------------------------
// ArchiveHandler
// ---------------------------------------------------------------------------

ArchiveHandler::ArchiveHandler(ObjectStore* store) : store_(store) {}

void ArchiveHandler::handle_message(const uint8_t* data, size_t len) {
    ParsedMessage msg;
    if (!parse(data, len, msg)) {
        errors_.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    if (!write(msg)) {
        errors_.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    archived_.fetch_add(1, std::memory_order_relaxed);
}

bool ArchiveHandler::parse(const uint8_t* data, size_t len, ParsedMessage& out) {
    nlohmann::json j;
    try {
        j = nlohmann::json::parse(data, data + len);
    } catch (...) {
        return false;
    }

    if (!j.is_object()) return false;

    out.frame_id  = j.value("frame_id",  "unknown");
    out.device_id = j.value("device_id", "unknown");
    out.timestamp = j.value("timestamp", "");

    // Decode raw JPEG if present and non-null
    if (j.contains("raw_jpeg_b64") && j["raw_jpeg_b64"].is_string()) {
        const std::string& b64 = j["raw_jpeg_b64"].get<std::string>();
        if (!b64.empty()) {
            out.jpeg     = base64_decode(b64);
            out.has_jpeg = !out.jpeg.empty();
            if (!out.has_jpeg) {
                return false;  // corrupt base64
            }
        }
    }

    // Metadata JSON: full message minus raw_jpeg_b64
    nlohmann::json meta = j;
    meta.erase("raw_jpeg_b64");
    out.metadata_json = meta.dump();

    return true;
}

bool ArchiveHandler::write(const ParsedMessage& msg) {
    const std::string date   = extract_date(msg.timestamp);
    const std::string device = sanitize_path(msg.device_id);
    const std::string frame  = sanitize_path(msg.frame_id);
    const std::string base   = "raw/" + date + "/" + device + "/" + frame;

    if (msg.has_jpeg) {
        auto ec = store_->put(base + ".jpg", msg.jpeg);
        if (ec) return false;
    }

    const auto& ms = msg.metadata_json;
    std::vector<uint8_t> meta_bytes(ms.begin(), ms.end());
    auto ec = store_->put(base + ".meta.json", meta_bytes);
    return !ec;
}

}  // namespace eyed
