"""Shared pytest fixtures for iris-engine tests."""

from __future__ import annotations

import base64
import os
from pathlib import Path

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient


@pytest.fixture(scope="session")
def app():
    """Create the FastAPI app for testing."""
    # Set test environment before importing
    os.environ.setdefault("EYED_NATS_URL", "nats://localhost:4222")
    os.environ.setdefault("EYED_RUNTIME", "cpu")

    from src.main import app

    return app


@pytest.fixture(scope="session")
def client(app):
    """HTTP test client."""
    return TestClient(app)


@pytest.fixture
def sample_eye_image() -> np.ndarray:
    """Generate a synthetic grayscale 'eye' image for testing.

    Creates a simple circular pattern resembling an iris/pupil
    structure. Not realistic, but sufficient for testing pipeline
    plumbing and error handling.
    """
    h, w = 480, 640
    img = np.zeros((h, w), dtype=np.uint8)

    # Background (sclera-like)
    img[:] = 200

    cy, cx = h // 2, w // 2

    # Iris (dark ring)
    y, x = np.ogrid[:h, :w]
    iris_r = 100
    pupil_r = 40
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)

    iris_mask = dist < iris_r
    img[iris_mask] = 120

    # Pupil (black center)
    pupil_mask = dist < pupil_r
    img[pupil_mask] = 30

    # Add some texture to the iris region
    iris_ring = iris_mask & ~pupil_mask
    noise = np.random.RandomState(42).randint(0, 40, (h, w), dtype=np.uint8)
    img[iris_ring] = np.clip(img[iris_ring].astype(int) + noise[iris_ring] - 20, 0, 255).astype(
        np.uint8
    )

    return img


@pytest.fixture
def sample_jpeg_b64(sample_eye_image) -> str:
    """Base64-encoded JPEG of the sample eye image."""
    import cv2

    _, buf = cv2.imencode(".jpg", sample_eye_image, [cv2.IMWRITE_JPEG_QUALITY, 90])
    return base64.b64encode(buf.tobytes()).decode("ascii")


@pytest.fixture
def sample_jpeg_bytes(sample_eye_image) -> bytes:
    """Raw JPEG bytes of the sample eye image."""
    import cv2

    _, buf = cv2.imencode(".jpg", sample_eye_image, [cv2.IMWRITE_JPEG_QUALITY, 90])
    return buf.tobytes()


@pytest.fixture(scope="session")
def casia_root():
    """Path to CASIA1 dataset. Skips test if not found.

    Checks Docker path first (/data/Iris/CASIA1), then local dev path.
    """
    candidates = [
        Path("/data/Iris/CASIA1"),  # Docker mount
        Path(__file__).resolve().parents[2] / "data" / "Iris" / "CASIA1",  # Local
    ]
    for p in candidates:
        if p.is_dir():
            return p
    pytest.skip("CASIA1 dataset not found")


@pytest.fixture(scope="session")
def casia_subjects(casia_root):
    """Load CASIA1 images grouped by (subject_id, eye_side).

    Returns dict: {(subject_id, eye_side): [np.ndarray, ...]}
    Naming convention: {ID:03d}_{eye}_{num}.jpg  (eye: 1=left, 2=right)
    """
    eye_map = {"1": "left", "2": "right"}
    subjects: dict[tuple[str, str], list[np.ndarray]] = {}

    for subject_dir in sorted(casia_root.iterdir()):
        if not subject_dir.is_dir():
            continue
        for img_path in sorted(subject_dir.glob("*.jpg")):
            parts = img_path.stem.split("_")
            if len(parts) < 3:
                continue
            subject_id = parts[0]
            eye_side = eye_map.get(parts[1], "left")
            key = (subject_id, eye_side)
            img = cv2.imread(str(img_path), cv2.IMREAD_GRAYSCALE)
            if img is not None:
                subjects.setdefault(key, []).append(img)

    assert len(subjects) > 0, "No CASIA1 images loaded"
    return subjects


@pytest.fixture(scope="session")
def mmu2_root():
    """Path to MMU2 dataset. Skips test if not found."""
    candidates = [
        Path("/data/Iris/MMU2"),  # Docker mount
        Path(__file__).resolve().parents[2] / "data" / "Iris" / "MMU2",  # Local
    ]
    for p in candidates:
        if p.is_dir():
            return p
    pytest.skip("MMU2 dataset not found")


@pytest.fixture(scope="session")
def mmu2_subjects(mmu2_root):
    """Load MMU2 images grouped by (subject_id, eye_side).

    Returns dict: {(subject_id, eye_side): [np.ndarray, ...]}
    Naming: {subject_id}{eye:02d}{image:02d}.bmp  (eye: 01=left, 02=right)
    Directory per subject (1-100), 5 images per eye, BMP format.
    """
    eye_map = {"01": "left", "02": "right"}
    subjects: dict[tuple[str, str], list[np.ndarray]] = {}

    for subject_dir in sorted(mmu2_root.iterdir()):
        if not subject_dir.is_dir():
            continue
        subject_id = subject_dir.name
        for img_path in sorted(subject_dir.glob("*.bmp")):
            # Last 4 chars of stem: EEII (eye + image number)
            stem = img_path.stem
            if len(stem) < 4:
                continue
            eye_code = stem[-4:-2]
            eye_side = eye_map.get(eye_code, "left")
            key = (subject_id, eye_side)
            img = cv2.imread(str(img_path), cv2.IMREAD_GRAYSCALE)
            if img is not None:
                subjects.setdefault(key, []).append(img)

    assert len(subjects) > 0, "No MMU2 images loaded"
    return subjects
