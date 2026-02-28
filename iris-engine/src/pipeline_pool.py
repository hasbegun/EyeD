"""Pool of pre-loaded IRISPipeline instances for parallel batch work.

Each instance owns its own ONNX session and intermediate state, so
concurrent calls from different threads are safe.  Workers call
``acquire()`` to borrow one and ``release()`` to return it.
"""

from __future__ import annotations

import logging
import os
import queue
import time
from typing import Optional

from .pipeline import create_pipeline

logger = logging.getLogger(__name__)


class PipelinePool:
    """Thread-safe pool of IRISPipeline instances.

    Instances are pre-loaded at ``load()`` time (blocking).  Workers call
    ``acquire()`` to borrow one and ``release()`` to return it.  Internally
    backed by a :class:`queue.Queue` which handles blocking and fairness.
    """

    def __init__(self, size: int) -> None:
        self._size = size
        self._pool: queue.Queue = queue.Queue(maxsize=size)
        self._loaded = False

    def load(self) -> None:
        """Pre-load all pipeline instances.  Call once at startup."""
        # Limit ONNX internal threads to prevent oversubscription.
        # With N pipeline instances each using K threads, total = N*K.
        cpu = os.cpu_count() or 4
        ort_threads = max(1, cpu // self._size)
        os.environ.setdefault("OMP_NUM_THREADS", str(ort_threads))

        logger.info(
            "Pre-loading %d pipeline instances (OMP_NUM_THREADS=%d)...",
            self._size,
            ort_threads,
        )
        start = time.monotonic()
        for i in range(self._size):
            pipe = create_pipeline()
            self._pool.put(pipe)
            logger.info("Pipeline instance %d/%d loaded", i + 1, self._size)

        elapsed = time.monotonic() - start
        logger.info(
            "Pipeline pool ready: %d instances in %.1fs", self._size, elapsed
        )
        self._loaded = True

    def acquire(self, timeout: Optional[float] = 30.0):
        """Borrow a pipeline instance (blocks if all in use)."""
        try:
            return self._pool.get(timeout=timeout)
        except queue.Empty:
            raise TimeoutError(
                f"No pipeline instance available after {timeout}s "
                f"(pool size={self._size})"
            )

    def release(self, pipeline) -> None:
        """Return a pipeline instance to the pool."""
        self._pool.put(pipeline)

    @property
    def is_loaded(self) -> bool:
        return self._loaded

    @property
    def size(self) -> int:
        return self._size

    @property
    def available(self) -> int:
        return self._pool.qsize()


# Module-level singleton, initialized during lifespan startup.
_pool: Optional[PipelinePool] = None


def get_pipeline_pool() -> Optional[PipelinePool]:
    """Return the global pipeline pool (None if not initialized)."""
    return _pool


def init_pipeline_pool(size: int) -> PipelinePool:
    """Create and pre-load the global pipeline pool."""
    global _pool
    _pool = PipelinePool(size)
    _pool.load()
    return _pool
