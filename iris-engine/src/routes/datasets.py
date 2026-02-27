"""Dataset browsing endpoints and utilities."""

from __future__ import annotations

import mimetypes
import re
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response

from ..config import settings
from ..models import (
    AddPathRequest,
    DatasetImage,
    DatasetInfo,
    DatasetPathInfo,
    SubjectInfo,
)

router = APIRouter(tags=["datasets"])

DATA_ROOT = Path(settings.data_root)

# Extra dataset directories added at runtime via API
_extra_data_dirs: List[Path] = []

# Initialize extra dirs from config
for _d in settings.extra_data_dirs.split(","):
    _d = _d.strip()
    if _d:
        _extra_data_dirs.append(Path(_d))


# --- Utilities ---

# Eye-side mapping per dataset naming convention
_CASIA_EYE_MAP = {"1": "left", "2": "right"}
_MMU2_EYE_MAP = {"01": "left", "02": "right"}
_LR_DIR_MAP = {"l": "left", "r": "right", "left": "left", "right": "right"}

# CASIA-Iris-Thousand: filenames like S5000L00.jpg — L or R embedded
_THOUSAND_RE = re.compile(r"S\d+([LR])\d+", re.IGNORECASE)


def _all_data_roots() -> List[Path]:
    """Return all dataset root directories (primary + extras)."""
    roots = [DATA_ROOT]
    roots.extend(_extra_data_dirs)
    return roots


def _parse_eye_side(dataset: str, filename: str, parent_dir: str = "") -> str:
    """Infer eye side from filename/directory based on dataset naming convention."""
    if parent_dir:
        side = _LR_DIR_MAP.get(parent_dir.lower())
        if side:
            return side

    stem = Path(filename).stem
    if dataset.upper().startswith("CASIA"):
        m = _THOUSAND_RE.match(stem)
        if m:
            return "left" if m.group(1).upper() == "L" else "right"
        parts = stem.split("_")
        if len(parts) >= 2:
            return _CASIA_EYE_MAP.get(parts[1], "left")
    elif dataset.upper().startswith("MMU"):
        if len(stem) >= 4:
            return _MMU2_EYE_MAP.get(stem[-4:-2], "left")
    return "left"


def _validate_dataset_name(name: str) -> Path:
    """Validate dataset name and return its path. Raises HTTPException on error."""
    if "/" in name or "\\" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Invalid dataset name")
    for root in _all_data_roots():
        ds_path = root / name
        if ds_path.is_dir():
            return ds_path
    raise HTTPException(status_code=404, detail=f"Dataset '{name}' not found")


def _has_images(directory: Path) -> bool:
    """Check if a directory (or its subdirectories) contains image files."""
    exts = (".jpg", ".jpeg", ".bmp", ".png")
    for f in directory.rglob("*"):
        if f.is_file() and f.suffix.lower() in exts:
            return True
    return False


def _detect_format(d: Path) -> str:
    """Quick format detection: check first few files instead of rglob."""
    for f in d.rglob("*"):
        if f.is_file():
            if f.suffix.lower() == ".bmp":
                return "bmp"
            if f.suffix.lower() in (".jpg", ".jpeg", ".png"):
                return "jpg"
    return "jpg"


# --- Endpoints ---


@router.get("/datasets", response_model=List[DatasetInfo])
async def list_datasets():
    """List available iris datasets across all configured data roots."""
    seen: set[str] = set()
    datasets = []
    for root in _all_data_roots():
        if not root.is_dir():
            continue
        for d in sorted(root.iterdir()):
            if not d.is_dir() or d.name.startswith(".") or d.name in seen:
                continue
            if not _has_images(d):
                continue
            seen.add(d.name)
            fmt = _detect_format(d)
            datasets.append(DatasetInfo(name=d.name, format=fmt, count=-1))
    return datasets


# Fixed-path routes BEFORE parameterized routes to avoid conflicts
@router.get("/datasets/paths", response_model=List[DatasetPathInfo])
async def list_dataset_paths():
    """List all configured dataset root directories."""
    result = []
    for root in _all_data_roots():
        exists = root.is_dir()
        count = 0
        if exists:
            count = sum(
                1 for d in root.iterdir()
                if d.is_dir() and not d.name.startswith(".") and _has_images(d)
            )
        result.append(DatasetPathInfo(
            path=str(root), exists=exists, dataset_count=count,
        ))
    return result


