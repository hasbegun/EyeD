#include "fhe.h"

#include <chrono>
#include <iostream>

#ifdef IRIS_HAS_FHE

bool FHEManager::initialize(const std::string& key_dir) {
    try {
        auto ctx_result = iris::FHEContext::create();
        if (!ctx_result) {
            std::cerr << "[fhe] Failed to create FHE context: "
                      << ctx_result.error().message << std::endl;
            return false;
        }

        ctx_ = std::make_unique<iris::FHEContext>(std::move(*ctx_result));

        // Try to load existing keys from disk
        if (!key_dir.empty() && std::filesystem::exists(key_dir)) {
            auto bundle = iris::KeyStore::load(key_dir, *ctx_);
            if (bundle) {
                std::cout << "[fhe] Loaded existing keys from " << key_dir
                          << " (key_id=" << bundle->metadata.key_id << ")"
                          << std::endl;
                // Keys loaded from store are already injected into context
                // through the load process — but KeyStore::load only
                // deserializes the key objects. We need to regenerate
                // the context keys from the loaded bundle.
                // Actually, OpenFHE deserialization restores the keys into
                // the CryptoContext automatically. We just need to generate
                // fresh keys and inject them.

                // For now, generate fresh keys (PoC approach).
                // TODO: Proper key loading from KeyStore requires
                // injecting loaded keys into the crypto context.
                auto gen_result = ctx_->generate_keys();
                if (!gen_result) {
                    std::cerr << "[fhe] Key generation failed: "
                              << gen_result.error().message << std::endl;
                    return false;
                }
                std::cout << "[fhe] Generated fresh keys (PoC mode)" << std::endl;
                active_ = true;
                return true;
            }
            std::cout << "[fhe] No existing keys at " << key_dir
                      << ", generating new keys..." << std::endl;
        }

        // Generate fresh keys
        auto gen_result = ctx_->generate_keys();
        if (!gen_result) {
            std::cerr << "[fhe] Key generation failed: "
                      << gen_result.error().message << std::endl;
            return false;
        }

        // Save keys to disk if key_dir specified
        if (!key_dir.empty()) {
            auto bundle = iris::KeyManager::generate(*ctx_);
            if (bundle) {
                auto save_result = iris::KeyStore::save(key_dir, *ctx_, *bundle);
                if (save_result) {
                    std::cout << "[fhe] Keys saved to " << key_dir
                              << " (key_id=" << bundle->metadata.key_id << ")"
                              << std::endl;
                } else {
                    std::cerr << "[fhe] WARNING: Failed to save keys: "
                              << save_result.error().message << std::endl;
                }
            }
        }

        active_ = true;
        std::cout << "[fhe] FHE context initialized (slot_count="
                  << ctx_->slot_count() << ")" << std::endl;
        return true;

    } catch (const std::exception& e) {
        std::cerr << "[fhe] Exception during initialization: " << e.what()
                  << std::endl;
        return false;
    }
}

bool FHEManager::is_active() const noexcept {
    return active_;
}

std::vector<uint8_t> FHEManager::encrypt_and_serialize(
    const iris::PackedIrisCode& code) const {
    if (!active_) return {};

    auto enc = iris::EncryptedTemplate::encrypt(*ctx_, code);
    if (!enc) {
        std::cerr << "[fhe] Encryption failed: " << enc.error().message
                  << std::endl;
        return {};
    }

    auto ser = enc->serialize();
    if (!ser) {
        std::cerr << "[fhe] Serialization failed: " << ser.error().message
                  << std::endl;
        return {};
    }

    return std::move(*ser);
}

