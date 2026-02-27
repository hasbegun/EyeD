"""Background Redis -> Postgres drain for bulk enrollment persistence.

Modeled after MatchLogWriter in db.py.  Periodically pops enrollment
records from the Redis queue and batch-inserts them into Postgres.
"""

from __future__ import annotations

import asyncio
import base64
import logging
import uuid as uuid_mod
from typing import Optional

from .config import settings

logger = logging.getLogger(__name__)


class EnrollmentDrainWriter:
    """Async background task that drains Redis enrollment queue -> Postgres."""

    def __init__(self) -> None:
        self._task: Optional[asyncio.Task] = None
        self._stop_event = asyncio.Event()

    def start(self) -> None:
        """Start the background drain loop."""
        self._stop_event.clear()
        self._task = asyncio.create_task(self._drain_loop())
        logger.info("Enrollment drain writer started")

    async def stop(self) -> None:
        """Stop the drain loop and flush remaining items."""
        if self._task:
            self._stop_event.set()
            try:
                await asyncio.wait_for(self._task, timeout=10.0)
            except (asyncio.CancelledError, asyncio.TimeoutError):
                self._task.cancel()
            # Final flush to catch any items pushed after the last poll
            await self._flush()
            logger.info("Enrollment drain writer stopped")

    async def _drain_loop(self) -> None:
        """Periodically pop from Redis and batch-insert to Postgres."""
        while not self._stop_event.is_set():
            try:
                await self._flush()
            except Exception:
                logger.exception("Enrollment drain error")
            # Wait for configured interval or until stop is requested
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=settings.batch_db_interval,
                )
                break  # stop_event was set
            except asyncio.TimeoutError:
                pass  # Normal: interval elapsed, loop again

    async def _flush(self) -> None:
        """Pop a batch from Redis and insert into Postgres."""
        from .redis_cache import pop_enrollments

        items = await pop_enrollments(settings.batch_db_size)
        if not items:
            return

        await self._batch_insert(items)

    async def _batch_insert(self, items: list[dict]) -> None:
        """Batch-insert enrollment records into Postgres."""
        from .db import get_pool

        pool = get_pool()
        if not pool or not items:
            return

        try:
            # Step 1: Batch upsert identities (deduplicate by identity_id)
            identity_rows = list({
                (item["identity_id"], item["identity_name"])
                for item in items
            })
            await pool.executemany(
                """INSERT INTO identities (identity_id, name)
                   VALUES ($1, $2)
                   ON CONFLICT (identity_id) DO UPDATE SET name = EXCLUDED.name""",
                [
                    (uuid_mod.UUID(iid), name)
                    for iid, name in identity_rows
                ],
            )

            # Step 2: Batch insert templates
            await pool.executemany(
                """INSERT INTO templates
                   (template_id, identity_id, eye_side, iris_codes, mask_codes,
                    width, height, n_scales, quality_score, device_id)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)""",
                [
                    (
                        uuid_mod.UUID(item["template_id"]),
                        uuid_mod.UUID(item["identity_id"]),
                        item["eye_side"],
                        base64.b64decode(item["iris_codes_b64"]),
                        base64.b64decode(item["mask_codes_b64"]),
                        item["width"],
                        item["height"],
                        item["n_scales"],
                        item.get("quality_score", 0.0),
                        item.get("device_id", "bulk-enroll"),
                    )
                    for item in items
                ],
            )
            logger.info("Batch-inserted %d enrollment records to DB", len(items))
        except Exception:
            logger.exception(
                "Failed to batch-insert %d enrollment records", len(items)
            )


# Module-level singleton
enrollment_drain_writer = EnrollmentDrainWriter()
