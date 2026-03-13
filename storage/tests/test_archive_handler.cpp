#include "archive_handler.h"
#include "local_store.h"

#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <doctest/doctest.h>

#include <nlohmann/json.hpp>

namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
// TempDir — RAII temp directory (reuse pattern from test_local_store)
// ---------------------------------------------------------------------------
struct TempDir {
    fs::path path;
    explicit TempDir(const std::string& prefix = "ah_test_") {
        path = fs::temp_directory_path() / (prefix + std::to_string(
                   std::hash<std::string>{}(prefix + __FILE__ +
                       std::to_string(__LINE__))));
        fs::remove_all(path);
        fs::create_directories(path);
    }
    ~TempDir() { fs::remove_all(path); }
};

static std::string read_text(const fs::path& p) {
    std::ifstream f(p);
    return {std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
}

static std::vector<uint8_t> read_bytes(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    return std::vector<uint8_t>(std::istreambuf_iterator<char>(f),
                                std::istreambuf_iterator<char>());
}

// Minimal 1x1 white JPEG, base64-encoded (valid JPEG bytes)
static const std::string k1x1JpegB64 =
    "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U"
    "HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgN"
    "DRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy"
    "MjL/wAARCAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAA"
    "AAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/"
    "aAAwDAQACEQMRAD8AJQAB/9k=";

// Build a valid archive message JSON string
static std::string make_message(const std::string& frame_id  = "frame-001",
                                const std::string& device_id = "capture-01",
                                const std::string& timestamp = "2026-03-14T10:00:00Z",
                                const std::string& b64_jpeg  = k1x1JpegB64) {
    nlohmann::json j;
    j["frame_id"]      = frame_id;
    j["device_id"]     = device_id;
    j["timestamp"]     = timestamp;
    j["eye_side"]      = "left";
    j["quality_score"] = 0.95;
    if (!b64_jpeg.empty()) {
        j["raw_jpeg_b64"] = b64_jpeg;
    }
    return j.dump();
}

static void send(eyed::ArchiveHandler& h, const std::string& json) {
    h.handle_message(reinterpret_cast<const uint8_t*>(json.data()), json.size());
}

// ============================================================================
// base64_decode tests
// ============================================================================

TEST_CASE("base64_decode: empty string returns empty") {
    CHECK(eyed::base64_decode("").empty());
}

TEST_CASE("base64_decode: known vectors") {
    // "" → "" (RFC 4648 §10)
    CHECK(eyed::base64_decode("").empty());
    // "f" → "Zg=="
    auto v = eyed::base64_decode("Zg==");
    REQUIRE(v.size() == 1);
    CHECK(v[0] == 'f');
    // "fo" → "Zm8="
    v = eyed::base64_decode("Zm8=");
    REQUIRE(v.size() == 2);
    CHECK(v[0] == 'f'); CHECK(v[1] == 'o');
    // "foo" → "Zm9v"
    v = eyed::base64_decode("Zm9v");
    REQUIRE(v.size() == 3);
    CHECK(v[0] == 'f'); CHECK(v[1] == 'o'); CHECK(v[2] == 'o');
    // "foobar" → "Zm9vYmFy"
    v = eyed::base64_decode("Zm9vYmFy");
    REQUIRE(v.size() == 6);
    CHECK(std::string(v.begin(), v.end()) == "foobar");
}

TEST_CASE("base64_decode: binary round-trip") {
    std::vector<uint8_t> original = {0x00, 0xFF, 0x80, 0x7F, 0xAB, 0xCD};
    // Encode manually
    static const char kAlpha[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string encoded;
    for (size_t i = 0; i < original.size(); i += 3) {
        uint32_t b = (uint32_t)original[i] << 16;
        if (i+1 < original.size()) b |= (uint32_t)original[i+1] << 8;
        if (i+2 < original.size()) b |= original[i+2];
        encoded += kAlpha[(b >> 18) & 63];
        encoded += kAlpha[(b >> 12) & 63];
        encoded += (i+1 < original.size()) ? kAlpha[(b >> 6) & 63] : '=';
        encoded += (i+2 < original.size()) ? kAlpha[b & 63]        : '=';
    }
    auto decoded = eyed::base64_decode(encoded);
    CHECK(decoded == original);
}

TEST_CASE("base64_decode: invalid character returns empty") {
    CHECK(eyed::base64_decode("Zm9v!YmFy").empty());  // '!' is invalid
    CHECK(eyed::base64_decode("????").empty());
}

TEST_CASE("base64_decode: tolerates CRLF whitespace") {
    // "foobar" split with CRLF
    auto v = eyed::base64_decode("Zm9v\r\nYmFy");
    REQUIRE(v.size() == 6);
    CHECK(std::string(v.begin(), v.end()) == "foobar");
}

// ============================================================================
// sanitize_path tests
// ============================================================================

TEST_CASE("sanitize_path: normal identifiers pass through") {
    CHECK(eyed::sanitize_path("capture-01")    == "capture-01");
    CHECK(eyed::sanitize_path("frame_001")     == "frame_001");
    CHECK(eyed::sanitize_path("device.123")    == "device.123");
    CHECK(eyed::sanitize_path("ABC")           == "ABC");
}

TEST_CASE("sanitize_path: empty input returns underscore") {
    CHECK(eyed::sanitize_path("") == "_");
}

TEST_CASE("sanitize_path: dot and double-dot return underscore") {
    CHECK(eyed::sanitize_path(".")  == "_");
    CHECK(eyed::sanitize_path("..") == "_");
}

TEST_CASE("sanitize_path: path separators collapsed to single underscore") {
    CHECK(eyed::sanitize_path("a/b")    == "a_b");
    CHECK(eyed::sanitize_path("a\\b")   == "a_b");
    CHECK(eyed::sanitize_path("a//b")   == "a_b");  // consecutive → single _
    CHECK(eyed::sanitize_path("/abs")   == "_abs");
}

TEST_CASE("sanitize_path: path traversal rejected") {
    CHECK(eyed::sanitize_path("../etc/passwd") == "_");
    CHECK(eyed::sanitize_path("..\\windows")   == "_");
}

TEST_CASE("sanitize_path: colon replaced") {
    CHECK(eyed::sanitize_path("C:file") == "C_file");
}

TEST_CASE("sanitize_path: control characters replaced") {
    std::string s = "ab";
    s += '\x01';  // control char
    s += "cd";
    CHECK(eyed::sanitize_path(s) == "ab_cd");
}

// ============================================================================
// extract_date tests
// ============================================================================

TEST_CASE("extract_date: valid ISO 8601 timestamp") {
    CHECK(eyed::extract_date("2026-03-14T10:00:00Z") == "2026-03-14");
    CHECK(eyed::extract_date("2026-03-14")            == "2026-03-14");
    CHECK(eyed::extract_date("2000-01-01T00:00:00Z")  == "2000-01-01");
    CHECK(eyed::extract_date("9999-12-31T23:59:59Z")  == "9999-12-31");
}

TEST_CASE("extract_date: empty string returns today (non-empty)") {
    auto d = eyed::extract_date("");
    REQUIRE(d.size() == 10);
    CHECK(d[4] == '-');
    CHECK(d[7] == '-');
}

TEST_CASE("extract_date: invalid format falls back to today") {
    auto d = eyed::extract_date("not-a-date");
    REQUIRE(d.size() == 10);
    CHECK(d[4] == '-');
    CHECK(d[7] == '-');
}

TEST_CASE("extract_date: invalid month/day falls back to today") {
    auto d = eyed::extract_date("2026-13-01");  // month 13 invalid
    REQUIRE(d.size() == 10);
    // Can't assert specific value since it's today, just check format
    CHECK(d[4] == '-');
    CHECK(d[7] == '-');
}

// ============================================================================
// ArchiveHandler integration tests
// ============================================================================

TEST_CASE("ArchiveHandler: valid message writes JPEG and metadata") {
    TempDir td("ah_valid_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    send(handler, make_message("frame-001", "capture-01", "2026-03-14T10:00:00Z"));

    CHECK(handler.archived() == 1);
    CHECK(handler.errors()   == 0);

    // JPEG file must exist
    auto jpg_path = td.path / "raw/2026-03-14/capture-01/frame-001.jpg";
    CHECK(fs::exists(jpg_path));
    CHECK(fs::file_size(jpg_path) > 0);

    // Metadata JSON must exist and parse cleanly
    auto meta_path = td.path / "raw/2026-03-14/capture-01/frame-001.meta.json";
    CHECK(fs::exists(meta_path));
    auto meta = nlohmann::json::parse(read_text(meta_path));
    CHECK(meta["frame_id"]  == "frame-001");
    CHECK(meta["device_id"] == "capture-01");
    CHECK(!meta.contains("raw_jpeg_b64"));  // must be stripped
}

TEST_CASE("ArchiveHandler: message without raw_jpeg_b64 writes only metadata") {
    TempDir td("ah_no_jpeg_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    send(handler, make_message("frame-002", "capture-01", "2026-03-14T10:00:00Z", ""));

    CHECK(handler.archived() == 1);
    CHECK(handler.errors()   == 0);

    CHECK(!fs::exists(td.path / "raw/2026-03-14/capture-01/frame-002.jpg"));
    CHECK( fs::exists(td.path / "raw/2026-03-14/capture-01/frame-002.meta.json"));
}

TEST_CASE("ArchiveHandler: malformed JSON increments errors and does not crash") {
    TempDir td("ah_bad_json_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    const std::string bad = "{not valid json}";
    handler.handle_message(reinterpret_cast<const uint8_t*>(bad.data()), bad.size());

    CHECK(handler.archived() == 0);
    CHECK(handler.errors()   == 1);
}

TEST_CASE("ArchiveHandler: empty payload increments errors") {
    TempDir td("ah_empty_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    handler.handle_message(nullptr, 0);

    CHECK(handler.errors() == 1);
}

TEST_CASE("ArchiveHandler: invalid base64 in raw_jpeg_b64 increments errors") {
    TempDir td("ah_bad_b64_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    nlohmann::json j;
    j["frame_id"]     = "f1";
    j["device_id"]    = "d1";
    j["timestamp"]    = "2026-03-14T10:00:00Z";
    j["raw_jpeg_b64"] = "!!!NOT_VALID_BASE64!!!";
    send(handler, j.dump());

    CHECK(handler.archived() == 0);
    CHECK(handler.errors()   == 1);
}

TEST_CASE("ArchiveHandler: path traversal in device_id is sanitized") {
    TempDir td("ah_traversal_device_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    send(handler, make_message("frame-001", "../../../etc", "2026-03-14T10:00:00Z"));

    CHECK(handler.archived() == 1);
    CHECK(handler.errors()   == 0);

    // Device path should be sanitized — no actual traversal outside archive root
    bool escaped = false;
    store.walk("raw", [&](const std::string& rel, bool) {
        // All paths must remain under the store root
        if (rel.find("..") != std::string::npos) escaped = true;
        return true;
    });
    CHECK(!escaped);

    // The store root itself must not have been escaped
    CHECK(!fs::exists(td.path.parent_path() / "etc"));
}

TEST_CASE("ArchiveHandler: path traversal in frame_id is sanitized") {
    TempDir td("ah_traversal_frame_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    send(handler, make_message("../../secret", "capture-01", "2026-03-14T10:00:00Z"));

    CHECK(handler.archived() == 1);
    CHECK(handler.errors()   == 0);

    bool escaped = false;
    store.walk("raw", [&](const std::string& rel, bool) {
        if (rel.find("..") != std::string::npos) escaped = true;
        return true;
    });
    CHECK(!escaped);
}

TEST_CASE("ArchiveHandler: invalid timestamp falls back to today's date") {
    TempDir td("ah_bad_ts_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    send(handler, make_message("frame-001", "dev-01", "not-a-timestamp"));

    CHECK(handler.archived() == 1);
    CHECK(handler.errors()   == 0);

    // A date directory must have been created (today's date)
    bool found_date_dir = false;
    store.walk("raw", [&](const std::string& rel, bool is_dir) {
        if (is_dir && rel.size() > 4 && rel.find("raw/") == 0) {
            // Extract the date component: raw/YYYY-MM-DD
            std::string part = rel.substr(4, 10);
            if (part.size() == 10 && part[4] == '-' && part[7] == '-') {
                found_date_dir = true;
            }
        }
        return true;
    });
    CHECK(found_date_dir);
}

TEST_CASE("ArchiveHandler: stats accumulate across multiple messages") {
    TempDir td("ah_stats_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    send(handler, make_message("f1", "dev", "2026-03-14T00:00:00Z"));
    send(handler, make_message("f2", "dev", "2026-03-14T00:00:00Z"));
    send(handler, "{bad json}");
    send(handler, make_message("f3", "dev", "2026-03-14T00:00:00Z"));

    CHECK(handler.archived() == 3);
    CHECK(handler.errors()   == 1);
}

TEST_CASE("ArchiveHandler: metadata JSON does not contain raw_jpeg_b64") {
    TempDir td("ah_meta_strip_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    send(handler, make_message("f1", "dev", "2026-03-14T00:00:00Z", k1x1JpegB64));
    REQUIRE(handler.archived() == 1);

    auto meta_path = td.path / "raw/2026-03-14/dev/f1.meta.json";
    REQUIRE(fs::exists(meta_path));
    auto meta_text = read_text(meta_path);
    CHECK(meta_text.find("raw_jpeg_b64") == std::string::npos);
    CHECK(meta_text.find("frame_id") != std::string::npos);
}

TEST_CASE("ArchiveHandler: null raw_jpeg_b64 field writes only metadata") {
    TempDir td("ah_null_b64_");
    eyed::LocalStore store(td.path.string());
    eyed::ArchiveHandler handler(&store);

    nlohmann::json j;
    j["frame_id"]     = "f1";
    j["device_id"]    = "dev";
    j["timestamp"]    = "2026-03-14T10:00:00Z";
    j["raw_jpeg_b64"] = nullptr;
    send(handler, j.dump());

    CHECK(handler.archived() == 1);
    CHECK(handler.errors()   == 0);
    CHECK(!fs::exists(td.path / "raw/2026-03-14/dev/f1.jpg"));
    CHECK( fs::exists(td.path / "raw/2026-03-14/dev/f1.meta.json"));
}
