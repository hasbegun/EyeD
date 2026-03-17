import { LitElement, html, css, nothing } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import type { AnalyzeResult } from '../types/api.js';
import '../components/video-feed.js';
import '../components/status-indicator.js';

interface DeviceInfo {
  id: string;
  lastSeen: number;
  lastResult: AnalyzeResult | null;
  frameCount: number;
}

@customElement('view-devices')
export class ViewDevices extends LitElement {
  @state() private devices = new Map<string, DeviceInfo>();

  private boundHandler = this.onResult.bind(this);

  static styles = css`
    :host { display: block; }
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-md);
    }
    .empty {
      color: var(--eyed-text-muted);
      padding: var(--eyed-spacing-lg);
      border: 1px dashed var(--eyed-border);
      border-radius: var(--eyed-radius);
      text-align: center;
    }
    .device-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
      gap: var(--eyed-spacing-md);
    }
    .device-card {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      overflow: hidden;
    }
    .device-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: var(--eyed-spacing-sm) var(--eyed-spacing-md);
      border-bottom: 1px solid var(--eyed-border);
    }
    .device-header h2 {
      font-size: 0.875rem;
      font-weight: 600;
      margin: 0;
    }
    .device-meta {
      padding: var(--eyed-spacing-sm) var(--eyed-spacing-md);
      font-size: 0.75rem;
      color: var(--eyed-text-muted);
      font-family: var(--eyed-font-mono);
      display: flex;
      justify-content: space-between;
    }
    video-feed {
      aspect-ratio: 4 / 3;
    }
  `;

  connectedCallback() {
    super.connectedCallback();
    window.addEventListener('eyed-result', this.boundHandler as EventListener);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    window.removeEventListener('eyed-result', this.boundHandler as EventListener);
  }

  private onResult(e: Event) {
    const r = (e as CustomEvent<AnalyzeResult>).detail;
    const existing = this.devices.get(r.device_id);
    const updated = new Map(this.devices);
    updated.set(r.device_id, {
      id: r.device_id,
      lastSeen: Date.now(),
      lastResult: r,
      frameCount: (existing?.frameCount ?? 0) + 1,
    });
    this.devices = updated;
  }

  render() {
    const deviceList = Array.from(this.devices.values());
    return html`
      <h1>Devices</h1>
      ${deviceList.length === 0
        ? html`<div class="empty">No devices detected yet. Results will appear as frames are processed.</div>`
        : html`
          <div class="device-grid">
            ${deviceList.map(d => html`
              <div class="device-card">
                <div class="device-header">
                  <h2>${d.id}</h2>
                  <status-indicator connected label="Active"></status-indicator>
                </div>
                <video-feed device-id="${d.id}"></video-feed>
                <div class="device-meta">
                  <span>Frames: ${d.frameCount}</span>
                  <span>${d.lastResult?.match
                    ? `HD: ${d.lastResult.match.hamming_distance.toFixed(4)}`
                    : nothing}</span>
                  <span>${d.lastResult
                    ? `${d.lastResult.latency_ms.toFixed(0)}ms`
                    : ''}</span>
                </div>
              </div>
            `)}
          </div>
        `}
    `;
  }
}
