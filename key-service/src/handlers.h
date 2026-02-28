#pragma once

/**
 * @file handlers.h
 * @brief NATS message handlers for key-service operations.
 *
 * Handlers:
 *   eyed.key.decrypt_batch    — Batch decrypt inner products, compute HD, find best match
 *   eyed.key.decrypt_template — Decrypt a full template for admin visualization
 *   eyed.key.health           — Health check
 */

#include <nats.h>

namespace eyed {

/**
 * Handle batch decryption request.
 *
 * Request JSON:
 *   {
 *     "threshold": 0.39,
 *     "entries": [
 *       {
 *         "template_id": "uuid",
 *         "identity_id": "uuid",
 *         "identity_name": "Alice",
 *         "enc_inner_products_b64": ["base64...", ...],
 *         "probe_iris_popcount": [4100, 4050],
 *         "gallery_iris_popcount": [4200, 4080],
 *         "probe_mask_popcount": [7800, 7700],
 *         "gallery_mask_popcount": [7900, 7850]
 *       },
 *       ...
 *     ]
 *   }
 *
 * Response JSON:
 *   {
 *     "is_match": true,
 *     "hamming_distance": 0.34,
 *     "matched_identity_id": "uuid",
 *     "matched_identity_name": "Alice"
 *   }
 */
void HandleDecryptBatch(natsConnection* nc, natsSubscription* sub, natsMsg* msg, void* closure);

/**
 * Handle template decryption for admin visualization.
 *
 * Request JSON:
 *   {
 *     "iris_codes_b64": "base64...",
 *     "mask_codes_b64": "base64..."
 *   }
 *
 * Response JSON:
 *   {
 *     "iris_codes": [[0,1,0,...], [1,0,1,...], ...],
 *     "mask_codes": [[1,1,0,...], [1,1,1,...], ...]
 *   }
 */
void HandleDecryptTemplate(natsConnection* nc, natsSubscription* sub, natsMsg* msg, void* closure);

/**
 * Handle health check.
 *
 * Response JSON: {"status": "ok", "ring_dimension": 8192}
 */
void HandleHealth(natsConnection* nc, natsSubscription* sub, natsMsg* msg, void* closure);

}  // namespace eyed
