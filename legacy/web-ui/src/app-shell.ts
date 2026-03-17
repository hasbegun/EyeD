import { LitElement, html, css } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import { initRouter } from './router.js';
import { ResultsSocket } from './services/websocket.js';
import type { AnalyzeResult } from './types/api.js';
import './components/nav-sidebar.js';
import './components/status-indicator.js';

@customElement('eyed-app')
export class EyedApp extends LitElement {
  @state() private wsConnected = false;
  @state() private results: AnalyzeResult[] = [];

  private socket: ResultsSocket | null = null;

  static styles = css`
    :host {
      display: flex;
      height: 100vh;
      color: var(--eyed-text);
      background: var(--eyed-bg);
      font-family: var(--eyed-font);
    }
    main {
      flex: 1;
      overflow-y: auto;
      padding: var(--eyed-spacing-lg);
    }
  `;

  connectedCallback() {
    super.connectedCallback();
    this.socket = new ResultsSocket(
      (result) => {
        this.results = [result, ...this.results].slice(0, 200);
        // Dispatch event so views can listen
        this.dispatchEvent(new CustomEvent('eyed-result', {
          detail: result,
          bubbles: true,
          composed: true,
        }));
      },
      (connected) => {
        this.wsConnected = connected;
      },
    );
    this.socket.connect();
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.socket?.disconnect();
    this.socket = null;
  }

  firstUpdated() {
    const outlet = this.renderRoot.querySelector('#outlet');
    if (outlet) {
      initRouter(outlet as HTMLElement);
    }
  }

  render() {
    return html`
      <nav-sidebar .wsConnected=${this.wsConnected}></nav-sidebar>
      <main id="outlet"></main>
    `;
  }
}
