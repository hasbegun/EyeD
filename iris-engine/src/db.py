"""PostgreSQL persistence for templates and match audit log."""

from __future__ import annotations

import asyncio
import io
import logging
import uuid as uuid_mod
from typing import Optional

import asyncpg
import numpy as np

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Binary packing utilities for iris code arrays
# ---------------------------------------------------------------------------


def pack_codes(codes: list) -> bytes:
    """Pack a list of numpy arrays into a compressed, optionally encrypted blob.

    If EYED_ENCRYPTION_KEY is set, the blob is AES-256-GCM encrypted.
    """
    buf = io.BytesIO()
    np.savez_compressed(buf, *codes)
    from .crypto import encrypt

    return encrypt(buf.getvalue())


def unpack_codes(data: bytes) -> list:
    """Unpack a (possibly encrypted) binary blob back to list of numpy arrays.

    Transparently decrypts AES-256-GCM blobs; passes through legacy NPZ data.
    """
    from .crypto import decrypt

    data = decrypt(data)
    buf = io.BytesIO(data)
    npz = np.load(buf)
    return [npz[k] for k in sorted(npz.files)]


# ---------------------------------------------------------------------------
# Connection pool
# ---------------------------------------------------------------------------

_pool: Optional[asyncpg.Pool] = None


async def init_pool(dsn: str, min_size: int = 2, max_size: int = 5) -> asyncpg.Pool:
    """Create the asyncpg connection pool."""
    global _pool
    _pool = await asyncpg.create_pool(dsn, min_size=min_size, max_size=max_size)
    logger.info("PostgreSQL pool created (%d-%d connections)", min_size, max_size)
    return _pool


async def close_pool() -> None:
    """Close the connection pool."""
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
        logger.info("PostgreSQL pool closed")


def get_pool() -> Optional[asyncpg.Pool]:
    """Return the current pool (or None if not initialized)."""
    return _pool


# ---------------------------------------------------------------------------
# Identity operations
# ---------------------------------------------------------------------------


async def ensure_identity(identity_id: str, name: str = "") -> None:
    """Insert identity if not exists, update name if it does."""
    pool = get_pool()
    if not pool:
        return
    uid = uuid_mod.UUID(identity_id)
    await pool.execute(
        """INSERT INTO identities (identity_id, name)
           VALUES ($1, $2)
           ON CONFLICT (identity_id) DO UPDATE SET name = EXCLUDED.name""",
        uid,
        name,
    )


async def delete_identity(identity_id: str) -> bool:
    """Delete an identity and all its templates (cascade). Returns True if found."""
    pool = get_pool()
    if not pool:
        return False
    uid = uuid_mod.UUID(identity_id)
    result = await pool.execute("DELETE FROM identities WHERE identity_id = $1", uid)
    return result == "DELETE 1"


# ---------------------------------------------------------------------------
# Template operations
# ---------------------------------------------------------------------------


async def persist_template(
    template_id: str,
    identity_id: str,
    eye_side: str,
    iris_codes_bytes: bytes,
    mask_codes_bytes: bytes,
    width: int,
    height: int,
    n_scales: int,
    quality_score: float = 0.0,
    device_id: str = "",
) -> None:
    """Insert a template row."""
    pool = get_pool()
    if not pool:
        return
    await pool.execute(
        """INSERT INTO templates
           (template_id, identity_id, eye_side, iris_codes, mask_codes,
            width, height, n_scales, quality_score, device_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)""",
        uuid_mod.UUID(template_id),
        uuid_mod.UUID(identity_id),
        eye_side,
        iris_codes_bytes,
        mask_codes_bytes,
        width,
        height,
        n_scales,
        quality_score,
        device_id,
    )


async def load_all_templates() -> list[dict]:
    """Load all templates from DB for gallery initialization."""
    pool = get_pool()
    if not pool:
        return []
    rows = await pool.fetch(
        """SELECT t.template_id, t.identity_id, i.name, t.eye_side,
                  t.iris_codes, t.mask_codes
           FROM templates t
           JOIN identities i ON t.identity_id = i.identity_id"""
    )
    return [dict(r) for r in rows]


async def load_template(template_id: str) -> Optional[dict]:
    """Load a single template by ID with all stored fields."""
    pool = get_pool()
    if not pool:
        return None
    row = await pool.fetchrow(
        """SELECT t.template_id, t.identity_id, i.name, t.eye_side,
                  t.iris_codes, t.mask_codes, t.width, t.height,
                  t.n_scales, t.quality_score, t.device_id
           FROM templates t
           JOIN identities i ON t.identity_id = i.identity_id
           WHERE t.template_id = $1""",
        uuid_mod.UUID(template_id),
    )
    return dict(row) if row else None


async def list_identities() -> list[dict]:
    """List all enrolled identities with their template info."""
    pool = get_pool()
    if not pool:
        return []
    rows = await pool.fetch(
        """SELECT i.identity_id, i.name, i.created_at,
                  t.template_id, t.eye_side
           FROM identities i
           LEFT JOIN templates t ON i.identity_id = t.identity_id
           ORDER BY i.created_at"""
    )
    # Group by identity
    identities: dict[str, dict] = {}
    for r in rows:
        iid = str(r["identity_id"])
        if iid not in identities:
            identities[iid] = {
                "identity_id": iid,
                "name": r["name"] or "",
                "templates": [],
            }
        if r["template_id"]:
            identities[iid]["templates"].append({
                "template_id": str(r["template_id"]),
                "eye_side": r["eye_side"],
            })
    return list(identities.values())


# ---------------------------------------------------------------------------
# Match log writer (async background batching)
# ---------------------------------------------------------------------------


class MatchLogWriter:
    """Async background writer that batches match log inserts."""

    def __init__(self) -> None:
        self._queue: asyncio.Queue = asyncio.Queue(maxsize=1000)
        self._task: Optional[asyncio.Task] = None

    def start(self) -> None:
        self._task = asyncio.create_task(self._drain_loop())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            await self._flush_remaining()

    def log(self, entry: dict) -> None:
        """Non-blocking enqueue. Drops if queue full."""
        try:
            self._queue.put_nowait(entry)
        except asyncio.QueueFull:
            pass

    async def _drain_loop(self) -> None:
        while True:
            entries = []
            entry = await self._queue.get()
            entries.append(entry)
            # Drain any more that are ready (batch insert)
            while not self._queue.empty() and len(entries) < 50:
                entries.append(self._queue.get_nowait())
            await self._batch_insert(entries)

    async def _batch_insert(self, entries: list[dict]) -> None:
        pool = get_pool()
        if not pool or not entries:
            return
        try:
            await pool.executemany(
                """INSERT INTO match_log
                   (probe_frame_id, matched_template_id, matched_identity_id,
                    hamming_distance, is_match, device_id, latency_ms)
                   VALUES ($1, $2, $3, $4, $5, $6, $7)""",
                [
                    (
                        e["probe_frame_id"],
                        uuid_mod.UUID(e["matched_template_id"]) if e.get("matched_template_id") else None,
                        uuid_mod.UUID(e["matched_identity_id"]) if e.get("matched_identity_id") else None,
                        e["hamming_distance"],
                        e["is_match"],
                        e.get("device_id"),
                        e.get("latency_ms"),
                    )
                    for e in entries
                ],
            )
        except Exception:
            logger.exception("Failed to batch-insert %d match log entries", len(entries))

    async def _flush_remaining(self) -> None:
        entries = []
        while not self._queue.empty():
            entries.append(self._queue.get_nowait())
        if entries:
            await self._batch_insert(entries)


# Module-level singleton
match_log_writer = MatchLogWriter()
