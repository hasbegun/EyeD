#pragma once

#include "object_store.h"

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

namespace eyed {

// ---------------------------------------------------------------------------
// ArchiveHandler — processes eyed.archive NATS messages.
//
// Core responsibility: JSON decode → base64 JPEG decode → write files to store.
// Thread-safe: handle_message may be called concurrently from NATS dispatch.
// ---------------------------------------------------------------------------
class ArchiveHandler {
  public:
    explicit ArchiveHandler(ObjectStore* store);

    // Process a raw JSON NATS message payload (bytes, len).
    // Writes:
    //   raw/{date}/{device_id}/{frame_id}.jpg         (if raw_jpeg_b64 present)
    //   raw/{date}/{device_id}/{frame_id}.meta.json   (always)
    // Updates archived_/errors_ counters atomically.
    void handle_message(const uint8_t* data, size_t len);

    uint64_t archived() const { return archived_.load(std::memory_order_relaxed); }
    uint64_t errors()   const { return errors_.load(std::memory_order_relaxed); }

  private:
    ObjectStore* store_;
    std::atomic<uint64_t> archived_{0};
    std::atomic<uint64_t> errors_{0};

    struct ParsedMessage {
        std::string frame_id;
        std::string device_id;
        std::string timestamp;
        std::vector<uint8_t> jpeg;   // decoded from raw_jpeg_b64; empty if absent
        bool has_jpeg = false;
        std::string metadata_json;   // full JSON minus raw_jpeg_b64 field
    };

    // Parse JSON payload into ParsedMessage.
    // Returns false on malformed JSON or missing required fields.
    bool parse(const uint8_t* data, size_t len, ParsedMessage& out);

    // Write files to store. Returns false on I/O failure.
    bool write(const ParsedMessage& msg);
};

// ---------------------------------------------------------------------------
// Utilities (free functions — also exercised directly in tests)
// ---------------------------------------------------------------------------

// Sanitize a path component: collapses unsafe chars (/ \ : control chars) to
// underscores, rejects directory traversal sequences (. ..).
// Returns "_" for empty, ".", or ".." inputs.
std::string sanitize_path(const std::string& s);

// Extract "YYYY-MM-DD" from an ISO 8601 timestamp string.
// Falls back to today's UTC date on parse failure or empty input.
std::string extract_date(const std::string& iso8601);

// Decode standard base64 (RFC 4648) to raw bytes.
// Tolerates whitespace (CRLF line endings from MIME).
// Returns an empty vector on invalid characters or corrupt padding.
std::vector<uint8_t> base64_decode(const std::string& encoded);

}  // namespace eyed
