import { LitElement, html, css } from 'lit';
import { customElement } from 'lit/decorators.js';

@customElement('view-not-found')
export class ViewNotFound extends LitElement {
  static styles = css`
    :host { display: block; }
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-md);
    }
    .placeholder {
      color: var(--eyed-text-muted);
      padding: var(--eyed-spacing-lg);
      border: 1px dashed var(--eyed-border);
      border-radius: var(--eyed-radius);
      text-align: center;
    }
  `;

  render() {
    return html`
      <h1>Not Found</h1>
      <div class="placeholder">
        The page you are looking for does not exist.
      </div>
    `;
  }
}
