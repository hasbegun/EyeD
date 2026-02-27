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


def get_health() -> HealthStatus:
    return HealthStatus(
        alive=True,
        ready=is_pipeline_loaded() and _nats_connected,
        pipeline_loaded=is_pipeline_loaded(),
        nats_connected=_nats_connected,
        gallery_size=gallery.size,
        db_connected=_is_db_connected(),
    )
