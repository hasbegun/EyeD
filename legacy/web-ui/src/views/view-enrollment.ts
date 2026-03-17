import { LitElement, html, css } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import type { DatasetInfo, DatasetImage, EnrollResponse, GalleryIdentity } from '../types/api.js';
import {
  listDatasets,
  listDatasetImages,
  getDatasetImageUrl,
  enroll,
  listGallery,
  deleteIdentity,
} from '../services/gateway-client.js';

@customElement('view-enrollment')
export class ViewEnrollment extends LitElement {
  // Dataset browser state
  @state() private datasets: DatasetInfo[] = [];
  @state() private selectedDataset = '';
  @state() private subjects: string[] = [];
  @state() private selectedSubject = '';
  @state() private images: DatasetImage[] = [];
  @state() private selectedImage: DatasetImage | null = null;

  // Enrollment form state
  @state() private identityName = '';
  @state() private eyeSide = 'left';
  @state() private enrolling = false;
  @state() private enrollResult: EnrollResponse | null = null;
  @state() private enrollError = '';

  // Gallery state
  @state() private galleryEntries: GalleryIdentity[] = [];

  static styles = css`
    :host { display: block; }
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-md);
    }
    h2 {
      font-size: 1rem;
      font-weight: 600;
      margin: 0 0 var(--eyed-spacing-sm);
    }

    /* Layout */
    .layout {
      display: grid;
      grid-template-columns: 280px 1fr;
      gap: var(--eyed-spacing-lg);
    }
    @media (max-width: 768px) {
      .layout { grid-template-columns: 1fr; }
    }

    /* Dataset browser */
    .browser {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-md);
      max-height: 500px;
      overflow-y: auto;
    }
    .tabs {
      display: flex;
      gap: 4px;
      margin-bottom: var(--eyed-spacing-sm);
    }
    .tab {
      padding: 4px 12px;
      border-radius: var(--eyed-radius);
      font-size: 0.8125rem;
      cursor: pointer;
      background: var(--eyed-bg);
      border: 1px solid var(--eyed-border);
      color: var(--eyed-text-muted);
      font-family: inherit;
    }
    .tab[active] {
      background: var(--eyed-accent-dim);
      border-color: var(--eyed-accent);
      color: var(--eyed-text);
    }
    .subject-list {
      display: flex;
      flex-wrap: wrap;
      gap: 4px;
      margin-bottom: var(--eyed-spacing-sm);
    }
    .subject-btn {
      padding: 2px 8px;
      border-radius: var(--eyed-radius);
      font-size: 0.75rem;
      cursor: pointer;
      background: var(--eyed-bg);
      border: 1px solid var(--eyed-border);
      color: var(--eyed-text-muted);
      font-family: inherit;
    }
    .subject-btn[active] {
      background: var(--eyed-accent-dim);
      border-color: var(--eyed-accent);
      color: var(--eyed-text);
    }
    .image-list {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .image-item {
      display: flex;
      align-items: center;
      gap: var(--eyed-spacing-sm);
      padding: 4px 8px;
      border-radius: var(--eyed-radius);
      cursor: pointer;
      font-size: 0.8125rem;
      color: var(--eyed-text-muted);
      border: 1px solid transparent;
    }
    .image-item:hover { background: var(--eyed-hover); }
    .image-item[active] {
      background: var(--eyed-accent-dim);
      border-color: var(--eyed-accent);
      color: var(--eyed-text);
    }
    .eye-tag {
      font-size: 0.625rem;
      padding: 1px 4px;
      border-radius: 2px;
      background: var(--eyed-border);
      color: var(--eyed-text-muted);
    }

    /* Right panel */
    .right-panel {
      display: flex;
      flex-direction: column;
      gap: var(--eyed-spacing-md);
    }
    .preview-section {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-md);
    }
    .preview-img {
      max-width: 320px;
      border-radius: var(--eyed-radius);
      background: #000;
    }
    .no-selection {
      color: var(--eyed-text-muted);
      padding: var(--eyed-spacing-lg);
      text-align: center;
      border: 1px dashed var(--eyed-border);
      border-radius: var(--eyed-radius);
    }

    /* Enrollment form */
    .form-section {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-md);
    }
    .form-row {
      display: flex;
      gap: var(--eyed-spacing-md);
      align-items: flex-end;
      margin-bottom: var(--eyed-spacing-sm);
      flex-wrap: wrap;
    }
    .form-group {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .form-group.grow { flex: 1; min-width: 150px; }
    label {
      font-size: 0.75rem;
      color: var(--eyed-text-muted);
    }
    input, select {
      background: var(--eyed-bg);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      color: var(--eyed-text);
      padding: 8px 12px;
      font-size: 0.875rem;
      font-family: inherit;
    }
    .btn {
      display: inline-block;
      padding: 8px 16px;
      border-radius: var(--eyed-radius);
      font-size: 0.875rem;
      font-family: inherit;
      cursor: pointer;
      border: 1px solid var(--eyed-border);
      transition: background 0.15s;
    }
    .btn-primary {
      background: var(--eyed-accent-dim);
      color: var(--eyed-text);
      border-color: var(--eyed-accent);
    }
    .btn-primary:hover { background: var(--eyed-accent); color: #000; }
    .btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }
    .btn-danger {
      background: transparent;
      color: var(--eyed-danger);
      border-color: var(--eyed-danger);
      padding: 4px 10px;
      font-size: 0.75rem;
    }
    .btn-danger:hover { background: var(--eyed-danger); color: #fff; }

    /* Results */
    .result-msg {
      margin-top: var(--eyed-spacing-sm);
      padding: var(--eyed-spacing-sm);
      border-radius: var(--eyed-radius);
      font-size: 0.8125rem;
    }
    .result-msg.success {
      background: rgba(0, 200, 100, 0.1);
      border: 1px solid var(--eyed-success);
      color: var(--eyed-success);
    }
    .result-msg.duplicate {
      background: rgba(255, 200, 0, 0.1);
      border: 1px solid var(--eyed-warning);
      color: var(--eyed-warning);
    }
    .result-msg.error {
      background: rgba(255, 80, 80, 0.1);
      border: 1px solid var(--eyed-danger);
      color: var(--eyed-danger);
    }

    /* Gallery table */
    .gallery-section {
      margin-top: var(--eyed-spacing-lg);
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.8125rem;
    }
    th {
      text-align: left;
      padding: 8px;
      color: var(--eyed-text-muted);
      border-bottom: 1px solid var(--eyed-border);
      font-weight: 500;
    }
    td {
      padding: 8px;
      border-bottom: 1px solid var(--eyed-border);
      font-family: var(--eyed-font-mono);
    }
    td.name-col { font-family: inherit; }
    .mono { font-size: 0.6875rem; color: var(--eyed-text-muted); }
    .template-tags {
      display: flex;
      gap: 4px;
    }
    .template-tag {
      font-size: 0.625rem;
      padding: 1px 6px;
      border-radius: 2px;
      background: var(--eyed-border);
      color: var(--eyed-text-muted);
    }
    .empty-gallery {
      color: var(--eyed-text-muted);
      font-size: 0.8125rem;
      padding: var(--eyed-spacing-md);
      text-align: center;
    }
  `;