@router.post("/datasets/paths", response_model=DatasetPathInfo)
async def add_dataset_path(req: AddPathRequest):
    """Add an extra dataset directory at runtime."""
    p = Path(req.path)
    if not p.is_absolute():
        raise HTTPException(status_code=400, detail="Path must be absolute")
    for root in _all_data_roots():
        if root.resolve() == p.resolve():
            raise HTTPException(status_code=409, detail="Path already registered")
    _extra_data_dirs.append(p)
    exists = p.is_dir()
    count = 0
    if exists:
        count = sum(
            1 for d in p.iterdir()
            if d.is_dir() and not d.name.startswith(".") and _has_images(d)
        )
    return DatasetPathInfo(path=str(p), exists=exists, dataset_count=count)


@router.delete("/datasets/paths")
async def remove_dataset_path(path: str = Query(..., description="Path to remove")):
    """Remove a runtime-added dataset directory."""
    p = Path(path)
    for i, existing in enumerate(_extra_data_dirs):
        if existing.resolve() == p.resolve():
            _extra_data_dirs.pop(i)
            return {"removed": str(p)}
    raise HTTPException(
        status_code=404,
        detail="Path not found in extra directories (cannot remove primary root)",
    )


# Parameterized routes after fixed-path routes


@router.get("/datasets/{name}/info", response_model=DatasetInfo)
async def get_dataset_info(name: str):
    """Get full dataset info including image count."""
    ds_path = _validate_dataset_name(name)
    exts = ("*.jpg", "*.jpeg", "*.bmp", "*.png")
    count = sum(len(list(ds_path.rglob(ext))) for ext in exts)
    fmt = "bmp" if list(ds_path.rglob("*.bmp")) else "jpg"
    return DatasetInfo(name=name, format=fmt, count=count)


@router.get("/datasets/{name}/subjects", response_model=List[SubjectInfo])
async def list_dataset_subjects(name: str):
    """List subjects in a dataset with per-subject image counts."""
    ds_path = _validate_dataset_name(name)
    exts = (".jpg", ".jpeg", ".bmp", ".png")
    subjects = []

    for subject_dir in sorted(ds_path.iterdir()):
        if not subject_dir.is_dir() or subject_dir.name.startswith("."):
            continue
        count = 0
        for child in subject_dir.iterdir():
            if child.is_file() and child.suffix.lower() in exts:
                count += 1
            elif child.is_dir() and not child.name.startswith("."):
                count += sum(
                    1 for f in child.iterdir()
                    if f.is_file() and f.suffix.lower() in exts
                )
        if count > 0:
            subjects.append(SubjectInfo(subject_id=subject_dir.name, image_count=count))
    return subjects


@router.get("/datasets/{name}/images", response_model=List[DatasetImage])
async def list_dataset_images(
    name: str,
    subject: Optional[str] = Query(None, description="Filter by subject ID"),
    offset: int = Query(0, ge=0, description="Skip first N images"),
    limit: int = Query(100, ge=1, le=500, description="Max images to return"),
):
    """List images in a dataset with pagination."""
    ds_path = _validate_dataset_name(name)
    images = []
    exts = (".jpg", ".jpeg", ".bmp", ".png")
    skipped = 0

    for subject_dir in sorted(ds_path.iterdir()):
        if not subject_dir.is_dir() or subject_dir.name.startswith("."):
            continue
        if subject and subject_dir.name != subject:
            continue

        image_entries: list[tuple[Path, str]] = []
        for child in sorted(subject_dir.iterdir()):
            if child.is_file() and child.suffix.lower() in exts:
                image_entries.append((child, ""))
            elif child.is_dir() and not child.name.startswith("."):
                for img_path in sorted(child.iterdir()):
                    if img_path.is_file() and img_path.suffix.lower() in exts:
                        image_entries.append((img_path, child.name))

        for img_path, parent_dir in image_entries:
            if skipped < offset:
                skipped += 1
                continue
            if len(images) >= limit:
                return images

            rel = img_path.relative_to(ds_path)
            eye_side = _parse_eye_side(name, img_path.name, parent_dir)
            images.append(DatasetImage(
                path=str(rel),
                subject_id=subject_dir.name,
                eye_side=eye_side,
                filename=img_path.name,
            ))
    return images


@router.get("/datasets/{name}/image/{path:path}")
async def get_dataset_image(name: str, path: str):
    """Serve a single dataset image."""
    ds_path = _validate_dataset_name(name)

    img_path = (ds_path / path).resolve()
    if not str(img_path).startswith(str(ds_path.resolve())):
        raise HTTPException(status_code=400, detail="Invalid path")
    if not img_path.is_file():
        raise HTTPException(status_code=404, detail="Image not found")

    content_type = mimetypes.guess_type(str(img_path))[0] or "application/octet-stream"
    return Response(content=img_path.read_bytes(), media_type=content_type)
