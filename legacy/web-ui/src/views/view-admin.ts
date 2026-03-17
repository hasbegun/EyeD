import { LitElement, html, css } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import { checkReady, checkEngineReady } from '../services/gateway-client.js';
import type { HealthReady, EngineHealth } from '../types/api.js';
import '../components/status-indicator.js';

@customElement('view-admin')
export class ViewAdmin extends LitElement {
  @state() private gateway: HealthReady | null = null;
  @state() private engine: EngineHealth | null = null;
  @state() private gatewayError = '';
  @state() private engineError = '';
  @state() private lastPoll = '';

  private pollTimer: ReturnType<typeof setInterval> | null = null;

  static styles = css`
    :host { display: block; }
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-md);
    }
    h2 {
      font-size: 1.125rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-sm);
    }
    .services {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
      gap: var(--eyed-spacing-md);
      margin-bottom: var(--eyed-spacing-lg);
    }
    .service-card {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-md);
    }
    .service-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: var(--eyed-spacing-sm);
    }
    .service-header h2 { margin: 0; }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.8125rem;
    }
    td {
      padding: 4px 0;
      font-family: var(--eyed-font-mono);
    }
    td:first-child {
      color: var(--eyed-text-muted);
      padding-right: var(--eyed-spacing-md);
      white-space: nowrap;
    }
    .ok { color: var(--eyed-success); }
    .err { color: var(--eyed-danger); }
    .warn { color: var(--eyed-warning); }
    .error-msg {
      color: var(--eyed-danger);
      font-size: 0.8125rem;
      padding: var(--eyed-spacing-sm) 0;
    }
    .poll-info {
      font-size: 0.75rem;
      color: var(--eyed-text-muted);
      margin-bottom: var(--eyed-spacing-md);
    }
  `;

  connectedCallback() {
    super.connectedCallback();
    this.poll();
    this.pollTimer = setInterval(() => this.poll(), 5000);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  private async poll() {
    this.lastPoll = new Date().toLocaleTimeString();

    try {
      this.gateway = await checkReady();
      this.gatewayError = '';
    } catch (e) {
      this.gatewayError = e instanceof Error ? e.message : 'Unreachable';
      this.gateway = null;
    }

    try {
      this.engine = await checkEngineReady();
      this.engineError = '';
    } catch (e) {
      this.engineError = e instanceof Error ? e.message : 'Unreachable';
      this.engine = null;
    }
  }

  private statusClass(ok: boolean | undefined): string {
    return ok ? 'ok' : 'err';
  }

  private cbClass(state: string): string {
    if (state === 'closed') return 'ok';
    if (state === 'half-open') return 'warn';
    return 'err';
  }

  render() {
    return html`
      <h1>Admin</h1>
      <div class="poll-info">Last updated: ${this.lastPoll} (polling every 5s)</div>

      <div class="services">
        <div class="service-card">
          <div class="service-header">
            <h2>Gateway</h2>
            <status-indicator
              ?connected=${!!this.gateway?.ready}
              label=${this.gateway?.ready ? 'Ready' : 'Down'}
            ></status-indicator>
          </div>
          ${this.gatewayError
            ? html`<div class="error-msg">${this.gatewayError}</div>`
            : this.gateway ? html`
              <table>
                <tr><td>Alive</td><td class="${this.statusClass(this.gateway.alive)}">${this.gateway.alive}</td></tr>
                <tr><td>Ready</td><td class="${this.statusClass(this.gateway.ready)}">${this.gateway.ready}</td></tr>
                <tr><td>NATS</td><td class="${this.statusClass(this.gateway.nats_connected)}">${this.gateway.nats_connected}</td></tr>
                <tr><td>Circuit Breaker</td><td class="${this.cbClass(this.gateway.circuit_breaker)}">${this.gateway.circuit_breaker}</td></tr>
                <tr><td>Version</td><td>${this.gateway.version}</td></tr>
              </table>
            ` : ''}
        </div>

        <div class="service-card">
          <div class="service-header">
            <h2>Iris Engine</h2>
            <status-indicator
              ?connected=${!!this.engine?.ready}
              label=${this.engine?.ready ? 'Ready' : 'Down'}
            ></status-indicator>
          </div>
          ${this.engineError
            ? html`<div class="error-msg">${this.engineError}</div>`
            : this.engine ? html`
              <table>
                <tr><td>Alive</td><td class="${this.statusClass(this.engine.alive)}">${this.engine.alive}</td></tr>
                <tr><td>Ready</td><td class="${this.statusClass(this.engine.ready)}">${this.engine.ready}</td></tr>
                <tr><td>Pipeline</td><td class="${this.statusClass(this.engine.pipeline_loaded)}">${this.engine.pipeline_loaded}</td></tr>
                <tr><td>NATS</td><td class="${this.statusClass(this.engine.nats_connected)}">${this.engine.nats_connected}</td></tr>
                <tr><td>Gallery Size</td><td>${this.engine.gallery_size}</td></tr>
                <tr><td>Database</td><td class="${this.statusClass(this.engine.db_connected)}">${this.engine.db_connected}</td></tr>
                <tr><td>Version</td><td>${this.engine.version}</td></tr>
              </table>
            ` : ''}
        </div>

        <div class="service-card">
          <div class="service-header">
            <h2>NATS</h2>
            <status-indicator
              ?connected=${!!this.gateway?.nats_connected}
              label=${this.gateway?.nats_connected ? 'Connected' : 'Down'}
            ></status-indicator>
          </div>
          <table>
            <tr><td>Status</td><td class="${this.statusClass(this.gateway?.nats_connected)}">${this.gateway?.nats_connected ? 'Connected' : 'Unreachable'}</td></tr>
            <tr><td>Port</td><td>4222 (internal) / 9502 (host)</td></tr>
            <tr><td>Monitoring</td><td>8222 (internal) / 9501 (host)</td></tr>
          </table>
        </div>
      </div>
    `;
  }
}
