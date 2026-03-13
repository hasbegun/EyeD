#pragma once

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>

#ifdef IRIS_HAS_FHE
#include <iris/crypto/encrypted_matcher.hpp>
#include <iris/crypto/encrypted_template.hpp>
#include <iris/crypto/fhe_context.hpp>
#include <iris/crypto/key_manager.hpp>
#include <iris/crypto/key_store.hpp>
#endif

/// FHE manager for iris-engine2.
///
/// Handles context initialization, key generation/loading, and provides
/// high-level encrypt/match/serialize operations used by the service layer.
///
/// When FHE is not compiled in (IRIS_HAS_FHE not defined), all methods
/// are no-ops or return errors so the rest of the code compiles cleanly.
class FHEManager {
  public:
    /// Initialize the FHE context and keys.
    /// If key_dir is non-empty and contains existing keys, loads them.
    /// Otherwise generates fresh keys and saves to key_dir (if non-empty).
    bool initialize(const std::string& key_dir = "");

    /// Whether FHE is compiled in AND successfully initialized.
    [[nodiscard]] bool is_active() const noexcept;

    // --- Template encryption ---

    /// Encrypt a single PackedIrisCode into serialized bytes for DB storage.
    /// Returns empty vector on failure.
    std::vector<uint8_t> encrypt_and_serialize(
        const iris::PackedIrisCode& code) const;

    /// Encrypt all scales of an IrisTemplate.
    /// Returns pair of (encrypted_blob, empty_mask_blob).
    /// Each EncryptedTemplate already contains both code_ct and mask_ct,
    /// so the entire serialized data goes into the iris_codes BYTEA column
    /// and mask_codes gets an empty sentinel.
    std::pair<std::vector<uint8_t>, std::vector<uint8_t>>
    encrypt_template(const iris::IrisTemplate& tmpl) const;

    /// Deserialize encrypted codes from DB BYTEA back to EncryptedTemplate objects.
    /// Each blob contains N serialized EncryptedTemplates concatenated with
    /// a length prefix: [count(4)][size0(8)][data0][size1(8)][data1]...
#ifdef IRIS_HAS_FHE
    std::vector<iris::EncryptedTemplate> deserialize_encrypted(
        const uint8_t* data, size_t len) const;
#endif

    // --- Matching ---

    /// Match a probe IrisTemplate against a single gallery EncryptedTemplate.
    /// Encrypts the probe, runs encrypted HD, decrypts result.
    /// Returns (hamming_distance, best_rotation) or (1.0, 0) on failure.
    struct MatchResult {
        double distance = 1.0;
        int best_rotation = 0;
    };

#ifdef IRIS_HAS_FHE
    MatchResult match_probe_vs_encrypted(
        const iris::PackedIrisCode& probe,
        const iris::EncryptedTemplate& gallery) const;
#endif

    /// Match a probe code against a gallery code using encrypted HD with rotation.
    /// This is the full pipeline: encrypt probe, encrypt gallery, compute HD.
    MatchResult match_with_rotation(
        const iris::PackedIrisCode& probe,
        const iris::PackedIrisCode& gallery,
        int rotation_shift = 15) const;

#ifdef IRIS_HAS_FHE
    [[nodiscard]] const iris::FHEContext& context() const { return *ctx_; }
#endif

  private:
#ifdef IRIS_HAS_FHE
    std::unique_ptr<iris::FHEContext> ctx_;
#endif
    bool active_ = false;
};
