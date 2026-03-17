export interface AnalyzeResult {
  frame_id: string;
  device_id: string;
  match?: MatchInfo;
  iris_template_b64?: string;
  latency_ms: number;
  error?: string;
}

export interface MatchInfo {
  hamming_distance: number;
  is_match: boolean;
  matched_identity_id?: string;
  best_rotation: number;
}

export interface HealthReady {
  alive: boolean;
  ready: boolean;
  nats_connected: boolean;
  circuit_breaker: 'closed' | 'open' | 'half-open';
  version: string;
}

export interface HealthAlive {
  alive: boolean;
}

export interface EngineHealth {
  alive: boolean;
  ready: boolean;
  pipeline_loaded: boolean;
  nats_connected: boolean;
  gallery_size: number;
  db_connected: boolean;
  version: string;
}

export interface SignalMessage {
  type: 'offer' | 'answer' | 'ice-candidate' | 'join' | 'leave';
  device_id: string;
  from: 'device' | 'viewer';
  payload?: unknown;
}

export interface DatasetInfo {
  name: string;
  format: string;
  count: number;
}

export interface DatasetImage {
  path: string;
  subject_id: string;
  eye_side: string;
  filename: string;
}

export interface EyeGeometry {
  pupil_center: [number, number];
  iris_center: [number, number];
  pupil_radius: number;
  iris_radius: number;
  eye_orientation: number;
}

export interface QualityMetrics {
  offgaze_score: number;
  occlusion_90: number;
  occlusion_30: number;
  sharpness: number;
  pupil_iris_ratio: number;
}

export interface DetailedResult {
  frame_id: string;
  device_id: string;
  iris_template_b64?: string;
  match?: MatchInfo;
  latency_ms: number;
  error?: string;
  geometry?: EyeGeometry;
  quality?: QualityMetrics;
  original_image_b64?: string;
  segmentation_overlay_b64?: string;
  normalized_iris_b64?: string;
  iris_code_b64?: string;
  noise_mask_b64?: string;
}

export interface EnrollResponse {
  identity_id: string;
  template_id: string;
  is_duplicate: boolean;
  duplicate_identity_id?: string;
  error?: string;
}

export interface GalleryIdentity {
  identity_id: string;
  name: string;
  templates: { template_id: string; eye_side: string }[];
}
