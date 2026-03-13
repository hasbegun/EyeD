#include "local_store.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <doctest/doctest.h>

namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
// Helper: create a temporary directory for each test, cleaned up on scope exit.
// ---------------------------------------------------------------------------
struct TempDir {
    fs::path path;
    explicit TempDir(const std::string& prefix = "eyed_test_") {
        path = fs::temp_directory_path() / (prefix + std::to_string(
                   std::hash<std::string>{}(prefix + __FILE__ +
                       std::to_string(__LINE__))));
        fs::remove_all(path);
        fs::create_directories(path);
    }
    ~TempDir() { fs::remove_all(path); }
};

// Helper: read raw bytes from a file.
static std::vector<uint8_t> read_file(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    return std::vector<uint8_t>(std::istreambuf_iterator<char>(f),
                                std::istreambuf_iterator<char>());
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

TEST_CASE("LocalStore creates root directory") {
    TempDir td("ls_ctor_");
    fs::path root = td.path / "newroot";
    REQUIRE(!fs::exists(root));
    eyed::LocalStore store(root.string());
    CHECK(fs::exists(root));
    CHECK(fs::is_directory(root));
}

TEST_CASE("LocalStore accepts existing root directory") {
    TempDir td("ls_existing_");
    eyed::LocalStore store(td.path.string());
    CHECK(fs::exists(td.path));
}

// ---------------------------------------------------------------------------
// put
// ---------------------------------------------------------------------------

TEST_CASE("LocalStore::put writes file contents") {
    TempDir td("ls_put_");
    eyed::LocalStore store(td.path.string());

    std::vector<uint8_t> data = {0x01, 0x02, 0x03, 0xFF};
    auto ec = store.put("file.bin", data);

    REQUIRE(!ec);
    auto result = read_file(td.path / "file.bin");
    CHECK(result == data);
}

TEST_CASE("LocalStore::put creates parent directories") {
    TempDir td("ls_put_mkdir_");
    eyed::LocalStore store(td.path.string());

    std::vector<uint8_t> data = {'h', 'e', 'l', 'l', 'o'};
    auto ec = store.put("raw/2026-01-01/device-01/frame.jpg", data);

    REQUIRE(!ec);
    CHECK(fs::exists(td.path / "raw/2026-01-01/device-01/frame.jpg"));
    auto result = read_file(td.path / "raw/2026-01-01/device-01/frame.jpg");
    CHECK(result == data);
}

TEST_CASE("LocalStore::put overwrites existing file") {
    TempDir td("ls_put_overwrite_");
    eyed::LocalStore store(td.path.string());

    std::vector<uint8_t> first  = {0x01};
    std::vector<uint8_t> second = {0x02, 0x03};

    REQUIRE(!store.put("f.bin", first));
    REQUIRE(!store.put("f.bin", second));

    auto result = read_file(td.path / "f.bin");
    CHECK(result == second);
}

TEST_CASE("LocalStore::put with empty data writes empty file") {
    TempDir td("ls_put_empty_");
    eyed::LocalStore store(td.path.string());

    std::vector<uint8_t> empty;
    auto ec = store.put("empty.bin", empty);

    REQUIRE(!ec);
    CHECK(fs::exists(td.path / "empty.bin"));
    CHECK(fs::file_size(td.path / "empty.bin") == 0);
}

TEST_CASE("LocalStore::put is atomic: no .tmp file left on success") {
    TempDir td("ls_put_atomic_");
    eyed::LocalStore store(td.path.string());

    std::vector<uint8_t> data = {1, 2, 3};
    REQUIRE(!store.put("a.bin", data));

    // After successful put, no .tmp file should exist
    CHECK(!fs::exists(td.path / "a.bin.tmp"));
    CHECK(fs::exists(td.path / "a.bin"));
}

TEST_CASE("LocalStore::put with nested path creates full dir tree") {
    TempDir td("ls_put_deep_");
    eyed::LocalStore store(td.path.string());

    std::vector<uint8_t> data = {9};
    REQUIRE(!store.put("a/b/c/d/e.txt", data));
    CHECK(fs::exists(td.path / "a/b/c/d/e.txt"));
}

// ---------------------------------------------------------------------------
// remove
// ---------------------------------------------------------------------------

TEST_CASE("LocalStore::remove deletes existing file") {
    TempDir td("ls_rm_");
    eyed::LocalStore store(td.path.string());

    std::vector<uint8_t> data = {1};
    REQUIRE(!store.put("todelete.bin", data));
    REQUIRE(fs::exists(td.path / "todelete.bin"));

    auto ec = store.remove("todelete.bin");
    CHECK(!ec);
    CHECK(!fs::exists(td.path / "todelete.bin"));
}

TEST_CASE("LocalStore::remove on non-existent file is a no-op (C++ behavior)") {
    TempDir td("ls_rm_noexist_");
    eyed::LocalStore store(td.path.string());

    // std::filesystem::remove returns false and does NOT set error_code for a
    // missing file (unlike Go's os.Remove which returns *PathError).
    // This makes deletes idempotent — acceptable for our use case since the
    // retention purger uses remove_all on date directories, not individual files.
    auto ec = store.remove("nonexistent.bin");
    CHECK(!ec);
    CHECK(!fs::exists(td.path / "nonexistent.bin"));
}

// ---------------------------------------------------------------------------
// walk
// ---------------------------------------------------------------------------

TEST_CASE("LocalStore::walk visits all entries") {
    TempDir td("ls_walk_");
    eyed::LocalStore store(td.path.string());

    REQUIRE(!store.put("raw/2026-01-01/dev/a.jpg",      {1}));
    REQUIRE(!store.put("raw/2026-01-01/dev/a.meta.json",{2}));
    REQUIRE(!store.put("raw/2026-01-02/dev/b.jpg",      {3}));

    std::vector<std::string> visited;
    store.walk("raw", [&](const std::string& rel, bool) {
        visited.push_back(rel);
        return true;  // continue
    });

    // Should have visited directories and files
    CHECK(visited.size() >= 3u);

    // The three files must be present
    auto has = [&](const std::string& suffix) {
        return std::any_of(visited.begin(), visited.end(),
            [&](const std::string& s) {
                return s.find(suffix) != std::string::npos;
            });
    };
    CHECK(has("a.jpg"));
    CHECK(has("a.meta.json"));
    CHECK(has("b.jpg"));
}

TEST_CASE("LocalStore::walk on non-existent root is a no-op") {
    TempDir td("ls_walk_noexist_");
    eyed::LocalStore store(td.path.string());

    int count = 0;
    store.walk("does/not/exist", [&](const std::string&, bool) {
        ++count;
        return true;
    });
    CHECK(count == 0);
}

TEST_CASE("LocalStore::walk early stop works") {
    TempDir td("ls_walk_stop_");
    eyed::LocalStore store(td.path.string());

    REQUIRE(!store.put("a/f1.bin", {1}));
    REQUIRE(!store.put("a/f2.bin", {2}));
    REQUIRE(!store.put("a/f3.bin", {3}));

    int count = 0;
    store.walk("a", [&](const std::string&, bool is_dir) {
        if (!is_dir) {
            ++count;
            if (count >= 1) return false;  // stop after first file
        }
        return true;
    });
    CHECK(count == 1);
}

TEST_CASE("LocalStore::walk on empty directory visits no files") {
    TempDir td("ls_walk_empty_");
    eyed::LocalStore store(td.path.string());

    fs::create_directories(td.path / "empty_dir");

    int file_count = 0;
    store.walk("empty_dir", [&](const std::string&, bool is_dir) {
        if (!is_dir) ++file_count;
        return true;
    });
    CHECK(file_count == 0);
}

TEST_CASE("LocalStore::walk relative paths are relative to store root") {
    TempDir td("ls_walk_rel_");
    eyed::LocalStore store(td.path.string());

    REQUIRE(!store.put("sub/file.txt", {42}));

    bool found = false;
    store.walk("sub", [&](const std::string& rel, bool is_dir) {
        if (!is_dir && rel.find("file.txt") != std::string::npos) {
            // rel should be "sub/file.txt", not an absolute path
            CHECK(rel[0] != '/');
            found = true;
        }
        return true;
    });
    CHECK(found);
}

// ---------------------------------------------------------------------------
// root()
// ---------------------------------------------------------------------------

TEST_CASE("LocalStore::root returns absolute path") {
    TempDir td("ls_root_");
    eyed::LocalStore store(td.path.string());
    CHECK(store.root().is_absolute());
    CHECK(store.root() == std::filesystem::canonical(td.path));
}
