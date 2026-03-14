#pragma once

#include "local_store.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>

namespace eyed {

// ---------------------------------------------------------------------------
// PurgeResult — stats from a single purge run.
// ---------------------------------------------------------------------------
struct PurgeResult {
    int     dirs_removed = 0;
    int64_t bytes_freed  = 0;
};

// ---------------------------------------------------------------------------
// RetentionPurger — enforces a retention policy for the raw/ archive tree.
//
// Mirrors Go retention.Purger behaviour:
//   - raw_days <= 0  → disabled (keep forever)
//   - Scans raw/{YYYY-MM-DD}/ top-level directories and removes any whose
//     date is strictly before (today − raw_days).
//   - Runs once immediately on start(), then every 24 hours.
//   - Background thread exits cleanly when stop() is called.
// ---------------------------------------------------------------------------
class RetentionPurger {
  public:
    // store    — must outlive the purger.
    // raw_days — retention window in days; 0 means keep forever.
    explicit RetentionPurger(LocalStore* store, int raw_days);
    ~RetentionPurger();

    // Disable copy/move (owns a thread).
    RetentionPurger(const RetentionPurger&)            = delete;
    RetentionPurger& operator=(const RetentionPurger&) = delete;

    // Start the background purge loop (spawns a detached-like thread managed
    // internally). Safe to call only once.
    void start();

    // Signal the background thread to stop and wait for it to exit.
    void stop();

    // Run one purge cycle synchronously (exposed for testing).
    // Returns stats for the run.
    PurgeResult purge_once();

    // Accessors
    int raw_days() const { return raw_days_; }

  private:
    LocalStore*  store_;
    int          raw_days_;

    std::atomic<bool>       stop_flag_{false};
    std::mutex              cv_mutex_;
    std::condition_variable cv_;

    // Background thread handle (std::thread in .cpp to keep header clean)
    struct Impl;
    Impl* impl_ = nullptr;

    void run_loop();
};

// ---------------------------------------------------------------------------
// Utility (also unit-tested directly)
// ---------------------------------------------------------------------------

// Calculate total byte size of all regular files under a directory tree.
int64_t dir_size(const std::filesystem::path& dir);

// Parse a YYYY-MM-DD string into a std::tm (UTC midnight).
// Returns false if the string is not a valid date.
bool parse_date(const std::string& s, std::tm& out);

// Format a std::tm as "YYYY-MM-DD".
std::string format_date(const std::tm& tm);

// Compute the cutoff date string "YYYY-MM-DD" = UTC today - days.
std::string cutoff_date(int days);

}  // namespace eyed
