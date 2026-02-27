"""Wraps Open-IRIS pipeline with correct API calls."""

from __future__ import annotations

import base64
import logging
import time
from typing import Any, Optional

import cv2
import numpy as np

from .config import settings

logger = logging.getLogger(__name__)

# Open-IRIS imports — loaded lazily to allow health checks before model is ready
_iris_module = None
_pipeline = None


def _get_iris_module():
    global _iris_module
    if _iris_module is None:
        import iris

        _iris_module = iris
    return _iris_module


def _build_pipeline_config(runtime: str) -> Optional[dict[str, Any]]:
    """Build a custom pipeline config to override ONNX execution provider.

    Open-IRIS hardcodes CPUExecutionProvider in its default config.
    To use CUDA or CoreML, we need to provide a custom config that
    overrides the segmentation node's provider list.
    """
    if runtime == "cpu":
        return None  # Use default config

    providers_map = {
        "cuda": ["CUDAExecutionProvider", "CPUExecutionProvider"],
        "coreml": ["CoreMLExecutionProvider", "CPUExecutionProvider"],
    }

    providers = providers_map.get(runtime)
    if providers is None:
        logger.warning("Unknown runtime '%s', falling back to CPU", runtime)
        return None

    # Override the segmentation node's execution providers.
    # This config structure follows Open-IRIS's pipeline YAML format.
    return {
        "metadata": {"pipeline_name": "eyed_iris_pipeline"},
        "pipeline": [
            {
                "name": "segmentation",
                "algorithm": {
                    "class_name": "iris.nodes.segmentation.onnx_multilabel_segmentation.ONNXMultilabelSegmentation",
                    "params": {"providers": providers},
                },
            },
        ],
    }


def get_pipeline():
    """Get or create the singleton IRISPipeline instance.

    NOTE: The singleton is NOT thread-safe.  Do not call from multiple
    threads concurrently — use :func:`create_pipeline` to obtain
    per-thread instances for parallel batch work.
    """
    global _pipeline
    if _pipeline is not None:
        return _pipeline

    iris = _get_iris_module()

    config = _build_pipeline_config(settings.eyed_runtime)
    logger.info("Initializing Open-IRIS pipeline (runtime=%s)", settings.eyed_runtime)

    start = time.monotonic()
    _pipeline = iris.IRISPipeline(config=config)
    elapsed = (time.monotonic() - start) * 1000
    logger.info("Pipeline loaded in %.0f ms", elapsed)

    return _pipeline


def create_pipeline():
    """Create a **new** IRISPipeline instance (for per-thread use).

    Each instance owns its own ONNX session and intermediate state,
    so concurrent calls from different threads are safe.
    """
    iris = _get_iris_module()
    config = _build_pipeline_config(settings.eyed_runtime)
    return iris.IRISPipeline(config=config)


def is_pipeline_loaded() -> bool:
    return _pipeline is not None


def decode_jpeg(jpeg_b64: str) -> np.ndarray:
    """Decode base64 JPEG to grayscale numpy array."""
    jpeg_bytes = base64.b64decode(jpeg_b64)
    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise ValueError("Failed to decode JPEG image")
    return img


def decode_jpeg_bytes(jpeg_bytes: bytes) -> np.ndarray:
    """Decode raw JPEG bytes to grayscale numpy array."""
    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise ValueError("Failed to decode JPEG image")
    return img


def analyze(
    img_data: np.ndarray,
    eye_side: str = "left",
    image_id: Optional[str] = None,
) -> dict:
    """Run the full Open-IRIS pipeline on a grayscale eye image.

    Args:
        img_data: Grayscale numpy array (H, W).
        eye_side: "left" or "right".
        image_id: Optional identifier for tracing this image through the pipeline.

    Returns:
        Open-IRIS pipeline output dict with keys:
        - "error": None or error info
        - "iris_template": IrisTemplate or None
        - "metadata": dict with pipeline trace info (includes image_id)
    """
    iris = _get_iris_module()
    pipeline = get_pipeline()

    ir_image = iris.IRImage(img_data=img_data, eye_side=eye_side, image_id=image_id)

    start = time.monotonic()
    result = pipeline(ir_image)
    elapsed_ms = (time.monotonic() - start) * 1000

    logger.debug("Pipeline completed in %.1f ms", elapsed_ms)
    return result


