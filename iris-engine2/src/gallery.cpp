#include "gallery.h"
#include "fhe.h"

#include <algorithm>
#include <iostream>
#include <map>

#ifdef IRIS_HAS_FHE
#include <iris/crypto/encrypted_matcher.hpp>
#include <iris/crypto/encrypted_template.hpp>
#endif

Gallery::Gallery(double match_threshold, double dedup_threshold,
                 FHEManager* fhe)
    : match_threshold_(match_threshold),
      dedup_threshold_(dedup_threshold),
      fhe_(fhe) {}

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

#ifdef IRIS_HAS_FHE
    // If any entry is encrypted, use encrypted matching path
    bool has_encrypted = std::any_of(entries_.begin(), entries_.end(),
                                      [](const GalleryEntry& e) { return e.is_encrypted; });
    if (has_encrypted && fhe_ && fhe_->is_active()) {
        return find_best_match_encrypted(probe, threshold);
    }
#endif

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

#ifdef IRIS_HAS_FHE
std::optional<GalleryMatch> Gallery::find_best_match_encrypted(
    const iris::IrisTemplate& probe, double threshold) const {
    // Caller must hold mutex_
    if (entries_.empty() || !fhe_ || !fhe_->is_active()) return std::nullopt;

    const auto& ctx = fhe_->context();

    double best_dist = 1.0;
    size_t best_idx = 0;
    int best_rot = 0;

    for (size_t i = 0; i < entries_.size(); ++i) {
        const auto& entry = entries_[i];
        if (!entry.is_encrypted || entry.encrypted_iris.empty()) continue;

        // For each scale, compute encrypted HD and take the minimum
        double entry_best_dist = 1.0;
        int entry_best_rot = 0;

        for (size_t s = 0; s < entry.encrypted_iris.size(); ++s) {
            const auto& gallery_enc = entry.encrypted_iris[s];
            if (s >= probe.iris_codes.size()) break;

            // Combine probe iris code bits with mask bits, matching
            // the way encrypt_template() combines them for gallery.
            iris::PackedIrisCode probe_combined;
            probe_combined.code_bits = probe.iris_codes[s].code_bits;
            if (s < probe.mask_codes.size()) {
                probe_combined.mask_bits = probe.mask_codes[s].code_bits;
            } else {
                probe_combined.mask_bits = probe.iris_codes[s].mask_bits;
            }

            constexpr int kRotationShift = 15;

            for (int abs_shift = 0; abs_shift <= kRotationShift; ++abs_shift) {
                for (int sign : {1, -1}) {
                    if (abs_shift == 0 && sign == -1) continue;
                    const int shift = abs_shift * sign;

                    auto rotated_probe = probe_combined.rotate(shift);

                    // Encrypt rotated probe
                    auto enc_probe = iris::EncryptedTemplate::encrypt(ctx, rotated_probe);
                    if (!enc_probe) continue;

                    // Encrypted match
                    auto enc_result = iris::EncryptedMatcher::match_encrypted(
                        ctx, *enc_probe, gallery_enc);
                    if (!enc_result) continue;

                    // Decrypt only the HD result (NOT the iris data)
                    auto hd = iris::EncryptedMatcher::decrypt_result(ctx, *enc_result);
                    if (!hd) continue;

                    if (*hd < entry_best_dist) {
                        entry_best_dist = *hd;
                        entry_best_rot = shift;
                    }
                }
            }
        }

        if (entry_best_dist < best_dist) {
            best_dist = entry_best_dist;
            best_idx = i;
            best_rot = entry_best_rot;
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
#endif

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