  connectedCallback() {
    super.connectedCallback();
    this.loadDatasets();
    this.loadGallery();
  }

  private async loadDatasets() {
    try {
      this.datasets = await listDatasets();
      if (this.datasets.length > 0 && !this.selectedDataset) {
        this.selectDataset(this.datasets[0].name);
      }
    } catch (e) {
      console.error('Failed to load datasets', e);
    }
  }

  private async selectDataset(name: string) {
    this.selectedDataset = name;
    this.selectedSubject = '';
    this.selectedImage = null;
    this.enrollResult = null;
    this.enrollError = '';
    try {
      const images = await listDatasetImages(name);
      this.images = images;
      const subjectSet = new Set(images.map(i => i.subject_id));
      this.subjects = [...subjectSet].sort();
      if (this.subjects.length > 0) {
        this.selectedSubject = this.subjects[0];
      }
    } catch (e) {
      console.error('Failed to load images', e);
    }
  }

  private selectSubject(subject: string) {
    this.selectedSubject = subject;
    this.selectedImage = null;
    this.enrollResult = null;
    this.enrollError = '';
  }

  private selectImage(img: DatasetImage) {
    this.selectedImage = img;
    this.eyeSide = img.eye_side;
    this.enrollResult = null;
    this.enrollError = '';
  }

  private async loadGallery() {
    try {
      this.galleryEntries = await listGallery();
    } catch (e) {
      console.error('Failed to load gallery', e);
    }
  }

  private async doEnroll() {
    if (!this.selectedImage || !this.identityName.trim()) return;

    this.enrolling = true;
    this.enrollResult = null;
    this.enrollError = '';

    try {
      // Fetch image and convert to base64
      const imageUrl = getDatasetImageUrl(this.selectedDataset, this.selectedImage.path);
      const imageResp = await fetch(imageUrl);
      if (!imageResp.ok) throw new Error(`Failed to fetch image: ${imageResp.status}`);
      const buf = await imageResp.arrayBuffer();
      const bytes = new Uint8Array(buf);
      let binary = '';
      for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      const jpegB64 = btoa(binary);

      const identityId = crypto.randomUUID();
      const result = await enroll(
        jpegB64,
        this.eyeSide,
        identityId,
        this.identityName.trim(),
      );
      this.enrollResult = result;
      if (result.template_id && !result.is_duplicate) {
        await this.loadGallery();
      }
    } catch (e) {
      this.enrollError = e instanceof Error ? e.message : 'Enrollment failed';
    } finally {
      this.enrolling = false;
    }
  }

  private async doDelete(identityId: string) {
    try {
      await deleteIdentity(identityId);
      await this.loadGallery();
    } catch (e) {
      console.error('Failed to delete identity', e);
    }
  }

