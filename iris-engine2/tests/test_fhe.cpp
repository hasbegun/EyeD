#include "fhe.h"

#include <doctest/doctest.h>
#include <cstring>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>

// Helper to create a PackedIrisCode with deterministic bit pattern
static iris::PackedIrisCode make_test_code(uint64_t seed) {
    iris::PackedIrisCode code;
    for (size_t i = 0; i < iris::PackedIrisCode::kNumWords; ++i) {
        code.code_bits[i] = seed ^ (i * 0x9E3779B97F4A7C15ULL);
        code.mask_bits[i] = ~0ULL;  // all bits valid
    }
    return code;
}

// Helper to create a test IrisTemplate with N scales
static iris::IrisTemplate make_test_template(uint64_t seed, int n_scales = 2) {
    iris::IrisTemplate tmpl;
    for (int i = 0; i < n_scales; ++i) {
        tmpl.iris_codes.push_back(make_test_code(seed + static_cast<uint64_t>(i)));
        tmpl.mask_codes.push_back(make_test_code(seed + 1000 + static_cast<uint64_t>(i)));
    }
    tmpl.iris_code_version = "v2.0";
    return tmpl;
}

#ifdef IRIS_HAS_FHE

TEST_CASE("FHEManager initialization") {
    FHEManager fhe;
    CHECK_FALSE(fhe.is_active());

    bool ok = fhe.initialize();
    CHECK(ok);
    CHECK(fhe.is_active());
}

TEST_CASE("FHEManager initialization with key directory") {
    FHEManager fhe;
    // Use a temp directory for keys
    auto temp_dir = std::filesystem::temp_directory_path() / "test_fhe_keys";
    std::filesystem::remove_all(temp_dir);

    bool ok = fhe.initialize(temp_dir.string());
    CHECK(ok);
    CHECK(fhe.is_active());

    // Verify key files were created
    CHECK(std::filesystem::exists(temp_dir / "public_key.bin"));
    CHECK(std::filesystem::exists(temp_dir / "secret_key.bin"));
    CHECK(std::filesystem::exists(temp_dir / "key_meta.json"));

    // Cleanup
    std::filesystem::remove_all(temp_dir);
}

TEST_CASE("FHEManager encrypt and serialize single code") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    auto code = make_test_code(42);
    auto serialized = fhe.encrypt_and_serialize(code);

    CHECK_FALSE(serialized.empty());
    // Serialized ciphertext should be much larger than the raw code
    CHECK(serialized.size() > sizeof(iris::PackedIrisCode));
}

TEST_CASE("FHEManager encrypt template - round trip structure") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    auto tmpl = make_test_template(42, 2);
    auto [iris_blob, mask_blob] = fhe.encrypt_template(tmpl);

    CHECK_FALSE(iris_blob.empty());
    CHECK_FALSE(mask_blob.empty());

    // Verify we can deserialize the iris blob back to EncryptedTemplate objects.
    // mask_blob is a sentinel (count=0) since the mask is inside each EncryptedTemplate.
    auto iris_ets = fhe.deserialize_encrypted(iris_blob.data(), iris_blob.size());
    auto mask_ets = fhe.deserialize_encrypted(mask_blob.data(), mask_blob.size());

    CHECK(iris_ets.size() == 2);  // 2 scales
    CHECK(mask_ets.size() == 0);  // sentinel — mask is inside each EncryptedTemplate
}

TEST_CASE("FHEManager encrypted matching - same code produces HD ≈ 0") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    auto code = make_test_code(42);

    // Match a code against itself (encrypted) — should give HD ≈ 0
    auto result = fhe.match_probe_vs_encrypted(
        code, *iris::EncryptedTemplate::encrypt(fhe.context(), code));

    CHECK(result.distance < 0.01);  // Should be very close to 0
}

TEST_CASE("FHEManager encrypted matching - different codes produce HD > 0") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    // Use maximally different codes: all-zeros vs all-ones
    iris::PackedIrisCode code_a;
    code_a.code_bits.fill(0x0000000000000000ULL);
    code_a.mask_bits.fill(~0ULL);

    iris::PackedIrisCode code_b;
    code_b.code_bits.fill(0xFFFFFFFFFFFFFFFFULL);
    code_b.mask_bits.fill(~0ULL);

    auto enc_b = iris::EncryptedTemplate::encrypt(fhe.context(), code_b);
    REQUIRE(enc_b.has_value());

    auto result = fhe.match_probe_vs_encrypted(code_a, *enc_b);

    // Maximally different codes: HD should be close to 0.5
    CHECK(result.distance > 0.3);
}

