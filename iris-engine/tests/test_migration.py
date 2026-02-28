"""Tests for AES → NPZ migration script.

Tests the detect_format, decrypt_aes, and parse_key functions
from the migration script. Does NOT require a database connection.
"""

from __future__ import annotations

import io
import os

import numpy as np
import pytest

pytest.importorskip("cryptography", reason="migration tests need cryptography")

# Import from scripts directory
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from migrate_aes_to_npz import decrypt_aes, detect_format, parse_key

# A valid 32-byte key as 64 hex chars
TEST_KEY_HEX = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
TEST_KEY_BYTES = bytes.fromhex(TEST_KEY_HEX)


def _make_npz_blob() -> bytes:
    """Create a realistic NPZ blob."""
    arr = np.random.randint(0, 2, size=(16, 256, 2), dtype=np.uint8)
    buf = io.BytesIO()
    np.savez_compressed(buf, arr)
    return buf.getvalue()


def _make_aes_blob(plaintext: bytes, key: bytes) -> bytes:
    """Create an EYED1-prefixed AES-256-GCM encrypted blob."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    nonce = os.urandom(12)
    aesgcm = AESGCM(key)
    ct_with_tag = aesgcm.encrypt(nonce, plaintext, None)
    return b"EYED1" + nonce + ct_with_tag


# ---------------------------------------------------------------------------
# Test detect_format
# ---------------------------------------------------------------------------


class TestDetectFormat:
    def test_detects_aes(self):
        blob = _make_aes_blob(b"test", TEST_KEY_BYTES)
        assert detect_format(blob) == "aes"

    def test_detects_npz(self):
        blob = _make_npz_blob()
        assert detect_format(blob) == "npz"

    def test_detects_he(self):
        import struct
        blob = b"HEv1" + struct.pack("<I", 0)
        assert detect_format(blob) == "he"

    def test_unknown_format(self):
        assert detect_format(b"random data") == "unknown"

    def test_empty_data(self):
        assert detect_format(b"") == "unknown"


# ---------------------------------------------------------------------------
# Test decrypt_aes
# ---------------------------------------------------------------------------


class TestDecryptAes:
    def test_roundtrip(self):
        """EYED1 blob decrypts to original plaintext."""
        plaintext = _make_npz_blob()
        encrypted = _make_aes_blob(plaintext, TEST_KEY_BYTES)
        decrypted = decrypt_aes(encrypted, TEST_KEY_BYTES)
        assert decrypted == plaintext

    def test_non_eyed1_raises(self):
        """Non-EYED1 data raises ValueError."""
        with pytest.raises(ValueError, match="EYED1"):
            decrypt_aes(b"not encrypted", TEST_KEY_BYTES)

    def test_wrong_key_fails(self):
        """Decryption with wrong key raises."""
        from cryptography.exceptions import InvalidTag

        plaintext = b"secret data"
        encrypted = _make_aes_blob(plaintext, TEST_KEY_BYTES)
        wrong_key = os.urandom(32)
        with pytest.raises(InvalidTag):
            decrypt_aes(encrypted, wrong_key)

    def test_decrypted_npz_is_valid(self):
        """Decrypted blob should be a valid NPZ archive."""
        npz_data = _make_npz_blob()
        encrypted = _make_aes_blob(npz_data, TEST_KEY_BYTES)
        decrypted = decrypt_aes(encrypted, TEST_KEY_BYTES)

        buf = io.BytesIO(decrypted)
        npz = np.load(buf)
        arrays = [npz[k] for k in sorted(npz.files)]
        assert len(arrays) == 1
        assert arrays[0].shape == (16, 256, 2)


# ---------------------------------------------------------------------------
# Test parse_key
# ---------------------------------------------------------------------------


class TestParseKey:
    def test_hex_key(self):
        key = parse_key(TEST_KEY_HEX)
        assert key == TEST_KEY_BYTES
        assert len(key) == 32

    def test_base64_key(self):
        import base64

        b64 = base64.b64encode(TEST_KEY_BYTES).decode()
        key = parse_key(b64)
        assert key == TEST_KEY_BYTES

    def test_wrong_length_raises(self):
        with pytest.raises(ValueError, match="32 bytes"):
            parse_key("aabbccdd")

    def test_whitespace_stripped(self):
        key = parse_key(f"  {TEST_KEY_HEX}  \n")
        assert key == TEST_KEY_BYTES
