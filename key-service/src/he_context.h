#pragma once

/**
 * @file he_context.h
 * @brief OpenFHE BFV context management for the key-service.
 *
 * The key-service holds the BFV secret key and is responsible for:
 *   1. Generating keypairs (context, public/secret/eval keys)
 *   2. Decrypting match results (inner product ciphertexts → integers)
 *   3. Decrypting templates for admin visualization
 *
 * BFV Parameters (must match iris-engine's he_context.py):
 *   - Plaintext modulus t = 65537
 *   - Multiplicative depth = 1
 *   - Security level = 128-bit (HEStd_128_classic)
 *   - Ring dimension N = auto (expected 8192 or 16384)
 */

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

#include "openfhe.h"

namespace eyed {

// BFV constants — must match iris-engine/src/he_context.py
constexpr uint64_t kPlaintextModulus = 65537;
constexpr uint32_t kMultDepth = 1;
constexpr uint32_t kIrisCodeSlots = 8192;  // 16 × 256 × 2
constexpr uint32_t kRotateSumIters = 13;   // ceil(log2(8192))

/**
 * Initialize the BFV crypto context.
 *
 * If key_dir contains existing keys (secret.key, public.key, etc.),
 * loads them. Otherwise, generates a fresh keypair and saves to key_dir.
 *
 * @param key_dir  Directory for key storage.
 * @return true on success, false on failure.
 */
bool InitContext(const std::filesystem::path& key_dir);

/**
 * Decrypt a single ciphertext and return all slot values.
 *
 * @param ct_bytes  Serialized ciphertext (binary format from openfhe.SerializeToFile).
 * @return Vector of plaintext slot values (length = ring dimension).
 */
std::vector<int64_t> DecryptToVector(const std::vector<uint8_t>& ct_bytes);

/**
 * Decrypt a single ciphertext and return only slot 0 (scalar inner product).
 *
 * @param ct_bytes  Serialized ciphertext.
 * @return The integer value in slot 0.
 */
int64_t DecryptScalar(const std::vector<uint8_t>& ct_bytes);

/**
 * Get the current ring dimension.
 */
uint32_t GetRingDimension();

/**
 * Check if the context is initialized and ready.
 */
bool IsReady();

}  // namespace eyed
