"""Homomorphic encryption matching for iris templates.

Computes encrypted inner products between a probe and all gallery entries,
then delegates decryption to the key-service (production) or decrypts locally
(PoC/test mode with secret key).
"""

from __future__ import annotations

import logging
from typing import Optional

from .config import settings
from .he_context import (
    IRIS_CODE_SLOTS,
    compute_popcounts,
    decrypt_scalar,
    encrypt_iris_code,
    has_secret_key,
    he_inner_product,
    serialize_ciphertext,
)
from .models import MatchResult

logger = logging.getLogger(__name__)


def encrypt_probe(template) -> tuple:
    """Encrypt a plaintext probe template for HE matching.

    Args:
        template: Open-IRIS IrisTemplate (plaintext, fresh from pipeline).

    Returns:
        (iris_cts, mask_cts, iris_popcount, mask_popcount) tuple.
    """
    iris_cts = [encrypt_iris_code(arr) for arr in template.iris_codes]
    mask_cts = [encrypt_iris_code(arr) for arr in template.mask_codes]
    iris_popcount = compute_popcounts(template.iris_codes)
    mask_popcount = compute_popcounts(template.mask_codes)
    return iris_cts, mask_cts, iris_popcount, mask_popcount


def he_match_1n_local(
    probe_iris_cts: list,
    probe_mask_cts: list,
    probe_iris_popcount: list[int],
    probe_mask_popcount: list[int],
    gallery_entries: list,
    threshold: float,
) -> Optional[MatchResult]:
    """HE matching with local decryption (PoC/test mode only).

    Decrypts inner products locally using the secret key instead of
    sending to key-service. Only works when has_secret_key() is True.

    Args:
        probe_iris_cts: Encrypted probe iris codes.
        probe_mask_cts: Encrypted probe mask codes.
        probe_iris_popcount: Plaintext popcounts for probe iris codes.
        probe_mask_popcount: Plaintext popcounts for probe mask codes.
        gallery_entries: List of GalleryEntry with he_iris_cts populated.
        threshold: Fractional Hamming distance threshold.

    Returns:
        MatchResult with best match below threshold.
    """
    if not has_secret_key():
        raise RuntimeError("Local HE matching requires secret key (PoC mode only)")

    if not gallery_entries:
        return MatchResult(hamming_distance=1.0, is_match=False)

    best_distance = 1.0
    best_entry = None

    for entry in gallery_entries:
        if not entry.he_iris_cts:
            continue

        total_xor = 0
        total_bits = 0
        n_codes = min(len(probe_iris_cts), len(entry.he_iris_cts))

        for i in range(n_codes):
            ct_ip = he_inner_product(probe_iris_cts[i], entry.he_iris_cts[i])
            ip_val = decrypt_scalar(ct_ip)
            pop_a = probe_iris_popcount[i]
            pop_b = entry.iris_popcount[i]
            xor_count = pop_a + pop_b - 2 * ip_val
            total_xor += xor_count
            total_bits += IRIS_CODE_SLOTS

        fhd = total_xor / total_bits if total_bits > 0 else 1.0

        if fhd < best_distance:
            best_distance = fhd
            best_entry = entry

    is_match = best_distance < threshold
    return MatchResult(
        hamming_distance=best_distance,
        is_match=is_match,
        matched_identity_id=best_entry.identity_id if is_match and best_entry else None,
        matched_identity_name=best_entry.identity_name if is_match and best_entry else None,
    )


async def he_match_1n(
    probe_iris_cts: list,
    probe_mask_cts: list,
    probe_iris_popcount: list[int],
    probe_mask_popcount: list[int],
    gallery_entries: list,
    threshold: float,
) -> Optional[MatchResult]:
    """HE matching with key-service decryption (production mode).

    Computes encrypted inner products for all gallery entries, then sends
    the batch to key-service via NATS for decryption and HD computation.
    """
    from . import key_client

    if not gallery_entries:
        return MatchResult(hamming_distance=1.0, is_match=False)

    batch_entries = []
    for entry in gallery_entries:
        if not entry.he_iris_cts:
            continue

        enc_inner_products = []
        n_codes = min(len(probe_iris_cts), len(entry.he_iris_cts))
        for i in range(n_codes):
            ct_ip = he_inner_product(probe_iris_cts[i], entry.he_iris_cts[i])
            ct_ip_bytes = serialize_ciphertext(ct_ip)
            enc_inner_products.append(ct_ip_bytes)

        batch_entries.append({
            "template_id": entry.template_id,
            "identity_id": entry.identity_id,
            "identity_name": entry.identity_name,
            "enc_inner_products": enc_inner_products,
            "probe_iris_popcount": probe_iris_popcount,
            "gallery_iris_popcount": entry.iris_popcount,
            "probe_mask_popcount": probe_mask_popcount,
            "gallery_mask_popcount": entry.mask_popcount,
        })

    if not batch_entries:
        return MatchResult(hamming_distance=1.0, is_match=False)

    return await key_client.request_decrypt_batch(batch_entries, threshold)
