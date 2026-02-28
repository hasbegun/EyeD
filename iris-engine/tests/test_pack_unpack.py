"""Tests for pack_codes/unpack_codes (plain NPZ format)."""

from __future__ import annotations

import io

import numpy as np

from src.db import pack_codes, unpack_codes

# NPZ files (ZIP archives) start with this magic.
_NPZ_MAGIC = b"PK\x03\x04"


class TestPackUnpackNPZ:
    """Test pack_codes/unpack_codes without any encryption."""

    def test_roundtrip_single_array(self):
        """Single array roundtrip through pack/unpack."""
        codes = [np.array([[1, 0], [0, 1]], dtype=np.uint8)]
        packed = pack_codes(codes)
        assert packed[:4] == _NPZ_MAGIC

        unpacked = unpack_codes(packed)
        assert len(unpacked) == 1
        np.testing.assert_array_equal(unpacked[0], codes[0])

    def test_roundtrip_multiple_arrays(self):
        """Multiple arrays preserve order and values."""
        codes = [
            np.random.randint(0, 2, size=(16, 256, 2), dtype=np.uint8),
            np.random.randint(0, 2, size=(16, 256, 2), dtype=np.uint8),
        ]
        packed = pack_codes(codes)
        unpacked = unpack_codes(packed)

        assert len(unpacked) == 2
        np.testing.assert_array_equal(unpacked[0], codes[0])
        np.testing.assert_array_equal(unpacked[1], codes[1])

    def test_output_is_valid_npz(self):
        """pack_codes output is a valid NPZ archive loadable by numpy."""
        codes = [np.ones((4, 8), dtype=np.uint8)]
        packed = pack_codes(codes)

        buf = io.BytesIO(packed)
        npz = np.load(buf)
        assert len(npz.files) == 1
        np.testing.assert_array_equal(npz[npz.files[0]], codes[0])

    def test_he_encrypt_flag_false_gives_npz(self):
        """Explicit he_encrypt=False produces plain NPZ."""
        codes = [np.zeros((2, 2), dtype=np.uint8)]
        packed = pack_codes(codes, he_encrypt=False)
        assert packed[:4] == _NPZ_MAGIC

    def test_empty_array(self):
        """An empty array roundtrips correctly."""
        codes = [np.array([], dtype=np.uint8)]
        packed = pack_codes(codes)
        unpacked = unpack_codes(packed)
        assert len(unpacked) == 1
        np.testing.assert_array_equal(unpacked[0], codes[0])
