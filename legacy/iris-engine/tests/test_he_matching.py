"""Tests for HE matching module.

Tests use ephemeral keys (PoC mode) with local decrypt — no real key-service.
"""

from __future__ import annotations

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


def _make_iris_code(seed: int) -> np.ndarray:
    """Create a random binary iris code."""
    rng = np.random.RandomState(seed)
    return rng.randint(0, 2, size=(16, 256, 2), dtype=np.int32)


def _make_gallery_entry(seed: int, identity_id: str, name: str = ""):
    """Create a GalleryEntry with HE-encrypted template."""
    from src.he_context import compute_popcounts, encrypt_iris_code
    from src.matcher import GalleryEntry

    iris_code = _make_iris_code(seed)
    mask_code = _make_iris_code(seed + 1000)  # Different seed for mask

    return GalleryEntry(
        identity_id=identity_id,
        template_id=f"tmpl-{identity_id}",
        identity_name=name or f"User {identity_id}",
        eye_side="left",
        template=None,
        he_iris_cts=[encrypt_iris_code(iris_code)],
        he_mask_cts=[encrypt_iris_code(mask_code)],
        iris_popcount=compute_popcounts([iris_code]),
        mask_popcount=compute_popcounts([mask_code]),
    ), iris_code


# ---------------------------------------------------------------------------
# Test encrypt_probe
# ---------------------------------------------------------------------------


class TestEncryptProbe:
    """Test the encrypt_probe helper."""

    def test_encrypt_probe_returns_correct_types(self):
        """encrypt_probe should return (cts, cts, pops, pops) tuple."""
        from src.he_matcher import encrypt_probe

        class FakeTemplate:
            iris_codes = [_make_iris_code(42)]
            mask_codes = [_make_iris_code(99)]

        iris_cts, mask_cts, iris_pop, mask_pop = encrypt_probe(FakeTemplate())

        assert len(iris_cts) == 1
        assert len(mask_cts) == 1
        assert len(iris_pop) == 1
        assert len(mask_pop) == 1
        assert isinstance(iris_pop[0], int)
        assert isinstance(mask_pop[0], int)

    def test_encrypt_probe_popcount_correct(self):
        """Popcounts from encrypt_probe should match numpy sum."""
        from src.he_matcher import encrypt_probe

        code = _make_iris_code(42)

        class FakeTemplate:
            iris_codes = [code]
            mask_codes = [code]

        _, _, iris_pop, _ = encrypt_probe(FakeTemplate())
        expected = int(np.sum(code.astype(bool)))
        assert iris_pop[0] == expected


# ---------------------------------------------------------------------------
# Test he_match_1n_local
# ---------------------------------------------------------------------------


