#include "he_context.h"

#include <fstream>
#include <iostream>
#include <sstream>

// OpenFHE headers
#include "openfhe.h"

// Serialization headers — register BFV polymorphic types with cereal
#include "ciphertext-ser.h"
#include "cryptocontext-ser.h"
#include "key/key-ser.h"
#include "scheme/bfvrns/bfvrns-ser.h"

using namespace lbcrypto;

namespace eyed {

namespace {

CryptoContext<DCRTPoly> g_context = nullptr;
PrivateKey<DCRTPoly> g_secret_key = nullptr;
PublicKey<DCRTPoly> g_public_key = nullptr;
bool g_initialized = false;

bool KeysExist(const std::filesystem::path& key_dir) {
    return std::filesystem::exists(key_dir / "cryptocontext.bin") &&
           std::filesystem::exists(key_dir / "secret.key") &&
           std::filesystem::exists(key_dir / "public.key");
}

bool GenerateAndSaveKeys(const std::filesystem::path& key_dir) {
    // Create BFV context with parameters matching iris-engine
    CCParams<CryptoContextBFVRNS> params;
    params.SetPlaintextModulus(kPlaintextModulus);
    params.SetMultiplicativeDepth(kMultDepth);
    params.SetSecurityLevel(HEStd_128_classic);

    g_context = GenCryptoContext(params);
    g_context->Enable(PKE);
    g_context->Enable(KEYSWITCH);
    g_context->Enable(LEVELEDSHE);

    auto ring_dim = g_context->GetRingDimension();
    std::cout << "[key-service] BFV context: t=" << kPlaintextModulus
              << " depth=" << kMultDepth
              << " ring_dim=" << ring_dim << std::endl;

    if (ring_dim < kIrisCodeSlots) {
        std::cerr << "[key-service] ERROR: ring_dim " << ring_dim
                  << " < " << kIrisCodeSlots << " required slots" << std::endl;
        return false;
    }

    // Generate keypair
    auto keypair = g_context->KeyGen();
    g_secret_key = keypair.secretKey;
    g_public_key = keypair.publicKey;

    // Generate eval keys for multiplication
    g_context->EvalMultKeyGen(g_secret_key);

    // Generate rotation keys for rotate-and-sum
    std::vector<int32_t> rotation_indices;
    for (uint32_t i = 0; i < kRotateSumIters; ++i) {
        rotation_indices.push_back(1 << i);
    }
    g_context->EvalRotateKeyGen(g_secret_key, rotation_indices);

    // Save keys to disk
    std::filesystem::create_directories(key_dir);

    if (!Serial::SerializeToFile(
            (key_dir / "cryptocontext.bin").string(), g_context, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to serialize crypto context" << std::endl;
        return false;
    }

    if (!Serial::SerializeToFile(
            (key_dir / "public.key").string(), g_public_key, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to serialize public key" << std::endl;
        return false;
    }

    if (!Serial::SerializeToFile(
            (key_dir / "secret.key").string(), g_secret_key, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to serialize secret key" << std::endl;
        return false;
    }

    // Save eval mult key
    std::ofstream emk_file((key_dir / "eval_mult.key").string(), std::ios::binary);
    if (!emk_file.is_open() ||
        !g_context->SerializeEvalMultKey(emk_file, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to serialize eval mult key" << std::endl;
        return false;
    }
    emk_file.close();

    // Save eval rotation key
    std::ofstream erk_file((key_dir / "eval_rotate.key").string(), std::ios::binary);
    if (!erk_file.is_open() ||
        !g_context->SerializeEvalAutomorphismKey(erk_file, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to serialize eval rotate key" << std::endl;
        return false;
    }
    erk_file.close();

    std::cout << "[key-service] Generated and saved keys to " << key_dir << std::endl;
    return true;
}

bool LoadKeysFromDir(const std::filesystem::path& key_dir) {
    // Load crypto context
    if (!Serial::DeserializeFromFile(
            (key_dir / "cryptocontext.bin").string(), g_context, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to load crypto context" << std::endl;
        return false;
    }

    g_context->Enable(PKE);
    g_context->Enable(KEYSWITCH);
    g_context->Enable(LEVELEDSHE);

    // Load secret key
    if (!Serial::DeserializeFromFile(
            (key_dir / "secret.key").string(), g_secret_key, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to load secret key" << std::endl;
        return false;
    }

    // Load public key
    if (!Serial::DeserializeFromFile(
            (key_dir / "public.key").string(), g_public_key, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to load public key" << std::endl;
        return false;
    }

    // Load eval mult key
    std::ifstream emk_file((key_dir / "eval_mult.key").string(), std::ios::binary);
    if (!emk_file.is_open() ||
        !g_context->DeserializeEvalMultKey(emk_file, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to load eval mult key" << std::endl;
        return false;
    }
    emk_file.close();

    // Load eval rotation key
    std::ifstream erk_file((key_dir / "eval_rotate.key").string(), std::ios::binary);
    if (!erk_file.is_open() ||
        !g_context->DeserializeEvalAutomorphismKey(erk_file, SerType::BINARY)) {
        std::cerr << "[key-service] Failed to load eval rotate key" << std::endl;
        return false;
    }
    erk_file.close();

    auto ring_dim = g_context->GetRingDimension();
    std::cout << "[key-service] Loaded keys from " << key_dir
              << " (ring_dim=" << ring_dim << ")" << std::endl;
    return true;
}

Ciphertext<DCRTPoly> DeserializeCiphertext(const std::vector<uint8_t>& ct_bytes) {
    // Write to temp file, deserialize
    auto tmp_path = std::filesystem::temp_directory_path() / "eyed_ct_tmp.bin";
    {
        std::ofstream out(tmp_path.string(), std::ios::binary);
        out.write(reinterpret_cast<const char*>(ct_bytes.data()), ct_bytes.size());
    }

    Ciphertext<DCRTPoly> ct;
    if (!Serial::DeserializeFromFile(tmp_path.string(), ct, SerType::BINARY)) {
        std::filesystem::remove(tmp_path);
        throw std::runtime_error("Failed to deserialize ciphertext");
    }

    std::filesystem::remove(tmp_path);
    return ct;
}

}  // anonymous namespace

bool InitContext(const std::filesystem::path& key_dir) {
    if (g_initialized) {
        return true;
    }

    bool ok;
    if (KeysExist(key_dir)) {
        std::cout << "[key-service] Loading existing keys from " << key_dir << std::endl;
        ok = LoadKeysFromDir(key_dir);
    } else {
        std::cout << "[key-service] Generating new keypair..." << std::endl;
        ok = GenerateAndSaveKeys(key_dir);
    }

    if (ok) {
        g_initialized = true;
    }
    return ok;
}

std::vector<int64_t> DecryptToVector(const std::vector<uint8_t>& ct_bytes) {
    if (!g_initialized) {
        throw std::runtime_error("HE context not initialized");
    }

    auto ct = DeserializeCiphertext(ct_bytes);
    Plaintext pt;
    g_context->Decrypt(g_secret_key, ct, &pt);

    pt->SetLength(kIrisCodeSlots);
    auto packed = pt->GetPackedValue();

    std::vector<int64_t> result(packed.begin(), packed.end());
    return result;
}

int64_t DecryptScalar(const std::vector<uint8_t>& ct_bytes) {
    if (!g_initialized) {
        throw std::runtime_error("HE context not initialized");
    }

    auto ct = DeserializeCiphertext(ct_bytes);
    Plaintext pt;
    g_context->Decrypt(g_secret_key, ct, &pt);

    pt->SetLength(1);
    return static_cast<int64_t>(pt->GetPackedValue()[0]);
}

uint32_t GetRingDimension() {
    if (!g_initialized) return 0;
    return g_context->GetRingDimension();
}

bool IsReady() {
    return g_initialized;
}

}  // namespace eyed
