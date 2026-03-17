import { LitElement, html, css } from 'lit';
import { customElement, property, state, query } from 'lit/decorators.js';
import { DeviceStream } from '../services/webrtc.js';

@customElement('video-feed')
export class VideoFeed extends LitElement {
  @property({ type: String, attribute: 'device-id' }) deviceId = '';
  @state() private connState: RTCPeerConnectionState | 'waiting' = 'waiting';

  @query('video') private videoEl!: HTMLVideoElement;

  private stream: DeviceStream | null = null;

  static styles = css`
    :host {
      display: block;
      background: #000;
      border-radius: var(--eyed-radius);
      overflow: hidden;
      position: relative;
    }
    video {
      width: 100%;
      display: block;
    }
    .overlay {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--eyed-text-muted);
      font-size: 0.875rem;
      background: rgba(0, 0, 0, 0.6);
    }
    .status-badge {
      position: absolute;
      top: var(--eyed-spacing-sm);
      right: var(--eyed-spacing-sm);
      padding: 2px 8px;
      border-radius: var(--eyed-radius);
      font-size: 0.6875rem;
      font-family: var(--eyed-font-mono);
    }
    .status-badge.connected { background: var(--eyed-success); color: #000; }
    .status-badge.connecting { background: var(--eyed-warning); color: #000; }
    .status-badge.disconnected { background: var(--eyed-danger); color: #fff; }
    .status-badge.waiting { background: var(--eyed-border); color: var(--eyed-text-muted); }
  `;

  connectedCallback() {
    super.connectedCallback();
    if (this.deviceId) {
      this.startStream();
    }
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.stream?.disconnect();
    this.stream = null;
  }

  updated(changed: Map<string, unknown>) {
    if (changed.has('deviceId') && this.deviceId) {
      this.stream?.disconnect();
      this.startStream();
    }
  }

  private startStream(): void {
    this.connState = 'waiting';
    this.stream = new DeviceStream(
      this.deviceId,
      (mediaStream) => {
        if (this.videoEl) {
          this.videoEl.srcObject = mediaStream;
        }
      },
      (state) => {
        this.connState = state;
      },
    );
    this.stream.connect();
  }

  private get statusClass(): string {
    switch (this.connState) {
      case 'connected': return 'status-badge connected';
      case 'connecting': case 'new': return 'status-badge connecting';
      case 'waiting': return 'status-badge waiting';
      default: return 'status-badge disconnected';
    }
  }

  private get statusLabel(): string {
    switch (this.connState) {
      case 'connected': return 'LIVE';
      case 'connecting': case 'new': return 'CONNECTING';
      case 'waiting': return 'WAITING';
      default: return 'OFFLINE';
    }
  }

  render() {
    const showOverlay = this.connState !== 'connected';
    return html`
      <video autoplay playsinline muted></video>
      ${showOverlay ? html`
        <div class="overlay">
          ${this.connState === 'waiting'
            ? `Waiting for device ${this.deviceId}...`
            : `Connection: ${this.connState}`}
        </div>
      ` : ''}
      <span class="${this.statusClass}">${this.statusLabel}</span>
    `;
  }
}
