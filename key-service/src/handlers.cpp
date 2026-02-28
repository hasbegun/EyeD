#include "handlers.h"
#include "he_context.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

// Base64 decode (minimal implementation for NATS payloads)
namespace {

static const std::string kBase64Chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::vector<uint8_t> Base64Decode(const std::string& encoded) {
    std::vector<uint8_t> result;
    int val = 0, bits = -8;
    for (unsigned char c : encoded) {
        if (c == '=' || c == '\n' || c == '\r') continue;
        auto pos = kBase64Chars.find(c);
        if (pos == std::string::npos) continue;
        val = (val << 6) + static_cast<int>(pos);
        bits += 6;
        if (bits >= 0) {
            result.push_back(static_cast<uint8_t>((val >> bits) & 0xFF));
            bits -= 8;
        }
    }
    return result;
}

std::string Base64Encode(const std::vector<uint8_t>& data) {
    std::string result;
    int val = 0, bits = -6;
    for (uint8_t c : data) {
        val = (val << 8) + c;
        bits += 8;
        while (bits >= 0) {
            result.push_back(kBase64Chars[(val >> bits) & 0x3F]);
            bits -= 6;
        }
    }
    if (bits > -6) {
        result.push_back(kBase64Chars[(val << (-bits)) & 0x3F]);
    }
    while (result.size() % 4) {
        result.push_back('=');
    }
    return result;
}

void SendReply(natsConnection* nc, natsMsg* msg, const nlohmann::json& response) {
    auto reply = natsMsg_GetReply(msg);
    if (reply) {
        auto body = response.dump();
        natsConnection_Publish(nc, reply, body.c_str(), static_cast<int>(body.size()));
    }
}

void SendError(natsConnection* nc, natsMsg* msg, const std::string& error) {
    nlohmann::json resp;
    resp["error"] = error;
    SendReply(nc, msg, resp);
}

/**
 * Compute fractional Hamming distance for one iris code pair.
 *
 * HD(a, b) = popcount(a XOR b) / popcount(combined_mask)
 *          = (pop_a + pop_b - 2 * inner_product) / (mask_pop_a + mask_pop_b - 2 * mask_ip)
 *
 * Wait — that formula isn't quite right for masked HD. Let me be precise:
 *
 * For unmasked HD:
 *   inner_product = sum(a_i * b_i) = popcount(a AND b)
 *   xor_count = pop_a + pop_b - 2 * inner_product = popcount(a XOR b)
 *   fhd = xor_count / total_bits
 *
 * For the initial implementation, we use unmasked HD (full 8192 bits).
 * Masked HD requires additional HE operations (depth 2) or sending the full
 * product vector. This is acceptable because Open-IRIS's HammingDistanceMatcher
 * also normalizes rather than masks.
 */
struct MatchCandidate {
    std::string template_id;
    std::string identity_id;
    std::string identity_name;
    double hamming_distance;
};

}  // anonymous namespace

namespace eyed {

void HandleDecryptBatch(natsConnection* nc, natsSubscription* /*sub*/, natsMsg* msg, void* /*closure*/) {
    try {
        auto data = std::string(natsMsg_GetData(msg), natsMsg_GetDataLength(msg));
        auto req = nlohmann::json::parse(data);

        double threshold = req.value("threshold", 0.39);
        auto& entries = req["entries"];

        MatchCandidate best;
        best.hamming_distance = 1.0;
        bool found = false;

        for (auto& entry : entries) {
            auto& enc_ips_b64 = entry["enc_inner_products_b64"];
            auto& probe_iris_pop = entry["probe_iris_popcount"];
            auto& gallery_iris_pop = entry["gallery_iris_popcount"];

            double total_xor_count = 0;
            double total_bits = 0;

            // For each iris code array pair (typically 2: real + imaginary)
            for (size_t i = 0; i < enc_ips_b64.size(); ++i) {
                auto ct_bytes = Base64Decode(enc_ips_b64[i].get<std::string>());
                int64_t inner_product = DecryptScalar(ct_bytes);

                int64_t pop_a = probe_iris_pop[i].get<int64_t>();
                int64_t pop_b = gallery_iris_pop[i].get<int64_t>();

                // XOR count = pop_a + pop_b - 2 * inner_product
                int64_t xor_count = pop_a + pop_b - 2 * inner_product;
                total_xor_count += xor_count;
                total_bits += kIrisCodeSlots;
            }

            double fhd = (total_bits > 0) ? (total_xor_count / total_bits) : 1.0;

            if (fhd < best.hamming_distance) {
                best.template_id = entry["template_id"].get<std::string>();
                best.identity_id = entry["identity_id"].get<std::string>();
                best.identity_name = entry.value("identity_name", "");
                best.hamming_distance = fhd;
                found = true;
            }
        }

        nlohmann::json resp;
        resp["is_match"] = found && (best.hamming_distance < threshold);
        resp["hamming_distance"] = best.hamming_distance;
        if (found && best.hamming_distance < threshold) {
            resp["matched_identity_id"] = best.identity_id;
            resp["matched_identity_name"] = best.identity_name;
        } else {
            resp["matched_identity_id"] = nullptr;
            resp["matched_identity_name"] = nullptr;
        }

        SendReply(nc, msg, resp);

    } catch (const std::exception& e) {
        std::cerr << "[key-service] decrypt_batch error: " << e.what() << std::endl;
        SendError(nc, msg, std::string("decrypt_batch failed: ") + e.what());
    }

    natsMsg_Destroy(msg);
}

void HandleDecryptTemplate(natsConnection* nc, natsSubscription* /*sub*/, natsMsg* msg, void* /*closure*/) {
    try {
        auto data = std::string(natsMsg_GetData(msg), natsMsg_GetDataLength(msg));
        auto req = nlohmann::json::parse(data);

        nlohmann::json resp;

        // Decrypt iris codes
        if (req.contains("iris_codes_b64")) {
            auto& iris_b64_list = req["iris_codes_b64"];
            nlohmann::json iris_arrays = nlohmann::json::array();
            for (auto& b64 : iris_b64_list) {
                auto ct_bytes = Base64Decode(b64.get<std::string>());
                auto values = DecryptToVector(ct_bytes);
                iris_arrays.push_back(values);
            }
            resp["iris_codes"] = iris_arrays;
        }

        // Decrypt mask codes
        if (req.contains("mask_codes_b64")) {
            auto& mask_b64_list = req["mask_codes_b64"];
            nlohmann::json mask_arrays = nlohmann::json::array();
            for (auto& b64 : mask_b64_list) {
                auto ct_bytes = Base64Decode(b64.get<std::string>());
                auto values = DecryptToVector(ct_bytes);
                mask_arrays.push_back(values);
            }
            resp["mask_codes"] = mask_arrays;
        }

        SendReply(nc, msg, resp);

    } catch (const std::exception& e) {
        std::cerr << "[key-service] decrypt_template error: " << e.what() << std::endl;
        SendError(nc, msg, std::string("decrypt_template failed: ") + e.what());
    }

    natsMsg_Destroy(msg);
}

void HandleHealth(natsConnection* nc, natsSubscription* /*sub*/, natsMsg* msg, void* /*closure*/) {
    nlohmann::json resp;
    resp["status"] = IsReady() ? "ok" : "not_ready";
    resp["ring_dimension"] = GetRingDimension();
    SendReply(nc, msg, resp);
    natsMsg_Destroy(msg);
}

}  // namespace eyed