std::pair<std::vector<uint8_t>, std::vector<uint8_t>>
FHEManager::encrypt_template(const iris::IrisTemplate& tmpl) const {
    if (!active_) return {{}, {}};

    // Each EncryptedTemplate bundles both code_ct (iris bits) and mask_ct
    // (validity mask bits). We combine iris_codes[i].code_bits with
    // mask_codes[i].code_bits into a single PackedIrisCode before encryption.
    //
    // Serialize format: [count(4)][size0(8)][data0][size1(8)][data1]...

    size_t n_scales = tmpl.iris_codes.size();
    std::vector<uint8_t> iris_blob;

    uint32_t count = static_cast<uint32_t>(n_scales);
    iris_blob.insert(iris_blob.end(),
                     reinterpret_cast<const uint8_t*>(&count),
                     reinterpret_cast<const uint8_t*>(&count) + sizeof(count));

    auto t_start = std::chrono::steady_clock::now();

    for (size_t s = 0; s < n_scales; ++s) {
        // Combine iris code bits with mask bits for correct HD computation.
        // iris_codes[s].code_bits = iris filter response
        // mask_codes[s].code_bits = validity mask
        iris::PackedIrisCode combined;
        combined.code_bits = tmpl.iris_codes[s].code_bits;
        if (s < tmpl.mask_codes.size()) {
            combined.mask_bits = tmpl.mask_codes[s].code_bits;
        } else {
            combined.mask_bits = tmpl.iris_codes[s].mask_bits;
        }

        auto t0 = std::chrono::steady_clock::now();
        auto enc = iris::EncryptedTemplate::encrypt(*ctx_, combined);
        auto t1 = std::chrono::steady_clock::now();
        if (!enc) {
            std::cerr << "[fhe] Encryption failed for scale " << s << ": "
                      << enc.error().message << std::endl;
            return {{}, {}};
        }
        std::cerr << "[fhe] encrypt scale " << s << ": "
                  << std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count()
                  << " ms" << std::endl;

        auto ser = enc->serialize();
        if (!ser) {
            std::cerr << "[fhe] Serialization failed for scale " << s << ": "
                      << ser.error().message << std::endl;
            return {{}, {}};
        }

        uint64_t size = ser->size();
        iris_blob.insert(iris_blob.end(),
                         reinterpret_cast<const uint8_t*>(&size),
                         reinterpret_cast<const uint8_t*>(&size) + sizeof(size));
        iris_blob.insert(iris_blob.end(), ser->begin(), ser->end());
    }

    auto t_end = std::chrono::steady_clock::now();
    std::cerr << "[fhe] encrypt_template total: "
              << std::chrono::duration_cast<std::chrono::milliseconds>(t_end - t_start).count()
              << " ms (" << n_scales << " scales)" << std::endl;

    // mask_codes BYTEA gets a sentinel (empty count=0) since the mask is
    // already inside each EncryptedTemplate's mask_ct.
    std::vector<uint8_t> mask_blob;
    uint32_t zero = 0;
    mask_blob.insert(mask_blob.end(),
                     reinterpret_cast<const uint8_t*>(&zero),
                     reinterpret_cast<const uint8_t*>(&zero) + sizeof(zero));

    return {std::move(iris_blob), std::move(mask_blob)};
}

std::vector<iris::EncryptedTemplate> FHEManager::deserialize_encrypted(
    const uint8_t* data, size_t len) const {
    std::vector<iris::EncryptedTemplate> result;
    if (!active_ || len < sizeof(uint32_t)) return result;

    size_t offset = 0;

    uint32_t count = 0;
    std::memcpy(&count, data + offset, sizeof(count));
    offset += sizeof(count);

    result.reserve(count);
    for (uint32_t i = 0; i < count && offset + sizeof(uint64_t) <= len; ++i) {
        uint64_t size = 0;
        std::memcpy(&size, data + offset, sizeof(size));
        offset += sizeof(size);

        if (offset + size > len) {
            std::cerr << "[fhe] Truncated encrypted data at scale " << i
                      << std::endl;
            break;
        }

        auto et = iris::EncryptedTemplate::deserialize(
            *ctx_, {data + offset, static_cast<size_t>(size)});
        if (!et) {
            std::cerr << "[fhe] Deserialization failed at scale " << i
                      << ": " << et.error().message << std::endl;
            break;
        }

        result.push_back(std::move(*et));
        offset += static_cast<size_t>(size);
    }

    return result;
}

