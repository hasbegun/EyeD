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
from .routes import analyze, datasets, db_inspector, enroll, gallery as gallery_routes, health

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: load pipeline + init DB + connect NATS. Shutdown: cleanup."""
    logger.info("iris-engine node %s starting", nats_service.node_id)

    # Load the singleton Open-IRIS pipeline (for single-request endpoints)
    logger.info("Loading Open-IRIS pipeline...")
    get_pipeline()
    logger.info("Pipeline ready")

    # Pre-load pipeline pool (for batch enrollment — true parallelism)
    if settings.pipeline_pool_size > 0:
        from .pipeline_pool import init_pipeline_pool

        init_pipeline_pool(settings.pipeline_pool_size)

    # Initialize OpenFHE BFV context (if HE mode enabled)
    if settings.he_enabled:
        from .he_context import init_context

        logger.info("Initializing HE context (key_dir=%s)...", settings.he_key_dir)
        init_context(key_dir=settings.he_key_dir)
        logger.info("HE context ready")

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

    # Initialize Redis (if configured)
    if settings.redis_url:
        from .redis_cache import init_redis

        await init_redis(settings.redis_url)

        # Start Redis -> DB drain writer (only if both Redis and DB exist)
        if settings.db_url:
            from .db_drain import enrollment_drain_writer

            enrollment_drain_writer.start()

    # Connect to NATS (non-blocking — HTTP still works without NATS)
    await nats_service.connect()
    await nats_service.subscribe_all()

    yield

    # Shutdown (reverse order)
    await nats_service.drain()

    if settings.redis_url and settings.db_url:
        from .db_drain import enrollment_drain_writer

        await enrollment_drain_writer.stop()

    if settings.redis_url:
        from .redis_cache import close_redis

        await close_redis()

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
app.include_router(db_inspector.router)
