"""Tests for iris-engine pipeline and HTTP endpoints."""

from __future__ import annotations

import base64
import io

import numpy as np
import pytest


class TestHealthEndpoints:
    """Test health check endpoints."""

    def test_alive(self, client):
        resp = client.get("/health/alive")
        assert resp.status_code == 200
        data = resp.json()
        assert data["alive"] is True

    def test_ready(self, client):
        resp = client.get("/health/ready")
        assert resp.status_code == 200
        data = resp.json()
        assert "pipeline_loaded" in data
        assert "nats_connected" in data


class TestAnalyzeEndpoint:
    """Test the /analyze HTTP endpoint."""

    def test_analyze_upload(self, client, sample_jpeg_bytes):
        resp = client.post(
            "/analyze",
            files={"file": ("eye.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
            data={"eye_side": "left"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "frame_id" in data
        assert "latency_ms" in data
        # Pipeline may or may not produce a template from synthetic image
        # but it should not crash
        assert data.get("error") is None or isinstance(data["error"], str)

    def test_analyze_json(self, client, sample_jpeg_b64):
        resp = client.post(
            "/analyze/json",
            json={
                "frame_id": "test-001",
                "device_id": "test",
                "jpeg_b64": sample_jpeg_b64,
                "eye_side": "left",
            },
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["frame_id"] == "test-001"
        assert data["device_id"] == "test"

    def test_analyze_invalid_jpeg(self, client):
        invalid_b64 = base64.b64encode(b"not a jpeg").decode()
        resp = client.post(
            "/analyze/json",
            json={
                "frame_id": "bad-001",
                "device_id": "test",
                "jpeg_b64": invalid_b64,
                "eye_side": "left",
            },
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["error"] is not None


class TestGalleryEndpoint:
    """Test gallery size endpoint."""

    def test_gallery_size(self, client):
        resp = client.get("/gallery/size")
        assert resp.status_code == 200
        data = resp.json()
        assert "gallery_size" in data
        assert isinstance(data["gallery_size"], int)


class TestImageDecoding:
    """Test JPEG decode utilities."""

    def test_decode_jpeg_valid(self, sample_jpeg_b64):
        from src.pipeline import decode_jpeg

        img = decode_jpeg(sample_jpeg_b64)
        assert isinstance(img, np.ndarray)
        assert img.ndim == 2  # grayscale
        assert img.shape[0] > 0 and img.shape[1] > 0

    def test_decode_jpeg_invalid(self):
        from src.pipeline import decode_jpeg

        with pytest.raises(ValueError, match="Failed to decode"):
            decode_jpeg(base64.b64encode(b"garbage").decode())

    def test_decode_jpeg_bytes_valid(self, sample_jpeg_bytes):
        from src.pipeline import decode_jpeg_bytes

        img = decode_jpeg_bytes(sample_jpeg_bytes)
        assert isinstance(img, np.ndarray)
        assert img.ndim == 2
