#pragma once

#include "object_store.h"

#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

namespace eyed {

// ---------------------------------------------------------------------------
// LocalStore — ObjectStore backed by the local filesystem.
// All paths passed to put/remove/walk are relative to root_.
// ---------------------------------------------------------------------------
class LocalStore : public ObjectStore {
  public:
    // Construct a store rooted at root_dir.
    // Creates root_dir if it does not exist.
    // Throws std::filesystem::filesystem_error on creation failure.
    explicit LocalStore(const std::string& root_dir);

    // Write data to path (relative to root_).
    // Creates parent directories as needed.
    // Uses atomic write: data is written to <path>.tmp then renamed.
    std::error_code put(const std::string& path,
                        const std::vector<uint8_t>& data) override;

    // Remove the file at path (relative to root_).
    std::error_code remove(const std::string& path) override;

    // Walk the directory tree rooted at rel_root (relative to root_),
    // calling fn for each entry. Skips silently if rel_root does not exist.
    void walk(const std::string& rel_root, WalkFunc fn) override;

    // Return the absolute root path of this store.
    const std::filesystem::path& root() const { return root_; }

  private:
    std::filesystem::path root_;

    // Resolve a store-relative path to an absolute filesystem path.
    // Does NOT validate against path traversal — callers must sanitize inputs.
    std::filesystem::path abs(const std::string& rel) const;
};

}  // namespace eyed
