import { LitElement, html, css, nothing } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import type { AnalyzeResult } from '../types/api.js';

type Filter = 'all' | 'match' | 'no-match' | 'error';

const MAX_HISTORY = 500;

@customElement('view-history')
export class ViewHistory extends LitElement {
  @state() private history: (AnalyzeResult & { ts: number })[] = [];
  @state() private filter: Filter = 'all';
  @state() private search = '';

  private boundHandler = this.onResult.bind(this);

  static styles = css`
    :host { display: block; }
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-md);
    }
    .toolbar {
      display: flex;
      gap: var(--eyed-spacing-sm);
      margin-bottom: var(--eyed-spacing-md);
      align-items: center;
      flex-wrap: wrap;
    }
    .filter-btn {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      color: var(--eyed-text-muted);
      padding: 4px 12px;
      font-size: 0.75rem;
      cursor: pointer;
      font-family: inherit;
    }
    .filter-btn:hover { background: var(--eyed-hover); }
    .filter-btn[active] {
      background: var(--eyed-accent-dim);
      color: var(--eyed-text);
      border-color: var(--eyed-accent);
    }
    input[type="search"] {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      color: var(--eyed-text);
      padding: 4px 12px;
      font-size: 0.8125rem;
      font-family: inherit;
      flex: 1;
      min-width: 150px;
    }
    input::placeholder { color: var(--eyed-text-muted); }
    .count {
      font-size: 0.75rem;
      color: var(--eyed-text-muted);
      margin-left: auto;
    }
    .log {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      overflow: hidden;
    }
    .log-empty {
      padding: var(--eyed-spacing-lg);
      text-align: center;
      color: var(--eyed-text-muted);
    }
    .log-header, .log-row {
      display: grid;
      grid-template-columns: 60px 100px 80px 80px 1fr 70px;
      gap: var(--eyed-spacing-sm);
      padding: 6px var(--eyed-spacing-md);
      font-size: 0.75rem;
      font-family: var(--eyed-font-mono);
      align-items: center;
    }
    .log-header {
      background: var(--eyed-hover);
      color: var(--eyed-text-muted);
      font-weight: 600;
      font-family: var(--eyed-font);
      border-bottom: 1px solid var(--eyed-border);
    }
    .log-row {
      border-bottom: 1px solid var(--eyed-border);
    }
    .log-row:last-child { border-bottom: none; }
    .log-row.is-match { border-left: 3px solid var(--eyed-success); }
    .log-row.is-error { border-left: 3px solid var(--eyed-danger); }
    .log-row.no-match { border-left: 3px solid var(--eyed-warning); }
    .col-time { color: var(--eyed-text-muted); }
    .col-latency { text-align: right; color: var(--eyed-text-muted); }
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
    this.history = [{ ...r, ts: Date.now() }, ...this.history].slice(0, MAX_HISTORY);
  }

  private get filtered() {
    let items = this.history;
    if (this.filter === 'match') items = items.filter(r => r.match?.is_match);
    else if (this.filter === 'no-match') items = items.filter(r => !r.error && !r.match?.is_match);
    else if (this.filter === 'error') items = items.filter(r => !!r.error);

    if (this.search) {
      const q = this.search.toLowerCase();
      items = items.filter(r =>
        r.device_id.toLowerCase().includes(q) ||
        r.frame_id.toLowerCase().includes(q) ||
        (r.match?.matched_identity_id?.toLowerCase().includes(q) ?? false)
      );
    }
    return items;
  }

  private rowClass(r: AnalyzeResult): string {
    if (r.error) return 'log-row is-error';
    if (r.match?.is_match) return 'log-row is-match';
    return 'log-row no-match';
  }

  private formatTime(ts: number): string {
    return new Date(ts).toLocaleTimeString();
  }

  render() {
    const rows = this.filtered;
    return html`
      <h1>History</h1>

      <div class="toolbar">
        ${(['all', 'match', 'no-match', 'error'] as Filter[]).map(f => html`
          <button
            class="filter-btn"
            ?active=${this.filter === f}
            @click=${() => { this.filter = f; }}
          >${f}</button>
        `)}
        <input
          type="search"
          placeholder="Search device, frame, identity..."
          .value=${this.search}
          @input=${(e: Event) => { this.search = (e.target as HTMLInputElement).value; }}
        />
        <span class="count">${rows.length} / ${this.history.length}</span>
      </div>

      <div class="log">
        <div class="log-header">
          <span>Time</span>
          <span>Device</span>
          <span>Frame</span>
          <span>HD</span>
          <span>Status</span>
          <span style="text-align:right">Latency</span>
        </div>
        ${rows.length === 0
          ? html`<div class="log-empty">${this.history.length === 0
              ? 'No results yet. Waiting for analysis data...'
              : 'No results match the current filter.'}</div>`
          : rows.map(r => html`
            <div class="${this.rowClass(r)}">
              <span class="col-time">${this.formatTime(r.ts)}</span>
              <span>${r.device_id}</span>
              <span>#${r.frame_id}</span>
              <span>${r.match ? r.match.hamming_distance.toFixed(4) : nothing}</span>
              <span>${
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