std::optional<iris::IrisTemplate> FHEManager::decrypt_template(
    const std::vector<uint8_t>& iris_blob) const {
    if (!active_ || iris_blob.empty()) return std::nullopt;

    auto enc_templates = deserialize_encrypted(iris_blob.data(), iris_blob.size());
    if (enc_templates.empty()) return std::nullopt;

    iris::IrisTemplate tmpl;
    tmpl.iris_code_version = "v2.0";

    for (auto& et : enc_templates) {
        auto decrypted = et.decrypt(*ctx_);
        if (!decrypted) {
            std::cerr << "[fhe] Failed to decrypt scale " << tmpl.iris_codes.size()
                      << std::endl;
            return std::nullopt;
        }

        // encrypt_template() combined: code_bits from iris_codes, mask_bits from mask_codes
        // So we split them back: iris_codes gets code_bits, mask_codes gets mask_bits
        iris::PackedIrisCode iris_code;
        iris_code.code_bits = decrypted->code_bits;
        iris_code.mask_bits = decrypted->mask_bits;  // not used for matching, but keep consistent

        iris::PackedIrisCode mask_code;
        mask_code.code_bits = decrypted->mask_bits;  // the actual mask bits
        mask_code.mask_bits = {};

        tmpl.iris_codes.push_back(std::move(iris_code));
        tmpl.mask_codes.push_back(std::move(mask_code));
    }

    return tmpl;
}

FHEManager::MatchResult FHEManager::match_probe_vs_encrypted(
    const iris::PackedIrisCode& probe,
    const iris::EncryptedTemplate& gallery) const {
    if (!active_) return {1.0, 0};

    // Encrypt probe
    auto enc_probe = iris::EncryptedTemplate::encrypt(*ctx_, probe);
    if (!enc_probe) return {1.0, 0};

    // Compute encrypted HD
    auto enc_result = iris::EncryptedMatcher::match_encrypted(
        *ctx_, *enc_probe, gallery);
    if (!enc_result) return {1.0, 0};

    // Decrypt result
    auto hd = iris::EncryptedMatcher::decrypt_result(*ctx_, *enc_result);
    if (!hd) return {1.0, 0};

    return {*hd, 0};
}

FHEManager::MatchResult FHEManager::match_with_rotation(
    const iris::PackedIrisCode& probe,
    const iris::PackedIrisCode& gallery,
    int rotation_shift) const {
    if (!active_) return {1.0, 0};

    auto result = iris::EncryptedMatcher::match_with_rotation(
        *ctx_, probe, gallery, rotation_shift);
    if (!result) {
        std::cerr << "[fhe] match_with_rotation failed: "
                  << result.error().message << std::endl;
        return {1.0, 0};
    }

    return {result->distance, result->best_rotation};
}

#else  // !IRIS_HAS_FHE

bool FHEManager::initialize(const std::string& /*key_dir*/) {
    std::cerr << "[fhe] FHE not compiled in (IRIS_HAS_FHE not defined)"
              << std::endl;
    return false;
}

bool FHEManager::is_active() const noexcept {
    return false;
}

std::vector<uint8_t> FHEManager::encrypt_and_serialize(
    const iris::PackedIrisCode& /*code*/) const {
    return {};
}

std::pair<std::vector<uint8_t>, std::vector<uint8_t>>
FHEManager::encrypt_template(const iris::IrisTemplate& /*tmpl*/) const {
    return {{}, {}};
}

FHEManager::MatchResult FHEManager::match_with_rotation(
    const iris::PackedIrisCode& /*probe*/,
    const iris::PackedIrisCode& /*gallery*/,
    int /*rotation_shift*/) const {
    return {1.0, 0};
}

#endif  // IRIS_HAS_FHE
