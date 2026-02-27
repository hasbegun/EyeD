"""Template matching using Open-IRIS HammingDistanceMatcher."""

from __future__ import annotations

import logging
import threading
import uuid
from dataclasses import dataclass, field
from typing import Optional

from .config import settings
from .models import MatchResult

logger = logging.getLogger(__name__)


@dataclass
class GalleryEntry:
    """An enrolled iris template in the gallery."""

    identity_id: str
    template_id: str
    identity_name: str
    eye_side: str
    template: object  # Open-IRIS IrisTemplate


class TemplateGallery:
    """In-memory gallery backed by PostgreSQL.

    Templates are kept in memory for fast 1:N matching.
    DB is used for persistence (load on startup, save on enroll).
    Falls back to pure in-memory mode if DB is not configured.
    """

    def __init__(self):
        self._entries: list[GalleryEntry] = []
        self._lock = threading.Lock()
        self._matcher = None

    async def load_from_db(self) -> int:
        """Reload all templates from PostgreSQL into memory.

        Replaces the current in-memory gallery atomically.  Returns the
        number of templates loaded.
        """
        from .db import load_all_templates, unpack_codes

        rows = await load_all_templates()

        from iris import IrisTemplate

        new_entries: list[GalleryEntry] = []
        for row in rows:
            try:
                iris_codes = unpack_codes(bytes(row["iris_codes"]))
                mask_codes = unpack_codes(bytes(row["mask_codes"]))
                template = IrisTemplate(
                    iris_codes=iris_codes,
                    mask_codes=mask_codes,
                    iris_code_version="v0.1",
                )
                new_entries.append(GalleryEntry(
                    identity_id=str(row["identity_id"]),
                    template_id=str(row["template_id"]),
                    identity_name=row["name"] or "",
                    eye_side=row["eye_side"],
                    template=template,
                ))
            except Exception:
                logger.exception("Failed to load template %s", row["template_id"])

        # Atomic swap — other threads see either the old or new list, never partial.
        with self._lock:
            self._entries = new_entries

        logger.info("Loaded %d templates from database", len(new_entries))
        return len(new_entries)

    def remove_identity(self, identity_id: str) -> int:
        """Remove all templates for an identity from the in-memory gallery.

        Returns the number of entries removed.
        """
        with self._lock:
            before = len(self._entries)
            self._entries = [e for e in self._entries if e.identity_id != identity_id]
            return before - len(self._entries)

    def _get_matcher(self):
        if self._matcher is None:
            from iris import HammingDistanceMatcher

            self._matcher = HammingDistanceMatcher(
                rotation_shift=settings.rotation_shift,
                normalise=True,
                norm_mean=0.45,
                norm_gradient=0.00005,
            )
        return self._matcher

    @property
    def size(self) -> int:
        with self._lock:
            return len(self._entries)

    def enroll(
        self,
        identity_id: str,
        identity_name: str,
        eye_side: str,
        template: object,
    ) -> str:
        """Add a template to the gallery. Returns template_id."""
        template_id = str(uuid.uuid4())
        entry = GalleryEntry(
            identity_id=identity_id,
            template_id=template_id,
            identity_name=identity_name,
            eye_side=eye_side,
            template=template,
        )
        with self._lock:
            self._entries.append(entry)
        logger.info(
            "Enrolled template %s for identity %s (%s eye)",
            template_id,
            identity_id,
            eye_side,
        )
        return template_id

    def check_duplicate(self, probe_template: object) -> Optional[str]:
        """Check if this iris is already enrolled (stricter threshold).

        Returns identity_id if duplicate found, None otherwise.
        """
        result = self._match(probe_template, settings.dedup_threshold)
        if result and result.is_match:
            return result.matched_identity_id
        return None

    def match(self, probe_template: object) -> Optional[MatchResult]:
        """Match a probe template against the gallery.

        Returns MatchResult if match found, None if gallery is empty.
        """
        return self._match(probe_template, settings.match_threshold)

    def _match(
        self, probe_template: object, threshold: float
    ) -> Optional[MatchResult]:
        """Run 1:N matching against all enrolled templates."""
        with self._lock:
            entries = list(self._entries)

        if not entries:
            return MatchResult(
                hamming_distance=1.0,
                is_match=False,
            )

        matcher = self._get_matcher()
        best_distance = 1.0
        best_entry: Optional[GalleryEntry] = None
        best_rotation = 0

        for entry in entries:
            try:
                distance = matcher.run(
                    template_probe=probe_template,
                    template_gallery=entry.template,
                )
                if distance < best_distance:
                    best_distance = distance
                    best_entry = entry
            except Exception:
                logger.exception(
                    "Matching failed against template %s", entry.template_id
                )
                continue

        is_match = best_distance < threshold
        return MatchResult(
            hamming_distance=best_distance,
            is_match=is_match,
            matched_identity_id=best_entry.identity_id if is_match and best_entry else None,
            best_rotation=best_rotation,
        )


# Module-level singleton
gallery = TemplateGallery()
