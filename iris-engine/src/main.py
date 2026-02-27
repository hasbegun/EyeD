"""EyeD iris-engine: FastAPI entry point."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .matcher import gallery
from .pipeline import get_pipeline
from . import nats_service
from .routes import analyze, datasets, enroll, gallery as gallery_routes, health

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: load pipeline + init DB + connect NATS. Shutdown: cleanup."""
    logger.info("iris-engine node %s starting", nats_service.node_id)

    # Load the Open-IRIS pipeline (downloads model on first run)
    logger.info("Loading Open-IRIS pipeline...")
    get_pipeline()
    logger.info("Pipeline ready")

    # Initialize PostgreSQL (if configured)
    if settings.db_url:
        from .db import init_pool, match_log_writer

        await init_pool(settings.db_url, settings.db_pool_min, settings.db_pool_max)
        count = await gallery.load_from_db()
        logger.info("Gallery loaded: %d templates from database", count)
        match_log_writer.start()
        logger.info("Match log writer started")
    else:
        logger.info("No DB configured (EYED_DB_URL empty), running in-memory only")

    # Connect to NATS (non-blocking — HTTP still works without NATS)
    await nats_service.connect()
    await nats_service.subscribe_all()

    yield

    # Shutdown
    await nats_service.drain()

    if settings.db_url:
        from .db import close_pool, match_log_writer

        await match_log_writer.stop()
        await close_pool()

    logger.info("Shutdown complete")


app = FastAPI(
    title="EyeD Iris Engine",
    version="0.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(analyze.router)
app.include_router(enroll.router)
app.include_router(gallery_routes.router)
app.include_router(datasets.router)
