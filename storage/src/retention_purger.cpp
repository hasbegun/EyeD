#include "retention_purger.h"

#include <chrono>
#include <ctime>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <thread>

namespace eyed {

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

int64_t dir_size(const std::filesystem::path& dir) {
    int64_t total = 0;
    std::error_code ec;
    for (auto it = std::filesystem::recursive_directory_iterator(
                       dir,
                       std::filesystem::directory_options::skip_permission_denied, ec);
         !ec && it != std::filesystem::recursive_directory_iterator();
         it.increment(ec)) {
        if (!it->is_directory(ec) && !ec) {
            auto sz = it->file_size(ec);
            if (!ec) total += static_cast<int64_t>(sz);
        }
        ec.clear();
    }
    return total;
}

bool parse_date(const std::string& s, std::tm& out) {
    if (s.size() != 10) return false;
    auto is_digit = [](char c) { return c >= '0' && c <= '9'; };
    if (!is_digit(s[0]) || !is_digit(s[1]) || !is_digit(s[2]) || !is_digit(s[3])) return false;
    if (s[4] != '-') return false;
    if (!is_digit(s[5]) || !is_digit(s[6])) return false;
    if (s[7] != '-') return false;
    if (!is_digit(s[8]) || !is_digit(s[9])) return false;

    int year  = std::stoi(s.substr(0, 4));
    int month = std::stoi(s.substr(5, 2));
    int day   = std::stoi(s.substr(8, 2));

    if (year < 1970 || year > 9999) return false;
    if (month < 1   || month > 12)  return false;
    if (day   < 1   || day   > 31)  return false;

    out = {};
    out.tm_year = year  - 1900;
    out.tm_mon  = month - 1;
    out.tm_mday = day;
    return true;
}

std::string format_date(const std::tm& tm) {
    char buf[11];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d", &tm);
    return std::string(buf);
}

std::string cutoff_date(int days) {
    auto now = std::chrono::system_clock::now();
    auto t   = std::chrono::system_clock::to_time_t(now);

    std::tm tm{};
    gmtime_r(&t, &tm);

    // Subtract days
    tm.tm_mday -= days;
    timegm(&tm);  // normalize (handles negative day-of-month)

    return format_date(tm);
}

// ---------------------------------------------------------------------------
// RetentionPurger::Impl — holds the std::thread
// ---------------------------------------------------------------------------
struct RetentionPurger::Impl {
    std::thread thread;
};

// ---------------------------------------------------------------------------
// RetentionPurger
// ---------------------------------------------------------------------------

RetentionPurger::RetentionPurger(LocalStore* store, int raw_days)
    : store_(store), raw_days_(raw_days) {}

RetentionPurger::~RetentionPurger() {
    stop();
    delete impl_;
}

void RetentionPurger::start() {
    stop_flag_.store(false, std::memory_order_relaxed);
    impl_ = new Impl();
    impl_->thread = std::thread([this] { run_loop(); });
}

void RetentionPurger::stop() {
    stop_flag_.store(true, std::memory_order_relaxed);
    cv_.notify_all();
    if (impl_ && impl_->thread.joinable()) {
        impl_->thread.join();
    }
}

void RetentionPurger::run_loop() {
    // Run once immediately (mirrors Go behaviour)
    purge_once();

    // Then wait 24 h, checking stop_flag every wakeup
    while (true) {
        std::unique_lock<std::mutex> lock(cv_mutex_);
        // Wait up to 24 hours or until stop is signalled
        cv_.wait_for(lock, std::chrono::hours(24),
                     [this] { return stop_flag_.load(std::memory_order_relaxed); });
        if (stop_flag_.load(std::memory_order_relaxed)) break;
        purge_once();
    }
}

PurgeResult RetentionPurger::purge_once() {
    PurgeResult result;

    if (raw_days_ <= 0) {
        return result;  // keep forever
    }

    const std::string cutoff = cutoff_date(raw_days_);
    auto raw_root = store_->root() / "raw";

    std::error_code ec;
    if (!std::filesystem::exists(raw_root, ec) || ec) {
        return result;
    }

    for (auto& entry : std::filesystem::directory_iterator(raw_root, ec)) {
        if (ec) break;
        if (!entry.is_directory()) continue;

        const std::string name = entry.path().filename().string();

        std::tm date_tm{};
        if (!parse_date(name, date_tm)) {
            continue;  // skip non-date directories
        }

        // String comparison is valid for YYYY-MM-DD (lexicographic == chronological)
        if (name < cutoff) {
            int64_t sz = dir_size(entry.path());

            std::error_code rm_ec;
            std::filesystem::remove_all(entry.path(), rm_ec);
            if (!rm_ec) {
                result.dirs_removed++;
                result.bytes_freed += sz;
            }
        }
    }

    return result;
}

}  // namespace eyed
