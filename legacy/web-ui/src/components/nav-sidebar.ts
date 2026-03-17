import { LitElement, html, css } from 'lit';
import { customElement, property } from 'lit/decorators.js';
import './status-indicator.js';

interface NavItem {
  path: string;
  label: string;
  icon: string;
}

const NAV_ITEMS: NavItem[] = [
  { path: '/dashboard',  label: 'Dashboard',  icon: '\u25A3' },
  { path: '/devices',    label: 'Devices',    icon: '\u25CE' },
  { path: '/enrollment', label: 'Enrollment', icon: '\u2795' },
  { path: '/analysis',   label: 'Analysis',   icon: '\u25B6' },
  { path: '/history',    label: 'History',    icon: '\u2630' },
  { path: '/admin',      label: 'Admin',      icon: '\u2699' },
];

@customElement('nav-sidebar')
export class NavSidebar extends LitElement {
  @property({ type: Boolean }) wsConnected = false;

  static styles = css`
    :host {
      display: flex;
      flex-direction: column;
      width: 220px;
      background: var(--eyed-surface);
      border-right: 1px solid var(--eyed-border);
      padding: var(--eyed-spacing-md) 0;
    }
    .brand {
      padding: var(--eyed-spacing-md) var(--eyed-spacing-lg);
      font-size: 1.25rem;
      font-weight: 700;
      color: var(--eyed-accent);
      letter-spacing: 0.05em;
    }
    nav {
      display: flex;
      flex-direction: column;
      gap: 2px;
      margin-top: var(--eyed-spacing-md);
    }
    a {
      display: flex;
      align-items: center;
      gap: var(--eyed-spacing-sm);
      padding: var(--eyed-spacing-sm) var(--eyed-spacing-lg);
      color: var(--eyed-text-muted);
      text-decoration: none;
      font-size: 0.875rem;
      border-left: 3px solid transparent;
      transition: background 0.15s, color 0.15s;
    }
    a:hover {
      background: var(--eyed-hover);
      color: var(--eyed-text);
    }
    a[active] {
      color: var(--eyed-accent);
      border-left-color: var(--eyed-accent);
      background: var(--eyed-hover);
    }
    .icon {
      font-size: 1.1rem;
      width: 1.5rem;
      text-align: center;
    }
    .status {
      margin-top: auto;
      padding: var(--eyed-spacing-md) var(--eyed-spacing-lg);
      border-top: 1px solid var(--eyed-border);
    }
  `;

  render() {
    const current = window.location.pathname;
    return html`
      <div class="brand">EyeD</div>
      <nav>
        ${NAV_ITEMS.map(item => html`
          <a href="${item.path}" ?active=${current.startsWith(item.path)}>
            <span class="icon">${item.icon}</span>
            ${item.label}
          </a>
        `)}
      </nav>
      <div class="status">
        <status-indicator
          ?connected=${this.wsConnected}
          label=${this.wsConnected ? 'Live' : 'Offline'}
        ></status-indicator>
      </div>
    `;
  }
}