def serialize_template(template) -> Optional[str]:
    """Serialize an Open-IRIS IrisTemplate to base64 string for transport."""
    if template is None:
        return None

    try:
        serialized = template.serialize()
        return base64.b64encode(
            str(serialized).encode("utf-8")
        ).decode("ascii")
    except Exception:
        logger.exception("Failed to serialize iris template")
        return None


def deserialize_template(template_b64: str):
    """Deserialize a base64 iris template back to Open-IRIS IrisTemplate."""
    iris = _get_iris_module()
    raw = base64.b64decode(template_b64).decode("utf-8")
    serialized = eval(raw)  # noqa: S307 — trusted internal data only
    return iris.IrisTemplate.deserialize(serialized)


# --- Detailed analysis helpers ---


def _ndarray_to_png_b64(arr: np.ndarray) -> str:
    """Encode a numpy array as base64 PNG."""
    if arr.dtype == bool:
        arr = arr.astype(np.uint8) * 255
    _, buf = cv2.imencode(".png", arr)
    return base64.b64encode(buf.tobytes()).decode("ascii")


def _render_segmentation_overlay(
    original: np.ndarray,
    eye_centers=None,
    geometry=None,
) -> str:
    """Draw pupil/iris contours and centers on the original image, return base64 PNG.

    Works with partial data: eye_centers only, geometry only, or both.
    """
    vis = cv2.cvtColor(original, cv2.COLOR_GRAY2BGR)

    if geometry is not None:
        # Draw iris contour (orange — high contrast on grayscale)
        iris_pts = geometry.iris_array.astype(np.int32).reshape(-1, 1, 2)
        cv2.polylines(vis, [iris_pts], isClosed=True, color=(0, 140, 255), thickness=2)

        # Draw pupil contour (green)
        pupil_pts = geometry.pupil_array.astype(np.int32).reshape(-1, 1, 2)
        cv2.polylines(vis, [pupil_pts], isClosed=True, color=(0, 255, 0), thickness=2)

    if eye_centers is not None:
        # Draw centers
        px, py = int(eye_centers.pupil_x), int(eye_centers.pupil_y)
        ix, iy = int(eye_centers.iris_x), int(eye_centers.iris_y)
        cv2.drawMarker(vis, (px, py), (0, 255, 0), cv2.MARKER_CROSS, 10, 2)
        cv2.drawMarker(vis, (ix, iy), (0, 140, 255), cv2.MARKER_CROSS, 10, 2)

    _, buf = cv2.imencode(".png", vis)
    return base64.b64encode(buf.tobytes()).decode("ascii")


def _render_iris_code(template) -> Optional[str]:
    """Render the first iris code as a black/white image, return base64 PNG."""
    if template is None or not template.iris_codes:
        return None
    code = template.iris_codes[0]  # shape (16, 256, 2)
    # Flatten last dim: interleave real/imaginary parts
    flat = code.reshape(code.shape[0], -1)  # (16, 512)
    img = (flat.astype(np.uint8)) * 255
    # Scale up for visibility
    img = cv2.resize(img, (512, 128), interpolation=cv2.INTER_NEAREST)
    return _ndarray_to_png_b64(img)