  private get filteredImages(): DatasetImage[] {
    if (!this.selectedSubject) return [];
    return this.images.filter(i => i.subject_id === this.selectedSubject);
  }

  render() {
    return html`
      <h1>Enrollment</h1>
      <div class="layout">
        ${this.renderBrowser()}
        ${this.renderRightPanel()}
      </div>
      ${this.renderGallery()}
    `;
  }

  private renderBrowser() {
    return html`
      <div class="browser">
        <h2>Dataset Browser</h2>
        <div class="tabs">
          ${this.datasets.map(ds => html`
            <button
              class="tab"
              ?active=${ds.name === this.selectedDataset}
              @click=${() => this.selectDataset(ds.name)}
            >${ds.name}</button>
          `)}
        </div>

        ${this.subjects.length > 0 ? html`
          <label>Subjects</label>
          <div class="subject-list">
            ${this.subjects.map(s => html`
              <button
                class="subject-btn"
                ?active=${s === this.selectedSubject}
                @click=${() => this.selectSubject(s)}
              >${s}</button>
            `)}
          </div>
        ` : ''}

        <div class="image-list">
          ${this.filteredImages.map(img => html`
            <div
              class="image-item"
              ?active=${this.selectedImage?.path === img.path}
              @click=${() => this.selectImage(img)}
            >
              <span class="eye-tag">${img.eye_side === 'left' ? 'L' : 'R'}</span>
              ${img.filename}
            </div>
          `)}
        </div>
      </div>
    `;
  }

  private renderRightPanel() {
    if (!this.selectedImage) {
      return html`
        <div class="right-panel">
          <div class="no-selection">
            Select a dataset image to enroll as a new identity.
          </div>
        </div>
      `;
    }

    const imgUrl = getDatasetImageUrl(this.selectedDataset, this.selectedImage.path);

    return html`
      <div class="right-panel">
        <div class="preview-section">
          <h2>Selected Image</h2>
          <img class="preview-img" src="${imgUrl}" alt="${this.selectedImage.filename}" />
          <div style="margin-top: var(--eyed-spacing-sm); font-size: 0.8125rem; color: var(--eyed-text-muted);">
            ${this.selectedImage.filename} (${this.selectedImage.eye_side} eye, subject ${this.selectedImage.subject_id})
          </div>
        </div>

        <div class="form-section">
          <h2>Enroll Identity</h2>
          <div class="form-row">
            <div class="form-group grow">
              <label>Identity Name</label>
              <input
                type="text"
                placeholder="Jane Doe"
                .value=${this.identityName}
                @input=${(e: Event) => { this.identityName = (e.target as HTMLInputElement).value; }}
              />
            </div>
            <div class="form-group">
              <label>Eye Side</label>
              <select
                .value=${this.eyeSide}
                @change=${(e: Event) => { this.eyeSide = (e.target as HTMLSelectElement).value; }}
              >
                <option value="left">Left</option>
                <option value="right">Right</option>
              </select>
            </div>
            <button
              class="btn btn-primary"
              ?disabled=${this.enrolling || !this.identityName.trim()}
              @click=${this.doEnroll}
            >
              ${this.enrolling ? 'Enrolling...' : 'Enroll'}
            </button>
          </div>

          ${this.renderEnrollResult()}
        </div>
      </div>
    `;
  }

  private renderEnrollResult() {
    if (this.enrollError) {
      return html`<div class="result-msg error">${this.enrollError}</div>`;
    }
    if (!this.enrollResult) return '';

    const r = this.enrollResult;
    if (r.error) {
      return html`<div class="result-msg error">${r.error}</div>`;
    }
    if (r.is_duplicate) {
      return html`<div class="result-msg duplicate">
        Duplicate detected: this iris is already enrolled as identity ${r.duplicate_identity_id}
      </div>`;
    }
    return html`<div class="result-msg success">
      Enrolled successfully. Template ID: <span class="mono">${r.template_id}</span>
    </div>`;
  }

  private renderGallery() {
    return html`
      <div class="gallery-section">
        <h2>Enrolled Identities (${this.galleryEntries.length})</h2>
        ${this.galleryEntries.length === 0
          ? html`<div class="empty-gallery">No identities enrolled yet.</div>`
          : html`
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Identity ID</th>
                  <th>Templates</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                ${this.galleryEntries.map(g => html`
                  <tr>
                    <td class="name-col">${g.name || '(unnamed)'}</td>
                    <td><span class="mono">${g.identity_id.slice(0, 8)}...</span></td>
                    <td>
                      <div class="template-tags">
                        ${g.templates.map(t => html`
                          <span class="template-tag">${t.eye_side}</span>
                        `)}
                      </div>
                    </td>
                    <td>
                      <button
                        class="btn btn-danger"
                        @click=${() => this.doDelete(g.identity_id)}
                      >Delete</button>
                    </td>
                  </tr>
                `)}
              </tbody>
            </table>
          `}
      </div>
    `;
  }
}
