#include "gallery.h"

#include <algorithm>
#include <iostream>
#include <map>

#include "smpc.h"

Gallery::Gallery(double match_threshold, double dedup_threshold)
    : match_threshold_(match_threshold),
      dedup_threshold_(dedup_threshold) {}

void Gallery::enable_smpc(iris::SMPCGallery* smpc_gallery) {
    std::lock_guard lock(mutex_);
    smpc_gallery_ = smpc_gallery;
}

void Gallery::enable_smpc_distributed(SMPCManager* smpc_manager) {
    std::lock_guard lock(mutex_);
    smpc_manager_ = smpc_manager;
}

bool Gallery::smpc_active() const {
    return smpc_gallery_ != nullptr || smpc_manager_ != nullptr;
}

void Gallery::add(GalleryEntry entry) {
    std::lock_guard lock(mutex_);
    if (smpc_manager_) {
        // Distributed mode: enroll via coordinator (splits shares, distributes to participants)
        auto r = smpc_manager_->enroll_distributed(entry.template_id, entry.tmpl);
        if (!r.has_value()) {
            std::cerr << "[gallery] Coordinator enroll failed: "
                      << r.error().message << std::endl;
        }
    } else if (smpc_gallery_) {
        // Simulated mode: add to in-process SMPC gallery
        auto r = smpc_gallery_->add_template(entry.template_id, entry.tmpl);
        if (!r.has_value()) {
            std::cerr << "[gallery] SMPC add_template failed: "
                      << r.error().message << std::endl;
        }
    }
    entries_.push_back(std::move(entry));
}

void Gallery::add_metadata_only(GalleryEntry entry) {
    std::lock_guard lock(mutex_);
    entries_.push_back(std::move(entry));
}

int Gallery::remove(const std::string& identity_id) {
    std::lock_guard lock(mutex_);
    // Remove from SMPC gallery first (before entries_ is modified)
    if (smpc_gallery_) {
        for (const auto& e : entries_) {
            if (e.identity_id == identity_id) {
                smpc_gallery_->remove_template(e.template_id);
            }
        }
    }
    auto it = std::remove_if(entries_.begin(), entries_.end(),
                             [&](const GalleryEntry& e) {
                                 return e.identity_id == identity_id;
                             });
    int count = static_cast<int>(std::distance(it, entries_.end()));
    entries_.erase(it, entries_.end());
    return count;
}

std::optional<GalleryMatch> Gallery::find_best_match(
    const iris::IrisTemplate& probe, double threshold) const {
    // Caller must hold mutex_
    if (entries_.empty()) return std::nullopt;

    if (smpc_manager_) {
        return find_best_match_coordinator(probe, threshold);
    }

    if (smpc_gallery_) {
        return find_best_match_smpc(probe, threshold);
    }

    // Plaintext matching path
    std::vector<iris::IrisTemplate> gallery_templates;
    gallery_templates.reserve(entries_.size());
    for (const auto& e : entries_) {
        gallery_templates.push_back(e.tmpl);
    }

    auto results = matcher_.match_one_vs_n(probe, gallery_templates);
    if (!results || results->empty()) return std::nullopt;

    size_t best_idx = 0;
    double best_dist = 1.0;
    int best_rot = 0;
    for (size_t i = 0; i < results->size(); ++i) {
        if ((*results)[i].distance < best_dist) {
            best_dist = (*results)[i].distance;
            best_idx = i;
            best_rot = (*results)[i].best_rotation;
        }
    }

    bool is_match = best_dist < threshold;
    return GalleryMatch{
        .hamming_distance = best_dist,
        .is_match = is_match,
        .best_rotation = best_rot,
        .matched_identity_id = entries_[best_idx].identity_id,
        .matched_identity_name = entries_[best_idx].identity_name,
        .matched_template_id = entries_[best_idx].template_id,
    };
}

std::optional<GalleryMatch> Gallery::find_best_match_smpc(
    const iris::IrisTemplate& probe, double threshold) const {
    // Caller must hold mutex_
    if (entries_.empty() || !smpc_gallery_) return std::nullopt;

    auto results = smpc_gallery_->match_probe(probe);
    if (!results || results->empty()) return std::nullopt;

    // Results are in the same order as entries_ (kept in sync by add/remove)
    size_t best_idx = 0;
    double best_dist = 1.0;
    int best_rot = 0;
    for (size_t i = 0; i < results->size() && i < entries_.size(); ++i) {
        if ((*results)[i].distance < best_dist) {
            best_dist = (*results)[i].distance;
            best_idx = i;
            best_rot = (*results)[i].best_rotation;
        }
    }

    bool is_match = best_dist < threshold;
    return GalleryMatch{
        .hamming_distance = best_dist,
        .is_match = is_match,
        .best_rotation = best_rot,
        .matched_identity_id = entries_[best_idx].identity_id,
        .matched_identity_name = entries_[best_idx].identity_name,
        .matched_template_id = entries_[best_idx].template_id,
    };
}

std::optional<GalleryMatch> Gallery::match(
    const iris::IrisTemplate& probe) const {
    std::lock_guard lock(mutex_);
    return find_best_match(probe, match_threshold_);
}

DuplicateCheck Gallery::check_duplicate(
    const iris::IrisTemplate& probe) const {
    std::lock_guard lock(mutex_);
    auto best = find_best_match(probe, dedup_threshold_);
    if (!best || !best->is_match) {
        return DuplicateCheck{};
    }
    return {
        .is_duplicate = true,
        .duplicate_identity_id = best->matched_identity_id,
        .duplicate_identity_name = best->matched_identity_name,
    };
}

size_t Gallery::size() const {
    std::lock_guard lock(mutex_);
    return entries_.size();
}

std::optional<GalleryMatch> Gallery::find_best_match_coordinator(
    const iris::IrisTemplate& probe, double threshold) const {
    // Caller must hold mutex_
    if (entries_.empty() || !smpc_manager_) return std::nullopt;

    auto results = smpc_manager_->verify_distributed(probe);
    if (!results || results->empty()) return std::nullopt;

    // Find the best (lowest distance) result
    const CoordinatorVerifyResult* best_result = nullptr;
    for (const auto& r : *results) {
        if (!best_result || r.distance < best_result->distance) {
            best_result = &r;
        }
    }
    if (!best_result) return std::nullopt;

    // Map subject_id back to our entries_ to get identity info
    for (const auto& e : entries_) {
        if (e.template_id == best_result->subject_id) {
            bool is_match = best_result->distance < threshold;
            return GalleryMatch{
                .hamming_distance = best_result->distance,
                .is_match = is_match,
                .best_rotation = 0,
                .matched_identity_id = e.identity_id,
                .matched_identity_name = e.identity_name,
                .matched_template_id = e.template_id,
            };
        }
    }

    // subject_id not found in local entries (shouldn't happen)
    return std::nullopt;
}

std::vector<Gallery::IdentityInfo> Gallery::list() const {
    std::lock_guard lock(mutex_);

    // Group templates by identity
    std::map<std::string, IdentityInfo> by_identity;
    for (const auto& e : entries_) {
        auto& info = by_identity[e.identity_id];
        info.identity_id = e.identity_id;
        info.name = e.identity_name;
        info.templates.push_back({e.template_id, e.eye_side});
    }

    std::vector<IdentityInfo> result;
    result.reserve(by_identity.size());
    for (auto& [_, info] : by_identity) {
        result.push_back(std::move(info));
    }
    return result;
}
