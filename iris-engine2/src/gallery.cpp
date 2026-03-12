#include "gallery.h"

#include <algorithm>
#include <map>

Gallery::Gallery(double match_threshold, double dedup_threshold)
    : match_threshold_(match_threshold), dedup_threshold_(dedup_threshold) {}

void Gallery::add(GalleryEntry entry) {
    std::lock_guard lock(mutex_);
    entries_.push_back(std::move(entry));
}

int Gallery::remove(const std::string& identity_id) {
    std::lock_guard lock(mutex_);
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
