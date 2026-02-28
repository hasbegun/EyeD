"""Core analysis and enrollment logic shared by HTTP routes and NATS handlers."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from typing import Optional

from .config import settings
from .matcher import gallery
from .models import (
    AnalyzeRequest,
    AnalyzeResponse,
    EnrollRequest,
    EnrollResponse,
)
from .pipeline import analyze, decode_jpeg, serialize_template

logger = logging.getLogger(__name__)

pool = ThreadPoolExecutor(max_workers=1)


def run_analyze(
    jpeg_b64: str, eye_side: str, frame_id: str, device_id: str
) -> AnalyzeResponse:
    """Core analysis logic shared by HTTP and NATS handlers."""
    start = time.monotonic()

    try:
        img = decode_jpeg(jpeg_b64)
    except ValueError as e:
        return AnalyzeResponse(
            frame_id=frame_id, device_id=device_id, error=str(e)
        )

    result = analyze(img, eye_side=eye_side, image_id=frame_id)
    elapsed_ms = (time.monotonic() - start) * 1000

    if result.get("error"):
        return AnalyzeResponse(
            frame_id=frame_id,
            device_id=device_id,
            error=str(result["error"]),
            latency_ms=elapsed_ms,
        )

    template = result.get("iris_template")
    template_b64 = serialize_template(template)

    match_result = None
    if template is not None:
        match_result = gallery.match(template)

    return AnalyzeResponse(
        frame_id=frame_id,
        device_id=device_id,
        iris_template_b64=template_b64,
        match=match_result,
        latency_ms=elapsed_ms,
    )


def run_enroll_sync(req: EnrollRequest) -> EnrollResponse:
    """Core enrollment logic (synchronous — runs in thread pool)."""
    try:
        img = decode_jpeg(req.jpeg_b64)
    except ValueError as e:
        return EnrollResponse(
            identity_id=req.identity_id, template_id="", error=str(e)
        )

    result = analyze(img, eye_side=req.eye_side, image_id=req.identity_id)

    if result.get("error"):
        return EnrollResponse(
            identity_id=req.identity_id,
            template_id="",
            error=str(result["error"]),
        )

    template = result.get("iris_template")
    if template is None:
        return EnrollResponse(
            identity_id=req.identity_id,
            template_id="",
            error="Pipeline produced no template (segmentation may have failed)",
        )

    dup_id = gallery.check_duplicate(template)
    if dup_id is not None:
        dup_name = None
        with gallery._lock:
            for e in gallery._entries:
                if e.identity_id == dup_id:
                    dup_name = e.identity_name
                    break
        return EnrollResponse(
            identity_id=req.identity_id,
            template_id="",
            is_duplicate=True,
            duplicate_identity_id=dup_id,
            duplicate_identity_name=dup_name,
        )

    if settings.he_enabled:
        from .he_context import compute_popcounts, encrypt_iris_code

        he_iris_cts = [encrypt_iris_code(arr) for arr in template.iris_codes]
        he_mask_cts = [encrypt_iris_code(arr) for arr in template.mask_codes]
        iris_popcount = compute_popcounts(template.iris_codes)
        mask_popcount = compute_popcounts(template.mask_codes)

        template_id = gallery.enroll(
            identity_id=req.identity_id,
            identity_name=req.identity_name,
            eye_side=req.eye_side,
            template=None,
            he_iris_cts=he_iris_cts,
            he_mask_cts=he_mask_cts,
            iris_popcount=iris_popcount,
            mask_popcount=mask_popcount,
        )
    else:
        template_id = gallery.enroll(
            identity_id=req.identity_id,
            identity_name=req.identity_name,
            eye_side=req.eye_side,
            template=template,
        )

    return EnrollResponse(
        identity_id=req.identity_id,
        template_id=template_id,
    )


async def run_enroll_async(req: EnrollRequest) -> EnrollResponse:
    """Enrollment with DB persistence."""
    loop = asyncio.get_event_loop()
    response = await loop.run_in_executor(pool, run_enroll_sync, req)

    if response.template_id and settings.db_url:
        from .db import ensure_identity, pack_codes, persist_template

        try:
            entry = None
            with gallery._lock:
                for e in reversed(gallery._entries):
                    if e.template_id == response.template_id:
                        entry = e
                        break

            if entry and (entry.template or entry.he_iris_cts):
                await ensure_identity(req.identity_id, req.identity_name)

                if settings.he_enabled and entry.he_iris_cts:
                    from .he_context import IRIS_CODE_SHAPE, pack_he_codes_from_cts

                    iris_codes_bytes = pack_he_codes_from_cts(entry.he_iris_cts)
                    mask_codes_bytes = pack_he_codes_from_cts(entry.he_mask_cts)

                    await persist_template(
                        template_id=response.template_id,
                        identity_id=req.identity_id,
                        eye_side=req.eye_side,
                        iris_codes_bytes=iris_codes_bytes,
                        mask_codes_bytes=mask_codes_bytes,
                        width=IRIS_CODE_SHAPE[1],
                        height=IRIS_CODE_SHAPE[0],
                        n_scales=len(entry.he_iris_cts),
                        device_id=req.device_id,
                        iris_popcount=entry.iris_popcount,
                        mask_popcount=entry.mask_popcount,
                    )
                else:
                    t = entry.template
                    iris_codes_bytes = pack_codes(t.iris_codes)
                    mask_codes_bytes = pack_codes(t.mask_codes)

                    first_code = t.iris_codes[0]
                    height, width = first_code.shape[0], first_code.shape[1]
                    n_scales = len(t.iris_codes)

                    await persist_template(
                        template_id=response.template_id,
                        identity_id=req.identity_id,
                        eye_side=req.eye_side,
                        iris_codes_bytes=iris_codes_bytes,
                        mask_codes_bytes=mask_codes_bytes,
                        width=width,
                        height=height,
                        n_scales=n_scales,
                        device_id=req.device_id,
                    )
                logger.info("Template %s persisted to database", response.template_id)

                from . import nats_service

                if nats_service.nc and nats_service.nc.is_connected:
                    await nats_service.nc.publish(
                        settings.nats_subject_templates_changed,
                        json.dumps({
                            "node_id": nats_service.node_id,
                            "event": "enrolled",
                            "template_id": response.template_id,
                            "identity_id": req.identity_id,
                        }).encode(),
                    )
        except Exception:
            logger.exception("Failed to persist template %s to DB", response.template_id)

    return response


def log_match(response: AnalyzeResponse) -> None:
    """Enqueue match result for async DB logging."""
    if not settings.db_url or response.match is None:
        return
    from .db import match_log_writer

    match_log_writer.log({
        "probe_frame_id": response.frame_id,
        "matched_template_id": (
            _lookup_template_id(response.match.matched_identity_id)
            if response.match.is_match else None
        ),
        "matched_identity_id": (
            response.match.matched_identity_id if response.match.is_match else None
        ),
        "hamming_distance": response.match.hamming_distance,
        "is_match": response.match.is_match,
        "device_id": response.device_id,
        "latency_ms": int(response.latency_ms),
    })


def _lookup_template_id(identity_id: Optional[str]) -> Optional[str]:
    """Find the best template_id for a matched identity (for match_log FK)."""
    if not identity_id:
        return None
    with gallery._lock:
        for entry in gallery._entries:
            if entry.identity_id == identity_id:
                return entry.template_id
    return None


def build_archive_message(req: AnalyzeRequest, resp: AnalyzeResponse) -> dict:
    """Build archive message combining request data (raw JPEG) with results."""
    msg = {
        "frame_id": resp.frame_id,
        "device_id": resp.device_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "eye_side": req.eye_side,
        "raw_jpeg_b64": req.jpeg_b64,
        "quality_score": req.quality_score,
        "iris_template_b64": resp.iris_template_b64,
        "latency_ms": resp.latency_ms,
        "error": resp.error,
    }
    if resp.segmentation:
        msg["segmentation"] = resp.segmentation.dict()
    if resp.match:
        msg["match"] = resp.match.dict()
    return msg
