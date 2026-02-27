"""Health check endpoints."""

from fastapi import APIRouter

from ..health import get_health
from ..models import HealthStatus

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/alive", response_model=HealthStatus)
async def health_alive():
    """Liveness check — is the process running?"""
    return HealthStatus(alive=True)


@router.get("/ready", response_model=HealthStatus)
async def health_ready():
    """Readiness check — is the pipeline loaded and NATS connected?"""
    return get_health()
