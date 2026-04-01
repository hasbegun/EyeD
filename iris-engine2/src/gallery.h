#pragma once

#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include <iris/core/types.hpp>
#include <iris/crypto/smpc_gallery.hpp>
#include <iris/nodes/batch_matcher.hpp>

class SMPCManager;

struct GalleryEntry {
    std::string template_id;
    std::string identity_id;
    std::string identity_name;
    std::string eye_side;
    iris::IrisTemplate tmpl;
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
    Gallery(double match_threshold, double dedup_threshold);

    /// Enable SMPC matching via an externally-owned SMPCGallery (simulated mode).
    /// The caller must ensure the gallery outlives this object.
    void enable_smpc(iris::SMPCGallery* smpc_gallery);

    /// Enable SMPC matching via coordinator (distributed mode).
    /// The caller must ensure the SMPCManager outlives this object.
    void enable_smpc_distributed(SMPCManager* smpc_manager);

    /// Whether SMPC matching is active (either mode).
    [[nodiscard]] bool smpc_active() const;

    void add(GalleryEntry entry);

    /// Add entry to in-memory gallery only (no SMPC enrollment).
    /// Used during startup migration when templates have already been
    /// enrolled into SMPC via SMPCManager::migrate_templates().
    void add_metadata_only(GalleryEntry entry);

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
    iris::SMPCGallery* smpc_gallery_ = nullptr;
    SMPCManager* smpc_manager_ = nullptr;  // distributed mode

    // Find best match result (internal, caller holds lock)
    std::optional<GalleryMatch> find_best_match(
        const iris::IrisTemplate& probe, double threshold) const;

    // SMPC matching path — simulated mode (internal, caller holds lock)
    std::optional<GalleryMatch> find_best_match_smpc(
        const iris::IrisTemplate& probe, double threshold) const;

    // SMPC matching path — distributed mode via coordinator (internal, caller holds lock)
    std::optional<GalleryMatch> find_best_match_coordinator(
        const iris::IrisTemplate& probe, double threshold) const;
};
