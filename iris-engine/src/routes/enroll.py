"""Enrollment endpoints."""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import uuid
from pathlib import Path
from typing import List

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from ..config import settings
from ..core import pool, run_enroll_async
from ..matcher import gallery
from ..models import (
    BulkEnrollRequest,
    BulkEnrollResult,
    BulkEnrollSummary,
    EnrollRequest,
    EnrollResponse,
)
from ..pipeline import analyze, decode_jpeg

logger = logging.getLogger(__name__)

router = APIRouter(tags=["enroll"])


@router.post("/enroll", response_model=EnrollResponse)
async def enroll_endpoint(req: EnrollRequest):
    """Enroll a new identity with an eye image."""
    return await run_enroll_async(req)


@router.post("/enroll/batch")
async def enroll_batch(req: BulkEnrollRequest):
    """Bulk-enroll subjects from a dataset directory via SSE streaming."""
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

        has_eye_subdirs = False
        for child in subject_dir.iterdir():
            if child.is_dir() and child.name.lower() in _LR_DIR_MAP:
                has_eye_subdirs = True
                break

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
        from . import datasets as ds_mod

        loop = asyncio.get_event_loop()
        total = len(work)
        enrolled = 0
        duplicates = 0
        errors = 0

        ns = uuid.uuid5(uuid.NAMESPACE_URL, f"eyed:bulk:{req.dataset}")

        for subject_id, eye_side, img_path in work:
            identity_id = str(uuid.uuid5(ns, subject_id))
            result = BulkEnrollResult(
                subject_id=subject_id,
                eye_side=eye_side,
                filename=img_path.name,
                identity_id=identity_id,
            )
            try:
                jpeg_bytes = img_path.read_bytes()
                jpeg_b64 = base64.b64encode(jpeg_bytes).decode("ascii")

                img = decode_jpeg(jpeg_b64)
                pipeline_result = await loop.run_in_executor(
                    pool,
                    lambda: analyze(img, eye_side=eye_side, image_id=identity_id),
                )

                if pipeline_result.get("error"):
                    result.error = str(pipeline_result["error"])
                    errors += 1
                else:
                    template = pipeline_result.get("iris_template")
                    if template is None:
                        result.error = "Pipeline produced no template"
                        errors += 1
                    else:
                        dup_id = gallery.check_duplicate(template)
                        if dup_id is not None:
                            result.is_duplicate = True
                            result.duplicate_identity_id = dup_id
                            duplicates += 1
                        else:
                            display_name = f"{req.dataset}:{subject_id}"
                            tid = gallery.enroll(
                                identity_id=identity_id,
                                identity_name=display_name,
                                eye_side=eye_side,
                                template=template,
                            )
                            result.template_id = tid

                            if settings.db_url:
                                try:
                                    from ..db import (
                                        ensure_identity,
                                        pack_codes,
                                        persist_template,
                                    )

                                    entry = None
                                    with gallery._lock:
                                        for e in reversed(gallery._entries):
                                            if e.template_id == tid:
                                                entry = e
                                                break
                                    if entry and entry.template:
                                        await ensure_identity(identity_id, display_name)
                                        t = entry.template
                                        iris_codes_bytes = pack_codes(t.iris_codes)
                                        mask_codes_bytes = pack_codes(t.mask_codes)
                                        first_code = t.iris_codes[0]
                                        await persist_template(
                                            template_id=tid,
                                            identity_id=identity_id,
                                            eye_side=eye_side,
                                            iris_codes_bytes=iris_codes_bytes,
                                            mask_codes_bytes=mask_codes_bytes,
                                            width=first_code.shape[1],
                                            height=first_code.shape[0],
                                            n_scales=len(t.iris_codes),
                                            device_id="bulk-enroll",
                                        )
                                except Exception:
                                    logger.exception(
                                        "DB persist failed for %s/%s (template in memory only)",
                                        subject_id, eye_side,
                                    )
                            enrolled += 1
            except Exception as exc:
                result.error = str(exc)
                errors += 1
                logger.exception("Bulk enroll error for %s/%s", subject_id, eye_side)

            yield f"data: {result.json()}\n\n"

        # Publish ONE templates.changed event for the whole batch
        if enrolled > 0:
            from .. import nats_service

            if nats_service.nc and nats_service.nc.is_connected:
                await nats_service.nc.publish(
                    settings.nats_subject_templates_changed,
                    json.dumps({
                        "node_id": nats_service.node_id,
                        "event": "bulk_enrolled",
                        "count": enrolled,
                    }).encode(),
                )

        summary = BulkEnrollSummary(
            total=total, enrolled=enrolled, duplicates=duplicates, errors=errors,
        )
        yield f"event: done\ndata: {summary.json()}\n\n"

    return StreamingResponse(_stream(), media_type="text/event-stream")
