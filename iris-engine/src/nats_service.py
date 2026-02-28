"""NATS connection management and message handlers."""

from __future__ import annotations

import asyncio
import json
import logging
import time
import uuid
from typing import Optional

import nats
from nats.aio.client import Client as NATSClient

from .config import settings
from .health import set_nats_connected
from .matcher import gallery
from .models import AnalyzeRequest, EnrollRequest

logger = logging.getLogger(__name__)

# Module-level state
nc: Optional[NATSClient] = None
node_id: str = uuid.uuid4().hex[:12]

_slow_consumer_count = 0
_slow_consumer_last_log = 0.0
_analyzing = False
_reload_debounce_task: Optional[asyncio.Task] = None
_RELOAD_DEBOUNCE_SECS = 0.5


# --- NATS callbacks ---


async def _on_nats_error(e: Exception) -> None:
    global _slow_consumer_count, _slow_consumer_last_log
    msg = str(e)
    if "slow consumer" in msg:
        _slow_consumer_count += 1
        now = time.monotonic()
        if now - _slow_consumer_last_log >= 10:
            logger.warning(
                "NATS slow consumer: %d messages dropped (expected — pipeline is busy)",
                _slow_consumer_count,
            )
            _slow_consumer_count = 0
            _slow_consumer_last_log = now
        return
    logger.error("NATS error: %s", e)


async def _on_nats_disconnected() -> None:
    set_nats_connected(False)
    logger.warning("NATS disconnected")


async def _on_nats_reconnected() -> None:
    set_nats_connected(True)
    logger.info("NATS reconnected")


async def _on_nats_closed() -> None:
    set_nats_connected(False)
    logger.info("NATS connection closed")


# --- Connection ---


async def connect() -> Optional[NATSClient]:
    """Connect to NATS server with automatic reconnection."""
    global nc
    try:
        nc = await nats.connect(
            settings.nats_url,
            max_reconnect_attempts=-1,
            reconnect_time_wait=2,
            error_cb=_on_nats_error,
            disconnected_cb=_on_nats_disconnected,
            reconnected_cb=_on_nats_reconnected,
            closed_cb=_on_nats_closed,
        )
        set_nats_connected(True)
        logger.info("Connected to NATS at %s", settings.nats_url)
        return nc
    except Exception:
        logger.warning("NATS not available at %s, running HTTP-only", settings.nats_url)
        set_nats_connected(False)
        return None


async def subscribe_all() -> None:
    """Subscribe to all NATS subjects. Call after connect()."""
    if not nc:
        return

    await nc.subscribe(
        settings.nats_subject_analyze,
        cb=_nats_analyze_handler,
        pending_msgs_limit=1,
    )
    await nc.subscribe(settings.nats_subject_enroll, cb=_nats_enroll_handler)

    if settings.db_url:
        await nc.subscribe(
            settings.nats_subject_templates_changed,
            cb=_nats_templates_changed_handler,
        )

    logger.info(
        "Subscribed to NATS subjects: %s, %s, %s",
        settings.nats_subject_analyze,
        settings.nats_subject_enroll,
        settings.nats_subject_templates_changed,
    )


async def drain() -> None:
    """Drain and close the NATS connection."""
    if nc and nc.is_connected:
        await nc.drain()
        set_nats_connected(False)


# --- Message handlers ---


async def _nats_analyze_handler(msg) -> None:
    """Handle analysis request from NATS. Drops frames while pipeline is busy."""
    global _analyzing
    if _analyzing:
        return
    _analyzing = True
    try:
        from .core import build_archive_message, log_match, run_analyze

        data = json.loads(msg.data.decode())
        req = AnalyzeRequest(**data)
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None, run_analyze, req.jpeg_b64, req.eye_side, req.frame_id, req.device_id
        )

        log_match(response)

        if nc and nc.is_connected:
            await nc.publish(
                settings.nats_subject_result,
                response.json().encode(),
            )
            archive_msg = build_archive_message(req, response)
            await nc.publish(
                settings.nats_subject_archive,
                json.dumps(archive_msg).encode(),
            )
    except Exception:
        logger.exception("Error handling NATS analyze message")
    finally:
        _analyzing = False


async def _nats_enroll_handler(msg) -> None:
    """Handle enrollment request from NATS."""
    try:
        from .core import run_enroll_async

        data = json.loads(msg.data.decode())
        req = EnrollRequest(**data)
        response = await run_enroll_async(req)
        if nc and nc.is_connected:
            await nc.publish(
                settings.nats_subject_result,
                response.json().encode(),
            )
    except Exception:
        logger.exception("Error handling NATS enroll message")


async def _nats_templates_changed_handler(msg) -> None:
    """Reload template cache when another node changes its gallery."""
    global _reload_debounce_task
    try:
        data = json.loads(msg.data.decode())
        source = data.get("node_id")
        if source == node_id:
            return
        event = data.get("event", "unknown")
        logger.info("Template change from node %s: %s", source or "?", event)
        if _reload_debounce_task and not _reload_debounce_task.done():
            _reload_debounce_task.cancel()
        _reload_debounce_task = asyncio.create_task(_debounced_reload())
    except Exception:
        logger.exception("Error handling templates.changed message")


async def _debounced_reload() -> None:
    """Wait briefly then reload the gallery from DB."""
    await asyncio.sleep(_RELOAD_DEBOUNCE_SECS)
    count = await gallery.load_from_db()
    logger.info("Gallery reloaded from DB: %d templates", count)
