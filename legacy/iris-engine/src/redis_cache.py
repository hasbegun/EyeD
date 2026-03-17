"""Redis write-through cache for bulk enrollment.

Templates are pushed to a Redis LIST as a fast write-through cache.
A separate background task (see db_drain.py) drains that list into
Postgres in batches.
"""

from __future__ import annotations

import json
import logging
from typing import Optional

import redis.asyncio as aioredis

logger = logging.getLogger(__name__)

_redis: Optional[aioredis.Redis] = None

# Redis key for the enrollment persistence queue
ENROLL_QUEUE_KEY = "eyed:enroll:pending"


async def init_redis(url: str) -> aioredis.Redis:
    """Create the async Redis connection and verify it works."""
    global _redis
    _redis = aioredis.from_url(url, decode_responses=False)
    await _redis.ping()
    logger.info("Redis connected at %s", url)
    return _redis


async def close_redis() -> None:
    """Close the Redis connection."""
    global _redis
    if _redis:
        await _redis.aclose()
        _redis = None
        logger.info("Redis connection closed")


def get_redis() -> Optional[aioredis.Redis]:
    """Return the global Redis connection (None if not initialized)."""
    return _redis


def is_connected() -> bool:
    """Return True if a Redis connection is active."""
    return _redis is not None


async def push_enrollment(data: dict) -> None:
    """Push an enrollment record to the Redis queue.

    ``data`` should contain:
        template_id, identity_id, identity_name, eye_side,
        iris_codes_b64, mask_codes_b64, width, height, n_scales,
        quality_score, device_id
    """
    r = get_redis()
    if not r:
        return
    payload = json.dumps(data).encode()
    await r.rpush(ENROLL_QUEUE_KEY, payload)


async def pop_enrollments(batch_size: int = 50) -> list[dict]:
    """Atomically pop up to *batch_size* enrollment records.

    Uses LRANGE + LTRIM in a pipeline for atomicity.
    """
    r = get_redis()
    if not r:
        return []

    pipe = r.pipeline()
    pipe.lrange(ENROLL_QUEUE_KEY, 0, batch_size - 1)
    pipe.ltrim(ENROLL_QUEUE_KEY, batch_size, -1)
    results = await pipe.execute()

    raw_items = results[0]  # list[bytes]
    items: list[dict] = []
    for raw in raw_items:
        try:
            items.append(json.loads(raw))
        except (json.JSONDecodeError, TypeError):
            logger.warning("Skipping malformed Redis enrollment record")
    return items


async def queue_length() -> int:
    """Return the number of pending enrollment records."""
    r = get_redis()
    if not r:
        return 0
    return await r.llen(ENROLL_QUEUE_KEY)
