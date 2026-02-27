"""Enrollment endpoints."""

from __future__ import annotations

import asyncio
import json
import logging
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import List

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from ..config import settings
from ..core import run_enroll_async
from ..matcher import gallery
from ..models import (
    BulkEnrollRequest,
    BulkEnrollResult,
    BulkEnrollSummary,
    EnrollRequest,
    EnrollResponse,
)
from ..pipeline import analyze, decode_jpeg_bytes

logger = logging.getLogger(__name__)

router = APIRouter(tags=["enroll"])

# ---------------------------------------------------------------------------
# Batch enrollment: 5 worker threads + shared pipeline with lock
# ---------------------------------------------------------------------------
# Open-IRIS IRISPipeline is NOT thread-safe (stores intermediate state on the
# instance).  We serialize pipeline calls with a lock while keeping file I/O,
# image decoding, and gallery operations parallel.  DB writes are queued and
# processed asynchronously so they never block the pipeline threads.
_BATCH_WORKERS = 5
_batch_pool = ThreadPoolExecutor(
    max_workers=_BATCH_WORKERS,
    thread_name_prefix="bulk-enroll",
)
_pipeline_lock = threading.Lock()


def _process_one(
    subject_id: str,
    eye_side: str,
    img_path_str: str,
    identity_id: str,
    display_name: str,
) -> BulkEnrollResult:
    """Worker: read image -> pipeline -> gallery check -> enroll.

    Runs in a batch thread.  Pipeline call is serialized via lock;
    everything else (file I/O, decode, gallery ops) runs in parallel.
    """
    result = BulkEnrollResult(
        subject_id=subject_id,
        eye_side=eye_side,
        filename=Path(img_path_str).name,
        identity_id=identity_id,
    )
    try:
        # File I/O + decode — parallel across threads
        img = decode_jpeg_bytes(Path(img_path_str).read_bytes())

        # Pipeline — serialized (singleton is not thread-safe)
        with _pipeline_lock:
            pipeline_result = analyze(img, eye_side=eye_side, image_id=identity_id)

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

    return result


@router.post("/enroll", response_model=EnrollResponse)
async def enroll_endpoint(req: EnrollRequest):
    """Enroll a new identity with an eye image."""
    return await run_enroll_async(req)


@router.post("/enroll/batch")
async def enroll_batch(req: BulkEnrollRequest):
    """Bulk-enroll subjects from a dataset via SSE streaming.

    5 worker threads consume from a queue.  Pipeline calls are serialized
    (Open-IRIS singleton is not thread-safe).  File I/O, image decoding,
    and gallery operations run in parallel.  DB writes are queued and
    processed asynchronously.
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

        # --- Async DB writer (processes writes one at a time) ---
        db_queue: asyncio.Queue = asyncio.Queue()

        async def _db_writer():
            while True:
                item = await db_queue.get()
                if item is None:
                    break
                tid, identity_id, name, eye_side = item
                try:
                    from ..db import ensure_identity, pack_codes, persist_template

                    entry = None
                    with gallery._lock:
                        for e in reversed(gallery._entries):
                            if e.template_id == tid:
                                entry = e
                                break
                    if entry and entry.template:
                        await ensure_identity(identity_id, name)
                        t = entry.template
                        iris_bytes = pack_codes(t.iris_codes)
                        mask_bytes = pack_codes(t.mask_codes)
                        c0 = t.iris_codes[0]
                        await persist_template(
                            template_id=tid,
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
                    logger.exception("DB persist failed for template %s", tid)

        db_task = asyncio.create_task(_db_writer()) if settings.db_url else None

        # --- Submit all work items to the 5-thread pool ---
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
                except Exception as exc:
                    # Should not happen (_process_one catches everything)
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
                    # Queue async DB write (non-blocking)
                    if db_task and result.template_id:
                        await db_queue.put((
                            result.template_id,
                            result.identity_id,
                            f"{req.dataset}:{result.subject_id}",
                            result.eye_side,
                        ))

                yield f"data: {result.json()}\n\n"

            # Wait for remaining DB writes to finish
            if db_task:
                await db_queue.put(None)  # poison pill
                await db_task

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
            if db_task and not db_task.done():
                await db_queue.put(None)
                db_task.cancel()

    return StreamingResponse(_stream(), media_type="text/event-stream")
