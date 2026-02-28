from pathlib import Path
from typing import Literal

from pydantic import BaseSettings, validator


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
    db_password_file: str = ""  # Docker secret, e.g. /run/secrets/db_password
    db_url: str = ""
    db_pool_min: int = 2
    db_pool_max: int = 5

    @validator("db_url", always=True)
    def _inject_db_password(cls, v: str, values: dict) -> str:
        pw_file = values.get("db_password_file")
        if pw_file and "__DB_PASSWORD__" in v:
            try:
                pw = Path(pw_file).read_text().strip()
                v = v.replace("__DB_PASSWORD__", pw)
            except OSError:
                pass
        return v

    # Redis (empty = skip Redis, fall back to direct DB writes)
    redis_url: str = ""

    # Homomorphic Encryption (OpenFHE BFV)
    he_enabled: bool = False        # Enable HE mode (requires key-service running)
    he_key_dir: str = "/keys"       # Directory with public.key, eval_mult.key, eval_rotate.key
    he_key_service_subject: str = "eyed.key"  # NATS subject prefix for key-service

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
