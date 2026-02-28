"""Health check logic for iris-engine service."""

from __future__ import annotations

from .config import settings
from .matcher import gallery
from .models import HealthStatus
from .pipeline import is_pipeline_loaded

# NATS connection state — set by main.py on connect/disconnect
_nats_connected = False


def set_nats_connected(connected: bool) -> None:
    global _nats_connected
    _nats_connected = connected


def _is_db_connected() -> bool:
    if not settings.db_url:
        return False
    from .db import get_pool

    pool = get_pool()
    return pool is not None and pool.get_size() > 0


def _is_redis_connected() -> bool:
    if not settings.redis_url:
        return False
    from .redis_cache import is_connected

    return is_connected()


def _get_pool_stats() -> tuple[int, int]:
    """Return (pool_size, available) for the pipeline pool."""
    from .pipeline_pool import get_pipeline_pool

    pool = get_pipeline_pool()
    if pool is None:
        return 0, 0
    return pool.size, pool.available


def get_health() -> HealthStatus:
    pool_size, pool_available = _get_pool_stats()
    return HealthStatus(
        alive=True,
        ready=is_pipeline_loaded() and _nats_connected,
        pipeline_loaded=is_pipeline_loaded(),
        nats_connected=_nats_connected,
        gallery_size=gallery.size,
        db_connected=_is_db_connected(),
        redis_connected=_is_redis_connected(),
        pipeline_pool_size=pool_size,
        pipeline_pool_available=pool_available,
    )
