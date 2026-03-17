import type {
  HealthAlive,
  HealthReady,
  EngineHealth,
  DatasetInfo,
  DatasetImage,
  DetailedResult,
  EnrollResponse,
  GalleryIdentity,
} from '../types/api.js';

async function fetchJSON<T>(path: string): Promise<T> {
  const resp = await fetch(path);
  if (!resp.ok) throw new Error(`${path}: ${resp.status}`);
  return resp.json() as Promise<T>;
}

export async function checkAlive(): Promise<HealthAlive> {
  return fetchJSON<HealthAlive>('/health/alive');
}

export async function checkReady(): Promise<HealthReady> {
  return fetchJSON<HealthReady>('/health/ready');
}

export async function checkEngineReady(): Promise<EngineHealth> {
  return fetchJSON<EngineHealth>('/engine/health/ready');
}

export async function getGallerySize(): Promise<{ gallery_size: number }> {
  return fetchJSON<{ gallery_size: number }>('/engine/gallery/size');
}

export async function listDatasets(): Promise<DatasetInfo[]> {
  return fetchJSON<DatasetInfo[]>('/engine/datasets');
}

export async function listDatasetImages(
  name: string,
  subject?: string,
): Promise<DatasetImage[]> {
  const params = subject ? `?subject=${encodeURIComponent(subject)}` : '';
  return fetchJSON<DatasetImage[]>(`/engine/datasets/${encodeURIComponent(name)}/images${params}`);
}

export function getDatasetImageUrl(name: string, path: string): string {
  return `/engine/datasets/${encodeURIComponent(name)}/image/${path}`;
}

export async function analyzeDetailed(
  name: string,
  imagePath: string,
  eyeSide: string,
): Promise<DetailedResult> {
  // Fetch the image first, then send it as multipart form
  const imageUrl = getDatasetImageUrl(name, imagePath);
  const imageResp = await fetch(imageUrl);
  if (!imageResp.ok) throw new Error(`Failed to fetch image: ${imageResp.status}`);
  const imageBlob = await imageResp.blob();

  const form = new FormData();
  form.append('file', imageBlob, imagePath.split('/').pop() || 'image');
  form.append('eye_side', eyeSide);
  form.append('frame_id', `run-${imagePath}`);
  form.append('device_id', 'web-ui');

  const resp = await fetch('/engine/analyze/detailed', { method: 'POST', body: form });
  if (!resp.ok) throw new Error(`Analysis failed: ${resp.status}`);
  return resp.json() as Promise<DetailedResult>;
}

// --- Enrollment API ---

export async function enroll(
  jpegB64: string,
  eyeSide: string,
  identityId: string,
  identityName: string,
  deviceId = 'web-ui',
): Promise<EnrollResponse> {
  const resp = await fetch('/engine/enroll', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      identity_id: identityId,
      identity_name: identityName,
      jpeg_b64: jpegB64,
      eye_side: eyeSide,
      device_id: deviceId,
    }),
  });
  if (!resp.ok) throw new Error(`Enrollment failed: ${resp.status}`);
  return resp.json() as Promise<EnrollResponse>;
}

export async function listGallery(): Promise<GalleryIdentity[]> {
  return fetchJSON<GalleryIdentity[]>('/engine/gallery/list');
}

export async function deleteIdentity(identityId: string): Promise<void> {
  const resp = await fetch(`/engine/gallery/delete/${encodeURIComponent(identityId)}`, {
    method: 'DELETE',
  });
  if (!resp.ok) throw new Error(`Delete failed: ${resp.status}`);
}
