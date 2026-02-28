"""Tests for HE-aware enrollment data path.

Tests pack_codes/unpack_codes routing, GalleryEntry with HE fields,
persist_template with popcounts, and the enrollment flow.
"""

from __future__ import annotations

import io
import struct

import numpy as np
import pytest

openfhe = pytest.importorskip("openfhe")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module", autouse=True)
def he_context():
    """Initialize HE context once for all tests in this module."""
    from src.he_context import init_context, reset

    init_context()  # PoC mode: ephemeral keys
    yield
    reset()


@pytest.fixture
def random_iris_code():
    """Random binary iris code of shape (16, 256, 2)."""
    rng = np.random.RandomState(42)
    return rng.randint(0, 2, size=(16, 256, 2), dtype=np.int32)


@pytest.fixture
def random_iris_codes(random_iris_code):
    """List with one random iris code (typical enrollment)."""
    return [random_iris_code]


@pytest.fixture
def random_mask_codes():
    """List with one random mask code."""
    rng = np.random.RandomState(99)
    return [rng.randint(0, 2, size=(16, 256, 2), dtype=np.int32)]


# ---------------------------------------------------------------------------
# Test pack_codes routing
# ---------------------------------------------------------------------------


class TestPackCodesRouting:
    """Test that pack_codes routes to HE or legacy based on he_encrypt flag."""

    def test_pack_codes_legacy_no_he_prefix(self, random_iris_codes):
        """pack_codes(he_encrypt=False) should NOT produce HEv1 prefix."""
        from src.db import pack_codes

        blob = pack_codes(random_iris_codes, he_encrypt=False)
        assert blob[:4] != b"HEv1"

    def test_pack_codes_he_produces_hev1_prefix(self, random_iris_codes):
        """pack_codes(he_encrypt=True) should produce HEv1 prefix."""
        from src.db import pack_codes

        blob = pack_codes(random_iris_codes, he_encrypt=True)
        assert blob[:4] == b"HEv1"

    def test_pack_codes_he_contains_correct_count(self, random_iris_codes):
        """HEv1 blob should encode the correct number of ciphertexts."""
        from src.db import pack_codes

        blob = pack_codes(random_iris_codes, he_encrypt=True)
        count = struct.unpack("<I", blob[4:8])[0]
        assert count == len(random_iris_codes)


# ---------------------------------------------------------------------------
# Test unpack_codes auto-detection
# ---------------------------------------------------------------------------


class TestUnpackCodesAutoDetect:
    """Test that unpack_codes auto-detects HEv1 vs legacy formats."""

    def test_unpack_he_blob_returns_ciphertext_objects(self, random_iris_codes):
        """unpack_codes on HEv1 blob should return Ciphertext objects."""
        from src.db import pack_codes, unpack_codes

        blob = pack_codes(random_iris_codes, he_encrypt=True)
        result = unpack_codes(blob)
        assert len(result) == len(random_iris_codes)
        # Ciphertext objects are not numpy arrays
        assert not isinstance(result[0], np.ndarray)

    def test_unpack_legacy_blob_returns_numpy_arrays(self, random_iris_codes):
        """unpack_codes on legacy NPZ blob should return numpy arrays."""
        from src.db import pack_codes, unpack_codes

        blob = pack_codes(random_iris_codes, he_encrypt=False)
        result = unpack_codes(blob)
        assert len(result) == len(random_iris_codes)
        assert isinstance(result[0], np.ndarray)
        np.testing.assert_array_equal(result[0], random_iris_codes[0])

    def test_he_roundtrip_through_pack_unpack_decrypt(self, random_iris_codes):
        """pack(he) -> unpack -> decrypt should recover original data."""
        from src.db import pack_codes, unpack_codes
        from src.he_context import decrypt_iris_code

        blob = pack_codes(random_iris_codes, he_encrypt=True)
        cts = unpack_codes(blob)
        for i, ct in enumerate(cts):
            recovered = decrypt_iris_code(ct)
            np.testing.assert_array_equal(recovered, random_iris_codes[i])


# ---------------------------------------------------------------------------
# Test GalleryEntry
# ---------------------------------------------------------------------------


