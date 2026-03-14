#include "local_store.h"

#include <cerrno>
#include <cstdio>
#include <fstream>
#include <system_error>

namespace eyed {

// ---------------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------------

LocalStore::LocalStore(const std::string& root_dir) {
    root_ = std::filesystem::absolute(root_dir);
    std::filesystem::create_directories(root_);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

std::filesystem::path LocalStore::abs(const std::string& rel) const {
    return root_ / rel;
}

// ---------------------------------------------------------------------------
// put — atomic write via .tmp + rename
// ---------------------------------------------------------------------------

std::error_code LocalStore::put(const std::string& path,
                                const std::vector<uint8_t>& data) {
    auto full = abs(path);
    auto tmp  = std::filesystem::path(full.string() + ".tmp");

    // Create parent directories
    std::error_code ec;
    std::filesystem::create_directories(full.parent_path(), ec);
    if (ec) return ec;

    // Write to .tmp file
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) {
            return std::error_code(errno, std::generic_category());
        }
        if (!data.empty()) {
            out.write(reinterpret_cast<const char*>(data.data()),
                      static_cast<std::streamsize>(data.size()));
        }
        if (!out) {
            std::filesystem::remove(tmp, ec);
            return std::error_code(errno, std::generic_category());
        }
    }

    // Atomic rename .tmp → final path
    std::filesystem::rename(tmp, full, ec);
    if (ec) {
        std::error_code rm_ec;
        std::filesystem::remove(tmp, rm_ec);
    }
    return ec;
}

// ---------------------------------------------------------------------------
// remove
// ---------------------------------------------------------------------------

std::error_code LocalStore::remove(const std::string& path) {
    std::error_code ec;
    std::filesystem::remove(abs(path), ec);
    return ec;
}

// ---------------------------------------------------------------------------
// walk — recursive directory traversal
// ---------------------------------------------------------------------------

void LocalStore::walk(const std::string& rel_root, WalkFunc fn) {
    auto full = abs(rel_root);

    std::error_code ec;
    if (!std::filesystem::exists(full, ec) || ec) {
        return;  // nothing to walk
    }

    for (auto it = std::filesystem::recursive_directory_iterator(
                       full, std::filesystem::directory_options::skip_permission_denied, ec);
         !ec && it != std::filesystem::recursive_directory_iterator();
         it.increment(ec)) {

        const auto& entry = *it;
        // Build relative path from store root (not from rel_root anchor)
        std::error_code rel_ec;
        auto rel = std::filesystem::relative(entry.path(), root_, rel_ec);
        if (rel_ec) continue;

        bool is_dir = entry.is_directory(ec);
        if (ec) { ec.clear(); continue; }

        if (!fn(rel.string(), is_dir)) {
            return;  // caller requested early stop
        }
    }
}

}  // namespace eyed
