"""Enrollment endpoints."""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import List

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from ..config import settings
from ..core import run_enroll_async
from ..db import pack_codes
from ..matcher import gallery
from ..models import (
    BulkEnrollRequest,
    BulkEnrollResult,
    BulkEnrollSummary,
    EnrollRequest,
    EnrollResponse,
)
from ..pipeline import analyze, decode_jpeg_bytes
from ..pipeline_pool import get_pipeline_pool

logger = logging.getLogger(__name__)

router = APIRouter(tags=["enroll"])

# ---------------------------------------------------------------------------
# Batch enrollment: N worker threads + pipeline pool (true parallelism)
# ---------------------------------------------------------------------------
# Each worker borrows its own IRISPipeline instance from the pool, so all
# threads run truly in parallel with no global lock.  DB writes go through
# Redis for speed, then drain to Postgres in background batches.
_batch_pool = ThreadPoolExecutor(
    max_workers=settings.batch_workers,
    thread_name_prefix="bulk-enroll",
)


def _process_one(
    subject_id: str,
    eye_side: str,
    img_path_str: str,
    identity_id: str,
    display_name: str,
) -> BulkEnrollResult:
    """Worker: read image -> pipeline (from pool) -> gallery check -> enroll.

    Runs in a batch thread.  Each thread borrows its own pipeline instance
    from the pool, so all threads run truly in parallel.
    """
    result = BulkEnrollResult(
        subject_id=subject_id,
        eye_side=eye_side,
        filename=Path(img_path_str).name,
        identity_id=identity_id,
    )
    pool = get_pipeline_pool()
    pipe = None
    try:
        # File I/O + decode — parallel across threads
        img = decode_jpeg_bytes(Path(img_path_str).read_bytes())

        # Acquire pipeline from pool (blocks if all busy, no global lock)
        pipe = pool.acquire(timeout=30.0)
        pipeline_result = analyze(
            img, eye_side=eye_side, image_id=identity_id, pipeline_instance=pipe,
        )
        # Release immediately after use
        pool.release(pipe)
        pipe = None

        if pipeline_result.get("error"):
            result.error = str(pipeline_result["error"])
            return result

        template = pipeline_result.get("iris_template")
        if template is None:
            result.error = "Pipeline produced no template"
            return result

        # Gallery ops — thread-safe (internal locks)
        dup_id = gallery.check_duplicate(template)
        if dup_id is not None:
            result.is_duplicate = True
            result.duplicate_identity_id = dup_id
        else:
            tid = gallery.enroll(
                identity_id=identity_id,
                identity_name=display_name,
                eye_side=eye_side,
                template=template,
            )
            result.template_id = tid
    except Exception as exc:
        result.error = str(exc)
        logger.warning("Bulk enroll error for %s/%s: %s", subject_id, eye_side, exc)
    finally:
        # Ensure pipeline is returned even on error
        if pipe is not None:
            pool.release(pipe)

    return result


@router.post("/enroll", response_model=EnrollResponse)
async def enroll_endpoint(req: EnrollRequest):
    """Enroll a new identity with an eye image."""
    return await run_enroll_async(req)


