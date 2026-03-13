#pragma once

#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include <iris/core/types.hpp>
#include <iris/nodes/batch_matcher.hpp>

#ifdef IRIS_HAS_FHE
#include <iris/crypto/encrypted_template.hpp>
#endif

class FHEManager;

struct GalleryEntry {
    std::string template_id;
    std::string identity_id;
    std::string identity_name;
    std::string eye_side;
    iris::IrisTemplate tmpl;  // plaintext (used when FHE is off)
#ifdef IRIS_HAS_FHE
    // Encrypted templates (one per scale) — used when FHE is active.
    // Each EncryptedTemplate bundles both code_ct (iris bits) and mask_ct
    // (validity mask bits), so a single vector covers everything.
    std::vector<iris::EncryptedTemplate> encrypted_iris;
#endif
    bool is_encrypted = false;
};

struct GalleryMatch {
    double hamming_distance = 1.0;
    bool is_match = false;
    int best_rotation = 0;
    std::string matched_identity_id;
    std::string matched_identity_name;
    std::string matched_template_id;
};

struct DuplicateCheck {
    bool is_duplicate = false;
    std::string duplicate_identity_id;
    std::string duplicate_identity_name;
};

class Gallery {
  public:
    Gallery(double match_threshold, double dedup_threshold,
            FHEManager* fhe = nullptr);

    void add(GalleryEntry entry);
    int remove(const std::string& identity_id);

    // Match probe against gallery. Returns nullopt if gallery is empty.
    std::optional<GalleryMatch> match(const iris::IrisTemplate& probe) const;

    // Check for duplicate before enrollment.
    DuplicateCheck check_duplicate(const iris::IrisTemplate& probe) const;

    size_t size() const;

    struct TemplateInfo {
        std::string template_id;
        std::string eye_side;
    };
    struct IdentityInfo {
        std::string identity_id;
        std::string name;
        std::vector<TemplateInfo> templates;
    };
    std::vector<IdentityInfo> list() const;

  private:
    mutable std::mutex mutex_;
    std::vector<GalleryEntry> entries_;
    iris::BatchMatcher matcher_;
    double match_threshold_;
    double dedup_threshold_;
    FHEManager* fhe_ = nullptr;

    // Find best match result (internal, caller holds lock)
    std::optional<GalleryMatch> find_best_match(
        const iris::IrisTemplate& probe, double threshold) const;

#ifdef IRIS_HAS_FHE
    // FHE-encrypted matching: probe (plaintext) vs gallery (encrypted)
    std::optional<GalleryMatch> find_best_match_encrypted(
        const iris::IrisTemplate& probe, double threshold) const;
#endif
};
