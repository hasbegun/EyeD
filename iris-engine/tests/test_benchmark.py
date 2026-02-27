"""Pipeline latency benchmark.

Measures per-frame processing time of the Open-IRIS pipeline on real
CASIA1 images. Target: < 50ms on GPU, < 800ms on CPU (Docker dev).

Usage:
    pytest tests/test_benchmark.py -v -s
    # or via Makefile:
    make test-bench
"""

from __future__ import annotations

import logging
import statistics
import time

import pytest

from src.config import settings
from src.pipeline import analyze, get_pipeline

logger = logging.getLogger(__name__)

NUM_IMAGES = 10


@pytest.fixture(scope="module", autouse=True)
def _load_pipeline():
    """Ensure pipeline is loaded (and warmed up) before benchmarking."""
    get_pipeline()


@pytest.mark.benchmark
class TestBenchmark:
    """Pipeline latency benchmarks."""

    def test_per_frame_latency(self, casia_subjects):
        """Measure per-frame pipeline latency."""
        # Collect first NUM_IMAGES images
        images = []
        for key, imgs in sorted(casia_subjects.items()):
            for img in imgs:
                images.append((img, key[1]))  # (array, eye_side)
                if len(images) >= NUM_IMAGES:
                    break
            if len(images) >= NUM_IMAGES:
                break

        assert len(images) >= NUM_IMAGES, (
            f"Need {NUM_IMAGES} images, found {len(images)}"
        )

        # Warm-up run (first call loads ONNX models)
        analyze(images[0][0], eye_side=images[0][1])

        # Timed runs
        latencies: list[float] = []
        for img, eye_side in images:
            start = time.monotonic()
            analyze(img, eye_side=eye_side)
            elapsed_ms = (time.monotonic() - start) * 1000
            latencies.append(elapsed_ms)

        latencies_sorted = sorted(latencies)
        mean_ms = statistics.mean(latencies)
        median_ms = statistics.median(latencies)
        p95_idx = int(len(latencies_sorted) * 0.95)
        p95_ms = latencies_sorted[min(p95_idx, len(latencies_sorted) - 1)]

        print(f"\n{'='*60}")
        print(f"Benchmark Results ({NUM_IMAGES} frames, runtime={settings.eyed_runtime})")
        print(f"{'='*60}")
        print(f"  Mean   : {mean_ms:7.1f} ms")
        print(f"  Median : {median_ms:7.1f} ms")
        print(f"  Min    : {min(latencies):7.1f} ms")
        print(f"  Max    : {max(latencies):7.1f} ms")
        print(f"  P95    : {p95_ms:7.1f} ms")
        print(f"{'='*60}\n")

        if settings.eyed_runtime == "cpu":
            assert median_ms < 800, (
                f"CPU median latency {median_ms:.1f}ms exceeds 800ms limit"
            )
        else:
            assert median_ms < 50, (
                f"GPU median latency {median_ms:.1f}ms exceeds 50ms target"
            )