class TestGalleryEntry:
    """Test GalleryEntry with HE fields."""

    def test_gallery_entry_default_he_fields(self):
        """GalleryEntry defaults should have empty HE fields."""
        from src.matcher import GalleryEntry

        entry = GalleryEntry(
            identity_id="test-id",
            template_id="tmpl-id",
            identity_name="Test",
            eye_side="left",
            template=None,
        )
        assert entry.he_iris_cts == []
        assert entry.he_mask_cts == []
        assert entry.iris_popcount == []
        assert entry.mask_popcount == []

    def test_gallery_entry_with_he_fields(self, random_iris_codes):
        """GalleryEntry should accept HE fields."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.matcher import GalleryEntry

        cts = [encrypt_iris_code(arr) for arr in random_iris_codes]
        pops = compute_popcounts(random_iris_codes)

        entry = GalleryEntry(
            identity_id="test-id",
            template_id="tmpl-id",
            identity_name="Test",
            eye_side="left",
            template=None,
            he_iris_cts=cts,
            he_mask_cts=[],
            iris_popcount=pops,
            mask_popcount=[],
        )
        assert len(entry.he_iris_cts) == 1
        assert entry.iris_popcount == pops
        assert entry.template is None


# ---------------------------------------------------------------------------
# Test pack_he_codes_from_cts
# ---------------------------------------------------------------------------


class TestPackFromCts:
    """Test serialization of already-encrypted Ciphertext objects."""

    def test_roundtrip_from_cts(self, random_iris_codes):
        """pack_he_codes_from_cts -> unpack_he_codes -> decrypt should match."""
        from src.he_context import (
            decrypt_iris_code,
            encrypt_iris_code,
            pack_he_codes_from_cts,
            unpack_he_codes,
        )

        cts = [encrypt_iris_code(arr) for arr in random_iris_codes]
        blob = pack_he_codes_from_cts(cts)

        assert blob[:4] == b"HEv1"

        recovered_cts = unpack_he_codes(blob)
        assert len(recovered_cts) == len(cts)

        for i, ct in enumerate(recovered_cts):
            arr = decrypt_iris_code(ct)
            np.testing.assert_array_equal(arr, random_iris_codes[i])

    def test_from_cts_matches_pack_he_codes(self, random_iris_codes):
        """pack_he_codes_from_cts should produce same-format blob as pack_he_codes."""
        from src.he_context import (
            encrypt_iris_code,
            pack_he_codes,
            pack_he_codes_from_cts,
        )

        # Both should produce HEv1 blobs with same count
        blob_from_numpy = pack_he_codes(random_iris_codes)
        cts = [encrypt_iris_code(arr) for arr in random_iris_codes]
        blob_from_cts = pack_he_codes_from_cts(cts)

        # Same prefix and count
        assert blob_from_numpy[:4] == blob_from_cts[:4] == b"HEv1"
        count1 = struct.unpack("<I", blob_from_numpy[4:8])[0]
        count2 = struct.unpack("<I", blob_from_cts[4:8])[0]
        assert count1 == count2 == len(random_iris_codes)


# ---------------------------------------------------------------------------
# Test enrollment with HE
# ---------------------------------------------------------------------------


class TestEnrollWithHE:
    """Test gallery enrollment with HE-encrypted templates."""

    def test_enroll_with_he_fields(self, random_iris_codes, random_mask_codes):
        """Enrollment with HE fields should store ciphertexts in gallery."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.matcher import TemplateGallery

        gallery = TemplateGallery()

        iris_cts = [encrypt_iris_code(arr) for arr in random_iris_codes]
        mask_cts = [encrypt_iris_code(arr) for arr in random_mask_codes]
        iris_pop = compute_popcounts(random_iris_codes)
        mask_pop = compute_popcounts(random_mask_codes)

        tid = gallery.enroll(
            identity_id="id-1",
            identity_name="Test User",
            eye_side="left",
            template=None,
            he_iris_cts=iris_cts,
            he_mask_cts=mask_cts,
            iris_popcount=iris_pop,
            mask_popcount=mask_pop,
        )

        assert tid  # Non-empty UUID string
        assert gallery.size == 1

        entry = gallery._entries[0]
        assert entry.template is None
        assert len(entry.he_iris_cts) == 1
        assert len(entry.he_mask_cts) == 1
        assert entry.iris_popcount == iris_pop
        assert entry.mask_popcount == mask_pop

    def test_enroll_legacy_still_works(self):
        """Enrollment without HE fields should still work."""
        from src.matcher import TemplateGallery

        gallery = TemplateGallery()

        class FakeTemplate:
            iris_codes = [np.zeros((16, 256, 2))]
            mask_codes = [np.zeros((16, 256, 2))]

        tid = gallery.enroll(
            identity_id="id-2",
            identity_name="Legacy User",
            eye_side="right",
            template=FakeTemplate(),
        )

        assert tid
        assert gallery.size == 1
        entry = gallery._entries[0]
        assert entry.template is not None
        assert entry.he_iris_cts == []
