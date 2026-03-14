#include "retention_purger.h"
#include "local_store.h"

#include <chrono>
#include <ctime>
#include <filesystem>
#include <string>
#include <thread>
#include <vector>
#include <doctest/doctest.h>

namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
// TempDir — RAII temp directory
// ---------------------------------------------------------------------------
struct TempDir {
    fs::path path;
    explicit TempDir(const std::string& prefix = "rp_test_") {
        path = fs::temp_directory_path() / (prefix + std::to_string(
                   std::hash<std::string>{}(prefix + __FILE__ +
                       std::to_string(__LINE__))));
        fs::remove_all(path);
        fs::create_directories(path);
    }
    ~TempDir() { fs::remove_all(path); }
};

// Create a dummy file with 'size' bytes under store's raw/{date}/{device}/
static void make_frame(eyed::LocalStore& store, const std::string& date,
                       const std::string& device, const std::string& frame,
                       size_t size = 128) {
    std::vector<uint8_t> data(size, 0xAB);
    store.put("raw/" + date + "/" + device + "/" + frame + ".jpg", data);
    store.put("raw/" + date + "/" + device + "/" + frame + ".meta.json",
              std::vector<uint8_t>{'{', '}'});
}

// ---------------------------------------------------------------------------
// parse_date tests
// ---------------------------------------------------------------------------

TEST_CASE("parse_date: valid dates") {
    std::tm tm{};
    REQUIRE(eyed::parse_date("2026-03-14", tm));
    CHECK(tm.tm_year == 2026 - 1900);
    CHECK(tm.tm_mon  == 3 - 1);
    CHECK(tm.tm_mday == 14);
}

TEST_CASE("parse_date: rejects non-date strings") {
    std::tm tm{};
    CHECK(!eyed::parse_date("", tm));
    CHECK(!eyed::parse_date("not-a-date", tm));
    CHECK(!eyed::parse_date("2026-3-14", tm));       // single-digit month
    CHECK(!eyed::parse_date("2026/03/14", tm));       // wrong separators
    CHECK(!eyed::parse_date("20260314", tm));          // no separators
    CHECK(!eyed::parse_date("2026-13-01", tm));        // month > 12
    CHECK(!eyed::parse_date("2026-00-01", tm));        // month = 0
}

TEST_CASE("parse_date: boundary years") {
    std::tm tm{};
    CHECK( eyed::parse_date("1970-01-01", tm));
    CHECK( eyed::parse_date("9999-12-31", tm));
    CHECK(!eyed::parse_date("1969-12-31", tm));  // year < 1970
}

// ---------------------------------------------------------------------------
// format_date tests
// ---------------------------------------------------------------------------

TEST_CASE("format_date: round-trips with parse_date") {
    std::tm tm{};
    REQUIRE(eyed::parse_date("2026-03-14", tm));
    CHECK(eyed::format_date(tm) == "2026-03-14");
}

TEST_CASE("format_date: epoch") {
    std::tm tm{};
    REQUIRE(eyed::parse_date("1970-01-01", tm));
    CHECK(eyed::format_date(tm) == "1970-01-01");
}

// ---------------------------------------------------------------------------
// cutoff_date tests
// ---------------------------------------------------------------------------

TEST_CASE("cutoff_date: 0 days gives today") {
    auto today = eyed::cutoff_date(0);
    REQUIRE(today.size() == 10);
    CHECK(today[4] == '-');
    CHECK(today[7] == '-');
    // Verify it's not in the past relative to itself
    CHECK(today >= "1970-01-01");
}

TEST_CASE("cutoff_date: 1 day gives yesterday") {
    auto today     = eyed::cutoff_date(0);
    auto yesterday = eyed::cutoff_date(1);
    CHECK(yesterday < today);
    CHECK(yesterday.size() == 10);
}

TEST_CASE("cutoff_date: 730 days is roughly 2 years ago") {
    auto two_years_ago = eyed::cutoff_date(730);
    auto today         = eyed::cutoff_date(0);
    CHECK(two_years_ago < today);
    // The year part must be at least 1 less
    int today_year    = std::stoi(today.substr(0, 4));
    int cutoff_year   = std::stoi(two_years_ago.substr(0, 4));
    CHECK(cutoff_year <= today_year - 1);
}

// ---------------------------------------------------------------------------
// dir_size tests
// ---------------------------------------------------------------------------

TEST_CASE("dir_size: empty directory returns 0") {
    TempDir td("ds_empty_");
    CHECK(eyed::dir_size(td.path) == 0);
}

TEST_CASE("dir_size: sums file sizes recursively") {
    TempDir td("ds_sum_");
    eyed::LocalStore store(td.path.string());
    store.put("a/f1.bin", std::vector<uint8_t>(100, 0));
    store.put("a/f2.bin", std::vector<uint8_t>(200, 0));
    store.put("a/b/f3.bin", std::vector<uint8_t>(50, 0));

    auto sz = eyed::dir_size(td.path);
    CHECK(sz >= 350);  // >= because metadata might add tiny overhead
}

// ---------------------------------------------------------------------------
// RetentionPurger::purge_once tests
// ---------------------------------------------------------------------------

