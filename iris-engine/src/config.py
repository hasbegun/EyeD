from typing import Literal

from pydantic import BaseSettings


class Settings(BaseSettings):
    # Runtime: controls ONNX execution provider for segmentation model
    eyed_runtime: Literal["cpu", "cuda", "coreml"] = "cpu"

    # NATS messaging
    nats_url: str = "nats://nats:4222"
    nats_subject_analyze: str = "eyed.analyze"
    nats_subject_enroll: str = "eyed.enroll"
    nats_subject_result: str = "eyed.result"
    nats_subject_archive: str = "eyed.archive"
    nats_subject_templates_changed: str = "eyed.templates.changed"

    # Matching thresholds (fractional Hamming distance)
    match_threshold: float = 0.39
    dedup_threshold: float = 0.32

    # Pipeline
    rotation_shift: int = 15

    # Database (empty = pure in-memory mode, no persistence)
    db_url: str = ""
    db_pool_min: int = 2
    db_pool_max: int = 5

    # Redis (empty = skip Redis, fall back to direct DB writes)
    redis_url: str = ""

    # Encryption: set EYED_ENCRYPTION_KEY env var (32 bytes, hex or base64)
    # to enable AES-256-GCM encryption of iris/mask templates at rest.
    # If unset, templates are stored unencrypted (backward compatible).
    # Key is read directly by crypto.py, NOT via this Settings class,
    # to avoid the key appearing in logs or serialized health responses.

    # Pipeline pool (pre-loaded instances for parallel batch work)
    pipeline_pool_size: int = 3

    # Batch enrollment
    batch_workers: int = 3        # thread pool size (should match pipeline_pool_size)
    batch_db_size: int = 50       # batch INSERT size for DB drain
    batch_db_interval: float = 1.0  # seconds between drain flushes

    # Dataset directories
    data_root: str = "/data/Iris"
    extra_data_dirs: str = ""  # comma-separated additional dataset directories

    # Server
    host: str = "0.0.0.0"
    port: int = 7000
    log_level: str = "info"

    class Config:
        env_prefix = "EYED_"
        env_file = ".env"


settings = Settings()