class TestHEMatchLocal:
    """Test HE matching with local decryption (PoC mode)."""

    def test_identical_templates_hd_zero(self):
        """Matching identical templates should give HD=0."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.he_matcher import he_match_1n_local

        iris_code = _make_iris_code(42)
        entry, _ = _make_gallery_entry(42, "id-1")

        # Encrypt the same code as probe
        probe_iris_cts = [encrypt_iris_code(iris_code)]
        probe_iris_pop = compute_popcounts([iris_code])

        result = he_match_1n_local(
            probe_iris_cts=probe_iris_cts,
            probe_mask_cts=[],
            probe_iris_popcount=probe_iris_pop,
            probe_mask_popcount=[],
            gallery_entries=[entry],
            threshold=0.5,
        )

        assert result is not None
        assert result.is_match is True
        assert result.hamming_distance == pytest.approx(0.0, abs=1e-9)
        assert result.matched_identity_id == "id-1"

    def test_different_templates_hd_nonzero(self):
        """Matching different templates should give HD > 0."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.he_matcher import he_match_1n_local

        probe_code = _make_iris_code(42)
        entry, gallery_code = _make_gallery_entry(99, "id-2")

        probe_iris_cts = [encrypt_iris_code(probe_code)]
        probe_iris_pop = compute_popcounts([probe_code])

        result = he_match_1n_local(
            probe_iris_cts=probe_iris_cts,
            probe_mask_cts=[],
            probe_iris_popcount=probe_iris_pop,
            probe_mask_popcount=[],
            gallery_entries=[entry],
            threshold=0.5,
        )

        assert result is not None
        # Random binary codes should have HD around 0.5
        assert 0.3 < result.hamming_distance < 0.7

    def test_hd_matches_plaintext_computation(self):
        """HE-computed HD should match plaintext computation."""
        from src.he_context import IRIS_CODE_SLOTS, compute_popcounts, encrypt_iris_code
        from src.he_matcher import he_match_1n_local

        probe_code = _make_iris_code(42)
        gallery_code = _make_iris_code(99)
        entry, _ = _make_gallery_entry(99, "id-3")

        probe_iris_cts = [encrypt_iris_code(probe_code)]
        probe_iris_pop = compute_popcounts([probe_code])

        # Plaintext HD
        ip_plaintext = int(np.sum(probe_code.flatten() * gallery_code.flatten()))
        pop_a = int(np.sum(probe_code.astype(bool)))
        pop_b = int(np.sum(gallery_code.astype(bool)))
        xor_count = pop_a + pop_b - 2 * ip_plaintext
        expected_hd = xor_count / IRIS_CODE_SLOTS

        # HE HD
        result = he_match_1n_local(
            probe_iris_cts=probe_iris_cts,
            probe_mask_cts=[],
            probe_iris_popcount=probe_iris_pop,
            probe_mask_popcount=[],
            gallery_entries=[entry],
            threshold=1.0,
        )

        assert result.hamming_distance == pytest.approx(expected_hd, abs=1e-9)

    def test_empty_gallery_no_match(self):
        """Empty gallery should return no match."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.he_matcher import he_match_1n_local

        probe_code = _make_iris_code(42)
        probe_iris_cts = [encrypt_iris_code(probe_code)]
        probe_iris_pop = compute_popcounts([probe_code])

        result = he_match_1n_local(
            probe_iris_cts=probe_iris_cts,
            probe_mask_cts=[],
            probe_iris_popcount=probe_iris_pop,
            probe_mask_popcount=[],
            gallery_entries=[],
            threshold=0.5,
        )

        assert result is not None
        assert result.is_match is False
        assert result.hamming_distance == 1.0

    def test_threshold_filtering(self):
        """Matches above threshold should not be returned."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.he_matcher import he_match_1n_local

        probe_code = _make_iris_code(42)
        entry, _ = _make_gallery_entry(99, "id-4")

        probe_iris_cts = [encrypt_iris_code(probe_code)]
        probe_iris_pop = compute_popcounts([probe_code])

        # Very strict threshold — random codes should not match
        result = he_match_1n_local(
            probe_iris_cts=probe_iris_cts,
            probe_mask_cts=[],
            probe_iris_popcount=probe_iris_pop,
            probe_mask_popcount=[],
            gallery_entries=[entry],
            threshold=0.1,
        )

        assert result is not None
        assert result.is_match is False

    def test_best_match_selected(self):
        """With multiple gallery entries, best match should be returned."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.he_matcher import he_match_1n_local

        probe_code = _make_iris_code(42)
        entry_same, _ = _make_gallery_entry(42, "id-same", "Same")
        entry_diff, _ = _make_gallery_entry(99, "id-diff", "Different")

        probe_iris_cts = [encrypt_iris_code(probe_code)]
        probe_iris_pop = compute_popcounts([probe_code])

        result = he_match_1n_local(
            probe_iris_cts=probe_iris_cts,
            probe_mask_cts=[],
            probe_iris_popcount=probe_iris_pop,
            probe_mask_popcount=[],
            gallery_entries=[entry_diff, entry_same],
            threshold=0.5,
        )

        assert result is not None
        assert result.is_match is True
        assert result.matched_identity_id == "id-same"
        assert result.hamming_distance == pytest.approx(0.0, abs=1e-9)


# ---------------------------------------------------------------------------
# Test gallery match/dedup routing
# ---------------------------------------------------------------------------


class TestMatcherHERouting:
    """Test that TemplateGallery routes to HE when enabled."""

    def test_enroll_and_match_he_poc(self):
        """End-to-end: enroll with HE → match with HE → correct result."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.matcher import TemplateGallery

        gallery = TemplateGallery()
        code = _make_iris_code(42)
        mask = _make_iris_code(43)

        iris_cts = [encrypt_iris_code(code)]
        mask_cts = [encrypt_iris_code(mask)]
        iris_pop = compute_popcounts([code])
        mask_pop = compute_popcounts([mask])

        gallery.enroll(
            identity_id="enrolled-1",
            identity_name="Enrolled User",
            eye_side="left",
            template=None,
            he_iris_cts=iris_cts,
            he_mask_cts=mask_cts,
            iris_popcount=iris_pop,
            mask_popcount=mask_pop,
        )

        # Match with same code (should find match)
        result = gallery._match_he_with_cts(
            iris_cts, mask_cts, iris_pop, mask_pop,
            threshold=0.5,
        )

        assert result is not None
        assert result.is_match is True
        assert result.matched_identity_id == "enrolled-1"

    def test_dedup_with_cts(self):
        """check_duplicate_with_cts should detect identical templates."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.matcher import TemplateGallery

        gallery = TemplateGallery()
        code = _make_iris_code(42)
        mask = _make_iris_code(43)

        iris_cts = [encrypt_iris_code(code)]
        mask_cts = [encrypt_iris_code(mask)]
        iris_pop = compute_popcounts([code])
        mask_pop = compute_popcounts([mask])

        gallery.enroll(
            identity_id="dup-check",
            identity_name="Dup User",
            eye_side="left",
            template=None,
            he_iris_cts=iris_cts,
            he_mask_cts=mask_cts,
            iris_popcount=iris_pop,
            mask_popcount=mask_pop,
        )

        # Same ciphertexts — should detect as duplicate
        dup_id = gallery.check_duplicate_with_cts(
            iris_cts, mask_cts, iris_pop, mask_pop,
        )
        assert dup_id == "dup-check"

    def test_dedup_different_not_flagged(self):
        """check_duplicate_with_cts should not flag different templates."""
        from src.he_context import compute_popcounts, encrypt_iris_code
        from src.matcher import TemplateGallery

        gallery = TemplateGallery()
        code1 = _make_iris_code(42)
        code2 = _make_iris_code(99)
        mask = _make_iris_code(43)

        iris_cts1 = [encrypt_iris_code(code1)]
        mask_cts = [encrypt_iris_code(mask)]
        iris_pop1 = compute_popcounts([code1])
        mask_pop = compute_popcounts([mask])

        gallery.enroll(
            identity_id="unique-1",
            identity_name="Unique User",
            eye_side="left",
            template=None,
            he_iris_cts=iris_cts1,
            he_mask_cts=mask_cts,
            iris_popcount=iris_pop1,
            mask_popcount=mask_pop,
        )

        # Different code — should not be flagged as duplicate
        iris_cts2 = [encrypt_iris_code(code2)]
        iris_pop2 = compute_popcounts([code2])

        dup_id = gallery.check_duplicate_with_cts(
            iris_cts2, mask_cts, iris_pop2, mask_pop,
        )
        assert dup_id is None
