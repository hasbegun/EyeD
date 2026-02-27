"""FNMR (False Non-Match Rate) accuracy test on CASIA1 dataset.

Runs the Open-IRIS pipeline on real iris images and verifies that genuine
pairs (same person, same eye) match below the threshold at least 99.5%
of the time (FNMR < 0.5%).

Usage:
    pytest tests/test_fnmr.py -v
    # or via Makefile:
    make test-fnmr
"""

from __future__ import annotations

import itertools
import logging
import statistics

import numpy as np
import pytest

from src.config import settings
from src.pipeline import analyze, get_pipeline

logger = logging.getLogger(__name__)

# Number of subjects to test (use fewer for faster CI)
MAX_SUBJECTS = 20


@pytest.fixture(scope="module", autouse=True)
def _load_pipeline():
    """Ensure pipeline is loaded once before FNMR tests."""
    get_pipeline()


@pytest.mark.casia
class TestFNMR:
    """Verify FNMR < 0.5% on CASIA1 genuine pairs."""

    def _extract_templates(self, casia_subjects):
        """Run pipeline on CASIA images, return templates grouped by key.

        Returns:
            dict: {(subject_id, eye_side): [IrisTemplate, ...]}
            int: number of images that failed segmentation
        """
        from iris import HammingDistanceMatcher

        templates: dict[tuple[str, str], list] = {}
        failures = 0
        processed = 0
        subject_count = 0

        for key, images in sorted(casia_subjects.items()):
            if subject_count >= MAX_SUBJECTS:
                break

            subject_id, eye_side = key
            # Only count unique subjects
            if not any(k[0] == subject_id for k in templates):
                subject_count += 1
                if subject_count > MAX_SUBJECTS:
                    break

            for img in images:
                result = analyze(img, eye_side=eye_side)
                processed += 1
                if result.get("error") or result.get("iris_template") is None:
                    failures += 1
                    continue
                templates.setdefault(key, []).append(result["iris_template"])

        logger.info(
            "Processed %d images, %d failures (%.1f%%), %d subjects",
            processed, failures, 100.0 * failures / max(processed, 1), subject_count,
        )
        return templates, failures

    def test_fnmr_below_threshold(self, casia_subjects):
        """FNMR must be < 0.5% for genuine pairs."""
        from iris import HammingDistanceMatcher

        matcher = HammingDistanceMatcher(
            rotation_shift=settings.rotation_shift,
            normalise=True,
            norm_mean=0.45,
            norm_gradient=0.00005,
        )

        templates, seg_failures = self._extract_templates(casia_subjects)

        genuine_distances: list[float] = []
        non_matches = 0

        for key, tmpls in templates.items():
            if len(tmpls) < 2:
                continue
            for t1, t2 in itertools.combinations(tmpls, 2):
                try:
                    dist = matcher.run(template_probe=t1, template_gallery=t2)
                    genuine_distances.append(dist)
                    if dist >= settings.match_threshold:
                        non_matches += 1
                except Exception:
                    logger.exception("Matching failed for %s", key)
                    non_matches += 1

        total_pairs = len(genuine_distances)
        assert total_pairs > 0, "No genuine pairs produced — check dataset and pipeline"

        fnmr = non_matches / total_pairs
        mean_hd = statistics.mean(genuine_distances)
        median_hd = statistics.median(genuine_distances)

        # Print summary
        print(f"\n{'='*60}")
        print(f"FNMR Test Results (CASIA1, {MAX_SUBJECTS} subjects)")
        print(f"{'='*60}")
        print(f"  Genuine pairs tested : {total_pairs}")
        print(f"  Segmentation failures: {seg_failures}")
        print(f"  Non-matches (FNM)    : {non_matches}")
        print(f"  FNMR                 : {fnmr:.4f} ({fnmr*100:.2f}%)")
        print(f"  Mean Hamming distance: {mean_hd:.4f}")
        print(f"  Median HD            : {median_hd:.4f}")
        print(f"  Min HD               : {min(genuine_distances):.4f}")
        print(f"  Max HD               : {max(genuine_distances):.4f}")
        print(f"  Threshold            : {settings.match_threshold}")
        print(f"{'='*60}\n")

        assert fnmr < 0.005, (
            f"FNMR {fnmr:.4f} ({fnmr*100:.2f}%) exceeds 0.5% target. "
            f"{non_matches}/{total_pairs} genuine pairs failed to match."
        )
