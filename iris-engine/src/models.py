from __future__ import annotations

from typing import List, Optional, Tuple

from pydantic import BaseModel


class AnalyzeRequest(BaseModel):
    """Frame submitted for analysis."""

    frame_id: str
    device_id: str = "local"
    jpeg_b64: str  # Base64-encoded JPEG data
    quality_score: float = 0.0
    eye_side: str = "left"  # "left" or "right"
    timestamp: str = ""


class SegmentationInfo(BaseModel):
    """Iris/pupil geometry extracted from segmentation."""

    pupil_center: Tuple[float, float]
    pupil_radius: float
    iris_center: Tuple[float, float]
    iris_radius: float
    confidence: float


class MatchResult(BaseModel):
    """Result of template matching against gallery."""

    hamming_distance: float
    is_match: bool
    matched_identity_id: Optional[str] = None
    matched_identity_name: Optional[str] = None
    best_rotation: int = 0


class AnalyzeResponse(BaseModel):
    """Full pipeline result."""

    frame_id: str
    device_id: str
    segmentation: Optional[SegmentationInfo] = None
    match: Optional[MatchResult] = None
    iris_template_b64: Optional[str] = None  # Serialized iris template
    latency_ms: float = 0.0
    error: Optional[str] = None


class EnrollRequest(BaseModel):
    """Request to enroll a new identity."""

    identity_id: str
    identity_name: str = ""
    jpeg_b64: str  # Base64-encoded JPEG data
    eye_side: str = "left"
    device_id: str = "local"


class EnrollResponse(BaseModel):
    """Enrollment result."""

    identity_id: str
    template_id: str
    is_duplicate: bool = False
    duplicate_identity_id: Optional[str] = None
    error: Optional[str] = None


class EyeGeometry(BaseModel):
    """Pupil/iris geometry extracted from pipeline."""

    pupil_center: Tuple[float, float]
    iris_center: Tuple[float, float]
    pupil_radius: float
    iris_radius: float
    eye_orientation: float  # radians


class QualityMetrics(BaseModel):
    """Image and iris quality measurements."""

    offgaze_score: float
    occlusion_90: float
    occlusion_30: float
    sharpness: float
    pupil_iris_ratio: float


class DetailedAnalyzeResponse(BaseModel):
    """Full pipeline result with intermediate visualizations."""

    frame_id: str
    device_id: str
    iris_template_b64: Optional[str] = None
    match: Optional[MatchResult] = None
    latency_ms: float = 0.0
    error: Optional[str] = None

    # Detailed data
    geometry: Optional[EyeGeometry] = None
    quality: Optional[QualityMetrics] = None

    # Visualization images (base64 PNG)
    original_image_b64: Optional[str] = None
    segmentation_overlay_b64: Optional[str] = None
    normalized_iris_b64: Optional[str] = None
    iris_code_b64: Optional[str] = None
    noise_mask_b64: Optional[str] = None


class DatasetInfo(BaseModel):
    """Available dataset summary."""

    name: str
    format: str
    count: int  # -1 = not yet counted (lazy)


class DatasetImage(BaseModel):
    """Single image in a dataset."""

    path: str
    subject_id: str
    eye_side: str
    filename: str


class BulkEnrollRequest(BaseModel):
    """Request to bulk-enroll subjects from a dataset directory."""

    dataset: str  # e.g. "CASIA-Iris-Thousand"
    subjects: Optional[List[str]] = None  # None = all subjects


class BulkEnrollResult(BaseModel):
    """Per-image result emitted during bulk enrollment (SSE data event)."""

    subject_id: str
    eye_side: str
    filename: str
    identity_id: str
    template_id: str = ""  # empty on error/dup
    is_duplicate: bool = False
    duplicate_identity_id: Optional[str] = None
    error: Optional[str] = None


class BulkEnrollSummary(BaseModel):
    """Final summary emitted at end of bulk enrollment (SSE done event)."""

    total: int
    enrolled: int
    duplicates: int
    errors: int


class TemplateDetailResponse(BaseModel):
    """Stored template with rendered iris code and mask visualizations."""

    template_id: str
    identity_id: str
    identity_name: str
    eye_side: str
    width: int
    height: int
    n_scales: int
    quality_score: float
    device_id: str
    iris_code_b64: Optional[str] = None
    mask_code_b64: Optional[str] = None


class SubjectInfo(BaseModel):
    """Subject directory with image count."""

    subject_id: str
    image_count: int


class DatasetPathInfo(BaseModel):
    """Status of a dataset root directory."""

    path: str
    exists: bool
    dataset_count: int


class AddPathRequest(BaseModel):
    """Request to add a dataset root directory."""

    path: str


class HealthStatus(BaseModel):
    """Service health information."""

    alive: bool = True
    ready: bool = False
    pipeline_loaded: bool = False
    nats_connected: bool = False
    gallery_size: int = 0
    db_connected: bool = False
    version: str = "0.2.0"
