import { LitElement, html, css } from 'lit';
import { customElement, property } from 'lit/decorators.js';

@customElement('status-indicator')
export class StatusIndicator extends LitElement {
  @property({ type: Boolean }) connected = false;
  @property({ type: String }) label = '';

  static styles = css`
    :host {
      display: inline-flex;
      align-items: center;
      gap: var(--eyed-spacing-xs);
      font-size: 0.75rem;
      color: var(--eyed-text-muted);
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--eyed-danger);
      transition: background 0.3s;
    }
    :host([connected]) .dot {
      background: var(--eyed-success);
    }
  `;

  render() {
    return html`
      <span class="dot"></span>
      ${this.label || (this.connected ? 'Connected' : 'Disconnected')}
    `;
  }
}
