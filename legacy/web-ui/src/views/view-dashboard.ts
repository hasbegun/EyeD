import { LitElement, html, css, nothing } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import type { AnalyzeResult } from '../types/api.js';

const MAX_RESULTS = 50;

@customElement('view-dashboard')
export class ViewDashboard extends LitElement {
  @state() private results: AnalyzeResult[] = [];
  @state() private stats = { total: 0, matches: 0, errors: 0 };

  private boundHandler = this.onResult.bind(this);

  static styles = css`
    :host { display: block; }
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-md);
    }
    .stats {
      display: flex;
      gap: var(--eyed-spacing-md);
      margin-bottom: var(--eyed-spacing-lg);
    }
    .stat-card {
      flex: 1;
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-md);
    }
    .stat-card .value {
      font-size: 1.75rem;
      font-weight: 700;
      font-family: var(--eyed-font-mono);
    }
    .stat-card .label {
      font-size: 0.75rem;
      color: var(--eyed-text-muted);
      margin-top: var(--eyed-spacing-xs);
    }
    .value.match { color: var(--eyed-success); }
    .value.error { color: var(--eyed-danger); }

    h2 {
      font-size: 1.125rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-sm);
    }
    .feed {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      overflow: hidden;
    }
    .feed-empty {
      padding: var(--eyed-spacing-lg);
      text-align: center;
      color: var(--eyed-text-muted);
    }
    .result-row {
      display: flex;
      align-items: center;
      gap: var(--eyed-spacing-md);
      padding: var(--eyed-spacing-sm) var(--eyed-spacing-md);
      border-bottom: 1px solid var(--eyed-border);
      font-size: 0.8125rem;
      font-family: var(--eyed-font-mono);
    }
    .result-row:last-child { border-bottom: none; }
    .result-row.is-match { border-left: 3px solid var(--eyed-success); }
    .result-row.is-error { border-left: 3px solid var(--eyed-danger); }
    .result-row.no-match { border-left: 3px solid var(--eyed-warning); }

    .col-device { width: 100px; color: var(--eyed-text-muted); }
    .col-frame  { width: 80px; color: var(--eyed-text-muted); }
    .col-hd     { width: 80px; }
    .col-status { flex: 1; }
    .col-latency {
      width: 70px;
      text-align: right;
      color: var(--eyed-text-muted);
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
    this.results = [r, ...this.results].slice(0, MAX_RESULTS);
    this.stats = {
      total: this.stats.total + 1,
      matches: this.stats.matches + (r.match?.is_match ? 1 : 0),
      errors: this.stats.errors + (r.error ? 1 : 0),
    };
  }

  private rowClass(r: AnalyzeResult): string {
    if (r.error) return 'result-row is-error';
    if (r.match?.is_match) return 'result-row is-match';
    return 'result-row no-match';
  }

  render() {
    return html`
      <h1>Dashboard</h1>

      <div class="stats">
        <div class="stat-card">
          <div class="value">${this.stats.total}</div>
          <div class="label">Frames Processed</div>
        </div>
        <div class="stat-card">
          <div class="value match">${this.stats.matches}</div>
          <div class="label">Matches</div>
        </div>
        <div class="stat-card">
          <div class="value error">${this.stats.errors}</div>
          <div class="label">Errors</div>
        </div>
      </div>

      <h2>Live Results</h2>
      <div class="feed">
        ${this.results.length === 0
          ? html`<div class="feed-empty">Waiting for analysis results...</div>`
          : this.results.map(r => html`
            <div class="${this.rowClass(r)}">
              <span class="col-device">${r.device_id}</span>
              <span class="col-frame">#${r.frame_id}</span>
              <span class="col-hd">${r.match
                ? r.match.hamming_distance.toFixed(4)
                : nothing}</span>
              <span class="col-status">${
                r.error ? r.error
                : r.match?.is_match ? `Match: ${r.match.matched_identity_id || 'unknown'}`
                : 'No match'
              }</span>
              <span class="col-latency">${r.latency_ms.toFixed(0)}ms</span>
            </div>
          `)}
      </div>
    `;
  }
}
