"""Application-level AES-256-GCM encryption for biometric templates.

Encrypts iris_codes and mask_codes before they leave the process boundary
(PostgreSQL BYTEA, Redis JSON). Decrypts on read. Transparent to callers —
hooked into pack_codes/unpack_codes in db.py.

Key: EYED_ENCRYPTION_KEY env var (32 bytes as 64 hex chars or 44 base64 chars).
If unset, encryption is disabled and data passes through unchanged.

Encrypted blob format:
    EYED1 (5B) || nonce (12B) || ciphertext || GCM tag (16B)
    Total overhead: 33 bytes per blob.
"""

from __future__ import annotations

import base64
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

_key: Optional[bytes] = None
_initialized: bool = False

# NPZ files (np.savez_compressed) are ZIP archives starting with this magic.
_NPZ_MAGIC = b"PK\x03\x04"

# Encrypted blobs start with this prefix (version 1).
_ENCRYPTED_PREFIX = b"EYED1"

_NONCE_SIZE = 12


def _load_key() -> Optional[bytes]:
    """Load encryption key from environment on first use."""
    global _key, _initialized
    if _initialized:
        return _key

    raw = os.environ.get("EYED_ENCRYPTION_KEY", "").strip()
    if not raw:
        logger.info("EYED_ENCRYPTION_KEY not set — template encryption disabled")
        _key = None
        _initialized = True
        return _key

    # Support both hex (64 chars) and base64 (44 chars) encoding.
    try:
        key_bytes = bytes.fromhex(raw)
    except ValueError:
        key_bytes = base64.b64decode(raw)

    if len(key_bytes) != 32:
        raise ValueError(
            f"EYED_ENCRYPTION_KEY must be 32 bytes (got {len(key_bytes)}). "
            "Provide 64 hex chars or 44 base64 chars."
        )

    _key = key_bytes
    _initialized = True
    logger.info("AES-256-GCM template encryption enabled")
    return _key


def reset() -> None:
    """Reset cached key state. Used by tests."""
    global _key, _initialized
    _key = None
    _initialized = False


def is_encryption_enabled() -> bool:
    """Return True if an encryption key is configured."""
    return _load_key() is not None


def encrypt(plaintext: bytes) -> bytes:
    """Encrypt with AES-256-GCM. Returns plaintext unchanged if no key."""
    key = _load_key()
    if key is None:
        return plaintext

    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    nonce = os.urandom(_NONCE_SIZE)
    aesgcm = AESGCM(key)
    ct_with_tag = aesgcm.encrypt(nonce, plaintext, None)
    return _ENCRYPTED_PREFIX + nonce + ct_with_tag


def decrypt(data: bytes) -> bytes:
    """Decrypt AES-256-GCM. Passes through legacy unencrypted NPZ data."""
    if not data:
        return data

    # Legacy unencrypted: NPZ (ZIP) files start with PK\x03\x04
    if data[:4] == _NPZ_MAGIC:
        return data

    # Not encrypted — unknown format, assume legacy
    if data[:5] != _ENCRYPTED_PREFIX:
        return data

    # Encrypted blob — key is required
    key = _load_key()
    if key is None:
        raise RuntimeError(
            "Encrypted template data found but EYED_ENCRYPTION_KEY is not set. "
            "Cannot decrypt without the encryption key."
        )

    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    nonce = data[5 : 5 + _NONCE_SIZE]
    ct_with_tag = data[5 + _NONCE_SIZE :]
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ct_with_tag, None)
