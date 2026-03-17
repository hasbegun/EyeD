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
    model_dir: str = "/app/models"  # Directory with pre-downloaded ONNX models
    rotation_shift: int = 15

    # Database (empty = pure in-memory mode, no persistence)
    # Docker secrets — file paths mounted at /run/secrets/*
    db_user_file: str = ""
    db_name_file: str = ""
    db_password_file: str = ""
    db_url: str = ""
    db_pool_min: int = 2
    db_pool_max: int = 5

    @validator("db_url", always=True)
    def _inject_db_secrets(cls, v: str, values: dict) -> str:
        for placeholder, key in (
            ("__DB_USER__", "db_user_file"),
            ("__DB_NAME__", "db_name_file"),
            ("__DB_PASSWORD__", "db_password_file"),
        ):
            fpath = values.get(key)
            if fpath and placeholder in v:
                try:
                    v = v.replace(placeholder, Path(fpath).read_text().strip())
                except OSError:
                    pass
        return v

    # Redis (empty = skip Redis, fall back to direct DB writes)
    redis_url: str = ""

    # Homomorphic Encryption (OpenFHE BFV)
    # NOTE: he_enabled is NOT a config field — it is auto-detected from key files.
    # See he_enabled() function below. This prevents env-var tampering.
    he_key_dir: str = "/keys"       # Directory with public.key, eval_mult.key, eval_rotate.key
    he_key_service_subject: str = "eyed.key"  # NATS subject prefix for key-service

    # Plaintext fallback (DEVELOPMENT ONLY — must be explicitly justified)
    # Service refuses to start without HE keys unless this is set.
    # Even with this flag, raw biometric data is never exposed in HTTP responses.
    allow_plaintext: bool = False

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


# ---------------------------------------------------------------------------
# HE auto-detection (tamper-proof — no env var toggle)
# ---------------------------------------------------------------------------
# HE is activated at startup when key files are present in he_key_dir.
# An attacker cannot disable HE by setting an environment variable; they
# would need filesystem access inside the container to remove key files.

_he_active: bool = False

_HE_REQUIRED_FILES = (
    "cryptocontext.bin",
    "public.key",
    "eval_mult.key",
    "eval_rotate.key",
)


def detect_he_keys(key_dir: str) -> bool:
    """Check if all required HE key files exist in the given directory."""
    kd = Path(key_dir)
    return kd.is_dir() and all((kd / f).exists() for f in _HE_REQUIRED_FILES)


def activate_he() -> None:
    """Enable HE mode. Called once at startup after successful HE init."""
    global _he_active
    _he_active = True


def he_enabled() -> bool:
    """Return True if HE mode is active (keys loaded, context initialized)."""
    return _he_active