@router.post("/enroll/batch")
async def enroll_batch(req: BulkEnrollRequest):
    """Bulk-enroll subjects from a dataset via SSE streaming.

    Uses pipeline pool for true parallelism (each thread gets its own
    ONNX session).  DB writes go through Redis for speed, then drain
    to Postgres in background batches.
    """
    from .datasets import _LR_DIR_MAP, _parse_eye_side, _validate_dataset_name

    ds_path = _validate_dataset_name(req.dataset)
    exts = (".jpg", ".jpeg", ".bmp", ".png")

    # Build work list: [(subject_id, eye_side, image_path), ...]
    work: List[tuple] = []
    for subject_dir in sorted(ds_path.iterdir()):
        if not subject_dir.is_dir() or subject_dir.name.startswith("."):
            continue
        if req.subjects and subject_dir.name not in req.subjects:
            continue

        has_eye_subdirs = any(
            child.is_dir() and child.name.lower() in _LR_DIR_MAP
            for child in subject_dir.iterdir()
        )

        if has_eye_subdirs:
            for eye_dir in sorted(subject_dir.iterdir()):
                if not eye_dir.is_dir():
                    continue
                side = _LR_DIR_MAP.get(eye_dir.name.lower())
                if not side:
                    continue
                imgs = sorted(
                    f for f in eye_dir.iterdir()
                    if f.is_file() and f.suffix.lower() in exts
                )
                if imgs:
                    work.append((subject_dir.name, side, imgs[0]))
        else:
            imgs = sorted(
                f for f in subject_dir.iterdir()
                if f.is_file() and f.suffix.lower() in exts
            )
            if imgs:
                side = _parse_eye_side(req.dataset, imgs[0].name)
                work.append((subject_dir.name, side, imgs[0]))

    async def _stream():
        loop = asyncio.get_event_loop()
        total = len(work)
        enrolled_count = 0
        dup_count = 0
        error_count = 0

        ns = uuid.uuid5(uuid.NAMESPACE_URL, f"eyed:bulk:{req.dataset}")

        # Submit all work items to thread pool
        futures = []
        for subject_id, eye_side, img_path in work:
            identity_id = str(uuid.uuid5(ns, subject_id))
            display_name = f"{req.dataset}:{subject_id}"
            future = loop.run_in_executor(
                _batch_pool,
                _process_one,
                subject_id, eye_side, str(img_path), identity_id, display_name,
            )
            futures.append(future)

        try:
            # Emit results in completion order (fastest threads first)
            for coro in asyncio.as_completed(futures):
                try:
                    result: BulkEnrollResult = await coro
                except Exception:
                    logger.exception("Unexpected batch error")
                    error_count += 1
                    continue

                # Update counters
                if result.error:
                    error_count += 1
                elif result.is_duplicate:
                    dup_count += 1
                else:
                    enrolled_count += 1
                    # Push to Redis (sub-ms) for background DB drain
                    if result.template_id:
                        await _push_persistence(
                            result.template_id,
                            result.identity_id,
                            f"{req.dataset}:{result.subject_id}",
                            result.eye_side,
                        )

                yield f"data: {result.json()}\n\n"

            # Notify other nodes
            if enrolled_count > 0:
                from .. import nats_service

                if nats_service.nc and nats_service.nc.is_connected:
                    await nats_service.nc.publish(
                        settings.nats_subject_templates_changed,
                        json.dumps({
                            "node_id": nats_service.node_id,
                            "event": "bulk_enrolled",
                            "count": enrolled_count,
                        }).encode(),
                    )

            summary = BulkEnrollSummary(
                total=total,
                enrolled=enrolled_count,
                duplicates=dup_count,
                errors=error_count,
            )
            yield f"event: done\ndata: {summary.json()}\n\n"

        finally:
            # Cancel pending thread pool futures on client disconnect
            for f in futures:
                f.cancel()

    return StreamingResponse(_stream(), media_type="text/event-stream")


async def _push_persistence(
    template_id: str,
    identity_id: str,
    display_name: str,
    eye_side: str,
) -> None:
    """Push enrollment data to Redis (preferred) or write directly to DB."""
    # Look up the template entry in gallery
    entry = None
    with gallery._lock:
        for e in reversed(gallery._entries):
            if e.template_id == template_id:
                entry = e
                break

    if not entry or not entry.template:
        return

    t = entry.template
    iris_bytes = pack_codes(t.iris_codes)
    mask_bytes = pack_codes(t.mask_codes)
    c0 = t.iris_codes[0]

    data = {
        "template_id": template_id,
        "identity_id": identity_id,
        "identity_name": display_name,
        "eye_side": eye_side,
        "iris_codes_b64": base64.b64encode(iris_bytes).decode("ascii"),
        "mask_codes_b64": base64.b64encode(mask_bytes).decode("ascii"),
        "width": c0.shape[1],
        "height": c0.shape[0],
        "n_scales": len(t.iris_codes),
        "quality_score": 0.0,
        "device_id": "bulk-enroll",
    }

    # Prefer Redis (sub-ms), fall back to direct DB write
    if settings.redis_url:
        try:
            from ..redis_cache import push_enrollment

            await push_enrollment(data)
            return
        except Exception:
            logger.warning("Redis push failed, falling back to direct DB write")

    # Direct DB write fallback (when Redis is not configured or fails)
    if settings.db_url:
        try:
            from ..db import ensure_identity, persist_template

            await ensure_identity(identity_id, display_name)
            await persist_template(
                template_id=template_id,
                identity_id=identity_id,
                eye_side=eye_side,
                iris_codes_bytes=iris_bytes,
                mask_codes_bytes=mask_bytes,
                width=c0.shape[1],
                height=c0.shape[0],
                n_scales=len(t.iris_codes),
                device_id="bulk-enroll",
            )
        except Exception:
            logger.exception("DB persist failed for template %s", template_id)
