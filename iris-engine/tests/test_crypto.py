"""Tests for AES-256-GCM biometric template encryption."""

import io
import os

import numpy as np
import pytest

from src.crypto import decrypt, encrypt, reset, _ENCRYPTED_PREFIX, _NPZ_MAGIC
from src.db import pack_codes, unpack_codes

# A valid 32-byte key as 64 hex chars
TEST_KEY_HEX = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


@pytest.fixture(autouse=True)
def _reset_crypto(monkeypatch):
    """Reset crypto module state before each test."""
    monkeypatch.delenv("EYED_ENCRYPTION_KEY", raising=False)
    reset()
    yield
    reset()


def _make_npz_blob() -> bytes:
    """Create a realistic NPZ blob (same format as pack_codes without encryption)."""
    arr = np.random.randint(0, 2, size=(16, 256, 2), dtype=np.uint8)
    buf = io.BytesIO()
    np.savez_compressed(buf, arr)
    return buf.getvalue()


class TestEncryptDecrypt:
    def test_roundtrip(self, monkeypatch):
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        plaintext = os.urandom(4096)
        ciphertext = encrypt(plaintext)
        assert ciphertext != plaintext
        assert decrypt(ciphertext) == plaintext

    def test_unique_nonces(self, monkeypatch):
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        plaintext = b"same data"
        ct1 = encrypt(plaintext)
        ct2 = encrypt(plaintext)
        assert ct1 != ct2  # Different nonces produce different ciphertexts
        assert decrypt(ct1) == plaintext
        assert decrypt(ct2) == plaintext

    def test_encrypted_prefix(self, monkeypatch):
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        ct = encrypt(b"test data")
        assert ct[:5] == _ENCRYPTED_PREFIX

    def test_tampered_ciphertext_fails(self, monkeypatch):
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        ct = encrypt(b"sensitive biometric data")
        # Flip a byte in the ciphertext body (after prefix + nonce)
        corrupted = bytearray(ct)
        corrupted[20] ^= 0xFF
        corrupted = bytes(corrupted)

        from cryptography.exceptions import InvalidTag

        with pytest.raises(InvalidTag):
            decrypt(corrupted)

    def test_empty_data(self, monkeypatch):
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        assert decrypt(b"") == b""


class TestNoKeyPassthrough:
    def test_encrypt_passthrough(self):
        """With no key, encrypt returns plaintext unchanged."""
        plaintext = b"unencrypted data"
        assert encrypt(plaintext) == plaintext

    def test_decrypt_passthrough_unknown_format(self):
        """With no key, decrypt passes through non-encrypted data."""
        data = b"some random bytes"
        assert decrypt(data) == data


class TestLegacyNpzPassthrough:
    def test_npz_passthrough_with_key(self, monkeypatch):
        """NPZ data is returned as-is even when encryption key is set."""
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        npz_blob = _make_npz_blob()
        assert npz_blob[:4] == _NPZ_MAGIC
        assert decrypt(npz_blob) == npz_blob

    def test_npz_passthrough_without_key(self):
        """NPZ data is returned as-is when no key is set."""
        npz_blob = _make_npz_blob()
        assert decrypt(npz_blob) == npz_blob


class TestDecryptWithoutKey:
    def test_encrypted_data_without_key_raises(self, monkeypatch):
        """Encrypted data cannot be decrypted without the key."""
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        ct = encrypt(b"secret template")

        # Remove key
        monkeypatch.delenv("EYED_ENCRYPTION_KEY")
        reset()

        with pytest.raises(RuntimeError, match="EYED_ENCRYPTION_KEY is not set"):
            decrypt(ct)


class TestKeyFormats:
    def test_hex_key(self, monkeypatch):
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        plaintext = b"test"
        assert decrypt(encrypt(plaintext)) == plaintext

    def test_base64_key(self, monkeypatch):
        import base64

        key_bytes = bytes.fromhex(TEST_KEY_HEX)
        b64_key = base64.b64encode(key_bytes).decode()
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", b64_key)
        reset()

        plaintext = b"test"
        assert decrypt(encrypt(plaintext)) == plaintext

    def test_wrong_key_length_raises(self, monkeypatch):
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", "aabbccdd")  # 4 bytes, not 32
        reset()

        with pytest.raises(ValueError, match="must be 32 bytes"):
            encrypt(b"test")


class TestPackUnpackIntegration:
    def test_roundtrip_with_encryption(self, monkeypatch):
        """pack_codes encrypts, unpack_codes decrypts — full roundtrip."""
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        codes = [
            np.random.randint(0, 2, size=(16, 256, 2), dtype=np.uint8),
            np.random.randint(0, 2, size=(16, 256, 2), dtype=np.uint8),
        ]
        packed = pack_codes(codes)
        assert packed[:5] == _ENCRYPTED_PREFIX  # Encrypted
        assert packed[:4] != _NPZ_MAGIC  # Not raw NPZ

        unpacked = unpack_codes(packed)
        assert len(unpacked) == 2
        np.testing.assert_array_equal(unpacked[0], codes[0])
        np.testing.assert_array_equal(unpacked[1], codes[1])

    def test_roundtrip_without_encryption(self):
        """pack_codes/unpack_codes work normally without encryption key."""
        codes = [np.array([[1, 0], [0, 1]], dtype=np.uint8)]
        packed = pack_codes(codes)
        assert packed[:4] == _NPZ_MAGIC  # Raw NPZ

        unpacked = unpack_codes(packed)
        np.testing.assert_array_equal(unpacked[0], codes[0])

    def test_legacy_data_readable_with_key(self, monkeypatch):
        """Unencrypted legacy data can be read after enabling encryption."""
        # Pack without key (legacy)
        codes = [np.ones((4, 8), dtype=np.uint8)]
        legacy_packed = pack_codes(codes)
        assert legacy_packed[:4] == _NPZ_MAGIC

        # Enable encryption
        monkeypatch.setenv("EYED_ENCRYPTION_KEY", TEST_KEY_HEX)
        reset()

        # Legacy data still readable
        unpacked = unpack_codes(legacy_packed)
        np.testing.assert_array_equal(unpacked[0], codes[0])

        # New data is encrypted
        new_packed = pack_codes(codes)
        assert new_packed[:5] == _ENCRYPTED_PREFIX
