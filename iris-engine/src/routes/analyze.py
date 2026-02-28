"""Analysis endpoints."""

from __future__ import annotations

import base64
import uuid

import cv2
import numpy as np
from fastapi import APIRouter, File, Form, UploadFile

from ..core import log_match, run_analyze
from ..matcher import gallery
from ..models import AnalyzeRequest, AnalyzeResponse, DetailedAnalyzeResponse
from ..pipeline import analyze_detailed, serialize_template

router = APIRouter(tags=["analyze"])


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze_endpoint(
    file: UploadFile = File(...),
    eye_side: str = Form("left"),
    frame_id: str = Form(""),
    device_id: str = Form("local"),
):
    """Analyze an eye image via HTTP upload."""
    jpeg_bytes = await file.read()
    jpeg_b64 = base64.b64encode(jpeg_bytes).decode("ascii")

    if not frame_id:
        frame_id = f"http-{uuid.uuid4().hex[:8]}"

    response = run_analyze(jpeg_b64, eye_side, frame_id, device_id)
    log_match(response)
    return response


@router.post("/analyze/json", response_model=AnalyzeResponse)
async def analyze_json_endpoint(req: AnalyzeRequest):
    """Analyze an eye image via JSON request with base64-encoded JPEG."""
    if not req.frame_id:
        req.frame_id = f"json-{uuid.uuid4().hex[:8]}"

    response = run_analyze(req.jpeg_b64, req.eye_side, req.frame_id, req.device_id)
    log_match(response)
    return response


@router.post("/analyze/detailed", response_model=DetailedAnalyzeResponse)
async def analyze_detailed_endpoint(
    file: UploadFile = File(...),
    eye_side: str = Form("left"),
    frame_id: str = Form(""),
    device_id: str = Form("local"),
):
    """Run detailed pipeline analysis with all intermediate visualizations."""
    img_bytes = await file.read()

    try:
        arr = np.frombuffer(img_bytes, dtype=np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
        if img is None:
            raise ValueError("Failed to decode image")
    except ValueError as e:
        return DetailedAnalyzeResponse(
            frame_id=frame_id or f"det-{uuid.uuid4().hex[:8]}",
            device_id=device_id,
            error=str(e),
        )

    if not frame_id:
        frame_id = f"det-{uuid.uuid4().hex[:8]}"

    result = analyze_detailed(img, eye_side=eye_side, image_id=frame_id)

    template = result.get("iris_template")
    template_b64 = serialize_template(template)

    match_result = None
    if template is not None:
        match_result = gallery.match(template)

    error_val = result.get("error")
    error_str = None
    if error_val and template is None:
        if isinstance(error_val, dict):
            error_str = error_val.get("message", str(error_val))
        else:
            error_str = str(error_val)

    return DetailedAnalyzeResponse(
        frame_id=frame_id,
        device_id=device_id,
        iris_template_b64=template_b64,
        match=match_result,
        latency_ms=result.get("latency_ms", 0),
        error=error_str,
        geometry=result.get("geometry"),
        quality=result.get("quality"),
        original_image_b64=result.get("original_image_b64"),
        segmentation_overlay_b64=result.get("segmentation_overlay_b64"),
        normalized_iris_b64=result.get("normalized_iris_b64"),
        iris_code_b64=result.get("iris_code_b64"),
        noise_mask_b64=result.get("noise_mask_b64"),
    )
