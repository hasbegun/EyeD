#pragma once

#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>
#include <system_error>
#include <vector>

namespace eyed {

// ---------------------------------------------------------------------------
// WalkFunc — callback for ObjectStore::walk().
// Called for each file (and optionally directory) found under the walk root.
//   rel_path — path relative to the store root
//   is_dir   — true when the entry is a directory
// Return false to stop the walk early; return true to continue.
// ---------------------------------------------------------------------------
using WalkFunc =
    std::function<bool(const std::string& rel_path, bool is_dir)>;

// ---------------------------------------------------------------------------
// ObjectStore — abstract file storage interface.
// Local filesystem for dev/edge; S3-compatible backend is a future extension.
// ---------------------------------------------------------------------------
class ObjectStore {
  public:
    virtual ~ObjectStore() = default;

    // Write data to path (relative to store root).
    // Creates parent directories as needed.
    // Returns a non-zero error_code on failure.
    virtual std::error_code put(const std::string& path,
                                const std::vector<uint8_t>& data) = 0;

    // Remove the file at path (relative to store root).
    // Returns a non-zero error_code on failure.
    virtual std::error_code remove(const std::string& path) = 0;

    // Walk the directory tree rooted at rel_root (relative to store root),
    // calling fn for each entry (files and directories).
    // Walking stops early if fn returns false.
    virtual void walk(const std::string& rel_root, WalkFunc fn) = 0;
};

}  // namespace eyed
