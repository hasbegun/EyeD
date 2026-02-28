"""Gallery management endpoints."""

from __future__ import annotations

import json

import cv2
import numpy as np
from fastapi import APIRouter, HTTPException

from ..config import settings
from ..matcher import gallery
from ..models import TemplateDetailResponse

router = APIRouter(prefix="/gallery", tags=["gallery"])


@router.get("/size")
async def gallery_size():
    """Return the number of enrolled templates."""
    return {"gallery_size": gallery.size}


@router.get("/list")
async def gallery_list():
    """Return list of enrolled identities with their templates."""
    if settings.db_url:
        from ..db import list_identities

        return await list_identities()

    # Fallback: build from in-memory gallery
    with gallery._lock:
        entries = list(gallery._entries)
    identities: dict[str, dict] = {}
    for e in entries:
        if e.identity_id not in identities:
            identities[e.identity_id] = {
                "identity_id": e.identity_id,
                "name": e.identity_name,
                "templates": [],
            }
        identities[e.identity_id]["templates"].append({
            "template_id": e.template_id,
            "eye_side": e.eye_side,
        })
    return list(identities.values())


@router.delete("/delete/{identity_id}")
async def gallery_delete(identity_id: str):
    """Delete an identity and all its templates."""
    removed = gallery.remove_identity(identity_id)

    if settings.db_url:
        from ..db import delete_identity

        await delete_identity(identity_id)

    if removed > 0:
        from .. import nats_service

        if nats_service.nc and nats_service.nc.is_connected:
            await nats_service.nc.publish(
                settings.nats_subject_templates_changed,
                json.dumps({
                    "node_id": nats_service.node_id,
                    "event": "deleted",
                    "identity_id": identity_id,
                }).encode(),
            )

    return {"deleted": removed > 0, "templates_removed": removed}


@router.get("/template/{template_id}", response_model=TemplateDetailResponse)
async def gallery_template_detail(template_id: str):
    """Return stored template data with rendered iris code and mask images."""
    from ..db import load_template, unpack_codes
    from ..pipeline import _ndarray_to_png_b64, _render_iris_code

    row = await load_template(template_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Template not found")

    iris_raw = bytes(row["iris_codes"])
    mask_raw = bytes(row["mask_codes"])

    if settings.he_enabled:
        from ..he_context import is_he_blob

        if is_he_blob(iris_raw):
            from ..key_client import request_decrypt_template

            decrypted = await request_decrypt_template(iris_raw, mask_raw)
            if decrypted is None:
                raise HTTPException(
                    status_code=503,
                    detail="Key-service unavailable for template decryption",
                )
            iris_codes = decrypted["iris_codes"]
            mask_codes = decrypted["mask_codes"]
        else:
            iris_codes = unpack_codes(iris_raw)
            mask_codes = unpack_codes(mask_raw)
    else:
        iris_codes = unpack_codes(iris_raw)
        mask_codes = unpack_codes(mask_raw)

    iris_code_b64 = None
    if iris_codes:
        from iris import IrisTemplate

        template = IrisTemplate(
            iris_codes=iris_codes,
            mask_codes=mask_codes,
            iris_code_version="v0.1",
        )
        iris_code_b64 = _render_iris_code(template)

    mask_code_b64 = None
    if mask_codes:
        code = mask_codes[0]
        flat = code.reshape(code.shape[0], -1)
        img = (flat.astype(np.uint8)) * 255
        img = cv2.resize(img, (512, 128), interpolation=cv2.INTER_NEAREST)
        mask_code_b64 = _ndarray_to_png_b64(img)

    return TemplateDetailResponse(
        template_id=str(row["template_id"]),
        identity_id=str(row["identity_id"]),
        identity_name=row["name"] or "",
        eye_side=row["eye_side"],
        width=row["width"],
        height=row["height"],
        n_scales=row["n_scales"],
        quality_score=row["quality_score"],
        device_id=row["device_id"] or "",
        iris_code_b64=iris_code_b64,
        mask_code_b64=mask_code_b64,
    )