def analyze_detailed(
    img_data: np.ndarray,
    eye_side: str = "left",
    image_id: Optional[str] = None,
) -> dict:
    """Run pipeline and extract all intermediate results for visualization.

    Returns a dict with:
        - All keys from normal analyze() (error, iris_template, metadata)
        - "geometry": EyeGeometry dict
        - "quality": QualityMetrics dict
        - "original_image_b64": base64 PNG of input
        - "segmentation_overlay_b64": base64 PNG with pupil/iris contours
        - "normalized_iris_b64": base64 PNG of normalized iris pattern
        - "iris_code_b64": base64 PNG of iris code
        - "noise_mask_b64": base64 PNG of noise mask
    """
    iris_mod = _get_iris_module()
    pipeline = get_pipeline()

    ir_image = iris_mod.IRImage(img_data=img_data, eye_side=eye_side, image_id=image_id)

    start = time.monotonic()
    try:
        result = pipeline(ir_image)
    except Exception as e:
        # Safety net: pipeline should catch internally, but just in case
        logger.exception("Pipeline raised unexpected exception")
        elapsed_ms = (time.monotonic() - start) * 1000
        return {
            "error": str(e),
            "iris_template": None,
            "latency_ms": elapsed_ms,
            "original_image_b64": _ndarray_to_png_b64(img_data),
        }
    elapsed_ms = (time.monotonic() - start) * 1000

    logger.debug("Detailed pipeline completed in %.1f ms", elapsed_ms)

    detailed = dict(result)
    detailed["latency_ms"] = elapsed_ms

    # Original image
    detailed["original_image_b64"] = _ndarray_to_png_b64(img_data)

    # Extract intermediate results from call trace
    trace = pipeline.call_trace

    eye_centers = trace.get("eye_center_estimation")
    geometry_polys = trace.get("geometry_estimation")
    normalized = trace.get("normalization")
    noise_mask = trace.get("noise_masks_aggregation")
    pupil_iris_prop = trace.get("pupil_to_iris_property_estimation")
    offgaze = trace.get("offgaze_estimation")
    occlusion90 = trace.get("occlusion90_calculator")
    occlusion30 = trace.get("occlusion30_calculator")
    sharpness = trace.get("sharpness_estimation")
    eye_orient = trace.get("eye_orientation")

    # Segmentation overlay — render with whatever data is available
    if eye_centers is not None or geometry_polys is not None:
        try:
            detailed["segmentation_overlay_b64"] = _render_segmentation_overlay(
                img_data, eye_centers, geometry_polys
            )
        except Exception:
            logger.exception("Failed to render segmentation overlay")

    # Geometry
    if eye_centers is not None and geometry_polys is not None:
        detailed["geometry"] = {
            "pupil_center": (eye_centers.pupil_x, eye_centers.pupil_y),
            "iris_center": (eye_centers.iris_x, eye_centers.iris_y),
            "pupil_radius": geometry_polys.pupil_diameter / 2.0,
            "iris_radius": geometry_polys.iris_diameter / 2.0,
            "eye_orientation": float(eye_orient.angle) if eye_orient else 0.0,
        }

    # Quality metrics
    if pupil_iris_prop is not None:
        detailed["quality"] = {
            "offgaze_score": float(offgaze.score) if offgaze else 0.0,
            "occlusion_90": float(occlusion90.visible_fraction) if occlusion90 else 0.0,
            "occlusion_30": float(occlusion30.visible_fraction) if occlusion30 else 0.0,
            "sharpness": float(sharpness.score) if sharpness else 0.0,
            "pupil_iris_ratio": float(pupil_iris_prop.pupil_to_iris_diameter_ratio),
        }

    # Normalized iris
    if normalized is not None:
        try:
            detailed["normalized_iris_b64"] = _ndarray_to_png_b64(
                normalized.normalized_image
            )
        except Exception:
            logger.exception("Failed to render normalized iris")

    # Iris code
    template = result.get("iris_template")
    if template is not None:
        try:
            detailed["iris_code_b64"] = _render_iris_code(template)
        except Exception:
            logger.exception("Failed to render iris code")

    # Noise mask
    if noise_mask is not None:
        try:
            detailed["noise_mask_b64"] = _ndarray_to_png_b64(noise_mask.mask)
        except Exception:
            logger.exception("Failed to render noise mask")

    return detailed