TEST_CASE("FHEManager match_with_rotation - same code") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    auto code = make_test_code(42);

    auto result = fhe.match_with_rotation(code, code, 3);
    CHECK(result.distance < 0.01);
    CHECK(result.best_rotation == 0);
}

TEST_CASE("FHEManager not initialized - encrypt returns empty") {
    FHEManager fhe;
    // Not initialized

    auto code = make_test_code(42);
    auto serialized = fhe.encrypt_and_serialize(code);
    CHECK(serialized.empty());
}

TEST_CASE("FHEManager not initialized - encrypt_template returns empty") {
    FHEManager fhe;

    auto tmpl = make_test_template(42);
    auto [iris_blob, mask_blob] = fhe.encrypt_template(tmpl);
    CHECK(iris_blob.empty());
    CHECK(mask_blob.empty());
}

TEST_CASE("FHEManager encrypt-decrypt roundtrip preserves bits") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    auto original = make_test_code(42);

    // Encrypt
    auto enc = iris::EncryptedTemplate::encrypt(fhe.context(), original);
    REQUIRE(enc.has_value());

    // Decrypt
    auto decrypted = enc->decrypt(fhe.context());
    REQUIRE(decrypted.has_value());

    // Compare bits
    CHECK(original.code_bits == decrypted->code_bits);
    CHECK(original.mask_bits == decrypted->mask_bits);
}

TEST_CASE("FHEManager serialize-deserialize roundtrip") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    auto original = make_test_code(42);

    // Encrypt
    auto enc = iris::EncryptedTemplate::encrypt(fhe.context(), original);
    REQUIRE(enc.has_value());

    // Serialize
    auto ser = enc->serialize();
    REQUIRE(ser.has_value());

    // Deserialize
    auto dec = iris::EncryptedTemplate::deserialize(
        fhe.context(), {ser->data(), ser->size()});
    REQUIRE(dec.has_value());

    // Decrypt and compare
    auto decrypted = dec->decrypt(fhe.context());
    REQUIRE(decrypted.has_value());

    CHECK(original.code_bits == decrypted->code_bits);
    CHECK(original.mask_bits == decrypted->mask_bits);
}

TEST_CASE("FHEManager multi-scale encrypt-deserialize roundtrip") {
    FHEManager fhe;
    REQUIRE(fhe.initialize());

    auto tmpl = make_test_template(123, 2);
    auto [iris_blob, mask_blob] = fhe.encrypt_template(tmpl);

    REQUIRE_FALSE(iris_blob.empty());
    REQUIRE_FALSE(mask_blob.empty());

    // Deserialize
    auto iris_ets = fhe.deserialize_encrypted(iris_blob.data(), iris_blob.size());
    CHECK(iris_ets.size() == 2);

    // Decrypt each scale and verify bits match original.
    // encrypt_template combines: code_bits from iris_codes[i], mask_bits from mask_codes[i].code_bits
    for (size_t i = 0; i < iris_ets.size(); ++i) {
        auto decrypted = iris_ets[i].decrypt(fhe.context());
        REQUIRE(decrypted.has_value());
        CHECK(tmpl.iris_codes[i].code_bits == decrypted->code_bits);
        CHECK(tmpl.mask_codes[i].code_bits == decrypted->mask_bits);
    }
}

#else  // !IRIS_HAS_FHE

TEST_CASE("FHEManager without FHE compiled - initialize fails") {
    FHEManager fhe;
    CHECK_FALSE(fhe.initialize());
    CHECK_FALSE(fhe.is_active());
}

TEST_CASE("FHEManager without FHE compiled - operations return empty") {
    FHEManager fhe;
    auto code = make_test_code(42);
    CHECK(fhe.encrypt_and_serialize(code).empty());

    auto tmpl = make_test_template(42);
    auto [iris_blob, mask_blob] = fhe.encrypt_template(tmpl);
    CHECK(iris_blob.empty());
    CHECK(mask_blob.empty());
}

#endif  // IRIS_HAS_FHE
