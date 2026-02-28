"""NATS client for key-service communication.

Provides async request-reply functions to the key-service for:
  - Batch decryption of encrypted inner products (match results)
  - Template decryption for admin visualization

The key-service holds the BFV secret key; iris-engine only has the public key.
"""

from __future__ import annotations

import base64
import json
import logging
from typing import Optional

from .config import settings
from .models import MatchResult

logger = logging.getLogger(__name__)

# NATS max payload is 8MB; each ciphertext is ~436KB.
# Chunk batch requests to stay under the limit.
_MAX_CTS_PER_REQUEST = 16  # ~16 × 436KB ≈ 7MB < 8MB limit
_REQUEST_TIMEOUT = 30.0  # seconds


async def request_decrypt_batch(
    entries: list[dict],
    threshold: float,
) -> Optional[MatchResult]:
    """Send encrypted inner products to key-service for decryption and HD check.

    Args:
        entries: List of dicts with:
            - template_id: str
            - identity_id: str
            - identity_name: str
            - enc_inner_products: list[bytes] (serialized ciphertexts)
            - probe_iris_popcount: list[int]
            - gallery_iris_popcount: list[int]
            - probe_mask_popcount: list[int]
            - gallery_mask_popcount: list[int]
        threshold: Fractional Hamming distance threshold.

    Returns:
        MatchResult if a match is found, or a no-match MatchResult.
    """
    from . import nats_service

    if not nats_service.nc or not nats_service.nc.is_connected:
        logger.error("Cannot decrypt: NATS not connected")
        return MatchResult(hamming_distance=1.0, is_match=False)

    # Convert ciphertext bytes to base64 for JSON transport
    payload_entries = []
    for entry in entries:
        payload_entries.append({
            "template_id": entry["template_id"],
            "identity_id": entry["identity_id"],
            "identity_name": entry.get("identity_name", ""),
            "enc_inner_products_b64": [
                base64.b64encode(ct_bytes).decode("ascii")
                for ct_bytes in entry["enc_inner_products"]
            ],
            "probe_iris_popcount": entry["probe_iris_popcount"],
            "gallery_iris_popcount": entry["gallery_iris_popcount"],
            "probe_mask_popcount": entry.get("probe_mask_popcount", []),
            "gallery_mask_popcount": entry.get("gallery_mask_popcount", []),
        })

    # Chunk if too many entries (each entry has multiple ciphertexts)
    total_cts = sum(len(e["enc_inner_products_b64"]) for e in payload_entries)
    if total_cts <= _MAX_CTS_PER_REQUEST:
        return await _send_decrypt_request(payload_entries, threshold)

    # Chunked mode: split entries into batches, take best result
    best_result = MatchResult(hamming_distance=1.0, is_match=False)
    chunk: list[dict] = []
    chunk_cts = 0

    for entry in payload_entries:
        entry_cts = len(entry["enc_inner_products_b64"])
        if chunk_cts + entry_cts > _MAX_CTS_PER_REQUEST and chunk:
            result = await _send_decrypt_request(chunk, threshold)
            if result and result.hamming_distance < best_result.hamming_distance:
                best_result = result
            chunk = []
            chunk_cts = 0
        chunk.append(entry)
        chunk_cts += entry_cts

    if chunk:
        result = await _send_decrypt_request(chunk, threshold)
        if result and result.hamming_distance < best_result.hamming_distance:
            best_result = result

    return best_result


async def _send_decrypt_request(
    entries: list[dict],
    threshold: float,
) -> Optional[MatchResult]:
    """Send a single NATS request to key-service."""
    from . import nats_service

    subject = f"{settings.he_key_service_subject}.decrypt_batch"
    payload = json.dumps({
        "threshold": threshold,
        "entries": entries,
    }).encode()

    try:
        response = await nats_service.nc.request(
            subject, payload, timeout=_REQUEST_TIMEOUT
        )
        data = json.loads(response.data.decode())

        if "error" in data:
            logger.error("key-service error: %s", data["error"])
            return MatchResult(hamming_distance=1.0, is_match=False)

        return MatchResult(
            hamming_distance=data.get("hamming_distance", 1.0),
            is_match=data.get("is_match", False),
            matched_identity_id=data.get("matched_identity_id"),
            matched_identity_name=data.get("matched_identity_name"),
        )

    except Exception:
        logger.exception("key-service decrypt_batch request failed")
        return MatchResult(hamming_distance=1.0, is_match=False)


async def request_decrypt_template(
    iris_codes_blob: bytes,
    mask_codes_blob: bytes,
) -> Optional[dict]:
    """Request template decryption for admin visualization.

    Args:
        iris_codes_blob: HEv1 blob from DB (serialized HE ciphertexts).
        mask_codes_blob: HEv1 blob from DB.

    Returns:
        Dict with 'iris_codes' and 'mask_codes' as lists of numpy arrays,
        or None on failure.
    """
    import numpy as np

    from . import nats_service
    from .he_context import _HE_PREFIX, unpack_he_codes

    if not nats_service.nc or not nats_service.nc.is_connected:
        logger.error("Cannot decrypt template: NATS not connected")
        return None

    # Extract serialized ciphertexts from HEv1 blobs
    from .he_context import serialize_ciphertext

    iris_cts = unpack_he_codes(iris_codes_blob)
    mask_cts = unpack_he_codes(mask_codes_blob)

    subject = f"{settings.he_key_service_subject}.decrypt_template"
    payload = json.dumps({
        "iris_codes_b64": [
            base64.b64encode(serialize_ciphertext(ct)).decode("ascii")
            for ct in iris_cts
        ],
        "mask_codes_b64": [
            base64.b64encode(serialize_ciphertext(ct)).decode("ascii")
            for ct in mask_cts
        ],
    }).encode()

    try:
        response = await nats_service.nc.request(
            subject, payload, timeout=_REQUEST_TIMEOUT
        )
        data = json.loads(response.data.decode())

        if "error" in data:
            logger.error("key-service error: %s", data["error"])
            return None

        from .he_context import IRIS_CODE_SHAPE

        return {
            "iris_codes": [
                np.array(arr, dtype=np.int32).reshape(IRIS_CODE_SHAPE)
                for arr in data["iris_codes"]
            ],
            "mask_codes": [
                np.array(arr, dtype=np.int32).reshape(IRIS_CODE_SHAPE)
                for arr in data["mask_codes"]
            ],
        }

    except Exception:
        logger.exception("key-service decrypt_template request failed")
        return None