TEST_CASE("purge_once: raw_days=0 disables purge") {
    TempDir td("rp_disabled_");
    eyed::LocalStore store(td.path.string());
    make_frame(store, "2020-01-01", "dev", "f1");

    eyed::RetentionPurger purger(&store, 0);
    auto result = purger.purge_once();

    CHECK(result.dirs_removed == 0);
    CHECK(result.bytes_freed  == 0);
    CHECK(fs::exists(td.path / "raw/2020-01-01"));
}

TEST_CASE("purge_once: removes directories older than cutoff") {
    TempDir td("rp_removes_");
    eyed::LocalStore store(td.path.string());

    // Very old date — should always be removed
    make_frame(store, "2000-01-01", "dev", "f1", 256);

    eyed::RetentionPurger purger(&store, 30);  // keep last 30 days
    auto result = purger.purge_once();

    CHECK(result.dirs_removed == 1);
    CHECK(result.bytes_freed  >  0);
    CHECK(!fs::exists(td.path / "raw/2000-01-01"));
}

TEST_CASE("purge_once: keeps directories within retention window") {
    TempDir td("rp_keeps_");
    eyed::LocalStore store(td.path.string());

    // Today's date is always within the retention window
    auto today = eyed::cutoff_date(0);  // today
    make_frame(store, today, "dev", "f1", 128);

    eyed::RetentionPurger purger(&store, 30);
    auto result = purger.purge_once();

    CHECK(result.dirs_removed == 0);
    CHECK(fs::exists(td.path / ("raw/" + today)));
}

TEST_CASE("purge_once: mixed old and new directories") {
    TempDir td("rp_mixed_");
    eyed::LocalStore store(td.path.string());

    auto today     = eyed::cutoff_date(0);
    auto yesterday = eyed::cutoff_date(1);
    make_frame(store, today,        "dev", "new_frame", 128);
    make_frame(store, yesterday,    "dev", "recent",    128);
    make_frame(store, "2000-06-01", "dev", "old_frame", 256);

    eyed::RetentionPurger purger(&store, 30);  // keep 30 days
    auto result = purger.purge_once();

    // Only the ancient dir should be gone
    CHECK(result.dirs_removed == 1);
    CHECK(!fs::exists(td.path / "raw/2000-06-01"));
    CHECK( fs::exists(td.path / ("raw/" + today)));
    CHECK( fs::exists(td.path / ("raw/" + yesterday)));
}

TEST_CASE("purge_once: skips non-date directories") {
    TempDir td("rp_skip_");
    eyed::LocalStore store(td.path.string());

    // Non-date directory name — should be skipped
    fs::create_directories(td.path / "raw" / "not-a-date");
    fs::create_directories(td.path / "raw" / "tmp");
    make_frame(store, "2000-01-01", "dev", "f1");

    eyed::RetentionPurger purger(&store, 30);
    auto result = purger.purge_once();

    // Only the date dir is removed; non-date dirs survive
    CHECK(result.dirs_removed == 1);
    CHECK(!fs::exists(td.path / "raw/2000-01-01"));
    CHECK( fs::exists(td.path / "raw/not-a-date"));
    CHECK( fs::exists(td.path / "raw/tmp"));
}

TEST_CASE("purge_once: no-op when raw/ directory does not exist") {
    TempDir td("rp_noraw_");
    eyed::LocalStore store(td.path.string());
    // raw/ never created

    eyed::RetentionPurger purger(&store, 30);
    auto result = purger.purge_once();

    CHECK(result.dirs_removed == 0);
    CHECK(result.bytes_freed  == 0);
}

TEST_CASE("purge_once: bytes_freed reflects actual file sizes") {
    TempDir td("rp_bytes_");
    eyed::LocalStore store(td.path.string());

    const size_t file_size = 1024;
    make_frame(store, "2000-01-01", "dev", "f1", file_size);
    make_frame(store, "2000-01-01", "dev", "f2", file_size);

    eyed::RetentionPurger purger(&store, 30);
    auto result = purger.purge_once();

    CHECK(result.dirs_removed == 1);
    // Two JPEG files + two tiny meta files
    CHECK(result.bytes_freed >= static_cast<int64_t>(file_size * 2));
}

TEST_CASE("purge_once: multiple old directories all removed") {
    TempDir td("rp_multi_");
    eyed::LocalStore store(td.path.string());

    make_frame(store, "2000-01-01", "dev", "f1");
    make_frame(store, "2001-06-15", "dev", "f2");
    make_frame(store, "2005-12-31", "dev", "f3");

    eyed::RetentionPurger purger(&store, 30);
    auto result = purger.purge_once();

    CHECK(result.dirs_removed == 3);
    CHECK(!fs::exists(td.path / "raw/2000-01-01"));
    CHECK(!fs::exists(td.path / "raw/2001-06-15"));
    CHECK(!fs::exists(td.path / "raw/2005-12-31"));
}

// ---------------------------------------------------------------------------
// RetentionPurger start/stop (smoke test — just verify no crash or deadlock)
// ---------------------------------------------------------------------------

TEST_CASE("RetentionPurger: start and stop immediately") {
    TempDir td("rp_startstop_");
    eyed::LocalStore store(td.path.string());
    eyed::RetentionPurger purger(&store, 30);

    purger.start();
    // Brief pause to let the initial purge_once run
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    purger.stop();
    // No crash or deadlock → pass
    CHECK(true);
}
