import { css } from 'lit';

export const cardStyles = css`
  .card {
    background: var(--eyed-surface);
    border: 1px solid var(--eyed-border);
    border-radius: var(--eyed-radius);
    padding: var(--eyed-spacing-md);
  }
`;

export const headingStyles = css`
  h1 {
    font-size: 1.5rem;
    font-weight: 600;
    margin: 0 0 var(--eyed-spacing-md);
  }
  h2 {
    font-size: 1.25rem;
    font-weight: 600;
    margin: 0 0 var(--eyed-spacing-sm);
  }
`;
