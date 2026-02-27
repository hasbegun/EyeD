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
