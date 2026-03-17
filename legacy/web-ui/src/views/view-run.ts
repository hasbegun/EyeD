import { LitElement, html, css, nothing } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import type { DatasetInfo, DatasetImage, DetailedResult } from '../types/api.js';
import {
  listDatasets,
  listDatasetImages,
  getDatasetImageUrl,
  analyzeDetailed,
} from '../services/gateway-client.js';

@customElement('view-run')
export class ViewRun extends LitElement {
  @state() private datasets: DatasetInfo[] = [];
  @state() private selectedDataset = '';
  @state() private subjects: string[] = [];
  @state() private selectedSubject = '';
  @state() private images: DatasetImage[] = [];
  @state() private selectedImage: DatasetImage | null = null;
  @state() private result: DetailedResult | null = null;
  @state() private loading = false;
  @state() private analyzing = false;
  @state() private error = '';

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
      color: var(--eyed-text-muted);
    }
    .layout {
      display: grid;
      grid-template-columns: 280px 1fr;
      gap: var(--eyed-spacing-lg);
      min-height: 0;
    }
    @media (max-width: 768px) {
      .layout { grid-template-columns: 1fr; }
    }

    /* --- Browser panel --- */
    .browser {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-md);
      overflow-y: auto;
      max-height: calc(100vh - 120px);
    }
    .ds-tabs {
      display: flex;
      gap: 4px;
      margin-bottom: var(--eyed-spacing-md);
    }
    .ds-tab {
      flex: 1;
      padding: 6px 8px;
      background: var(--eyed-bg);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      color: var(--eyed-text-muted);
      font-size: 0.75rem;
      font-family: inherit;
      cursor: pointer;
      text-align: center;
    }
    .ds-tab:hover { background: var(--eyed-hover); }
    .ds-tab[active] {
      background: var(--eyed-accent-dim);
      color: var(--eyed-text);
      border-color: var(--eyed-accent);
    }
    .subject-list {
      display: flex;
      flex-wrap: wrap;
      gap: 4px;
      margin-bottom: var(--eyed-spacing-md);
      max-height: 120px;
      overflow-y: auto;
    }
    .subject-btn {
      padding: 2px 8px;
      background: var(--eyed-bg);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      color: var(--eyed-text-muted);
      font-size: 0.6875rem;
      font-family: var(--eyed-font-mono);
      cursor: pointer;
    }
    .subject-btn:hover { background: var(--eyed-hover); }
    .subject-btn[active] {
      background: var(--eyed-accent-dim);
      color: var(--eyed-text);
      border-color: var(--eyed-accent);
    }
    .image-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(60px, 1fr));
      gap: 4px;
    }
    .image-thumb {
      aspect-ratio: 1;
      border: 2px solid transparent;
      border-radius: var(--eyed-radius);
      overflow: hidden;
      cursor: pointer;
      position: relative;
    }
    .image-thumb img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      filter: grayscale(0.5);
    }
    .image-thumb:hover { border-color: var(--eyed-border); }
    .image-thumb:hover img { filter: none; }
    .image-thumb[selected] {
      border-color: var(--eyed-accent);
    }
    .image-thumb[selected] img { filter: none; }
    .eye-badge {
      position: absolute;
      bottom: 2px;
      right: 2px;
      font-size: 0.5rem;
      background: rgba(0,0,0,0.7);
      color: var(--eyed-text-muted);
      padding: 1px 3px;
      border-radius: 2px;
    }
    .action-bar {
      margin-top: var(--eyed-spacing-md);
      display: flex;
      gap: var(--eyed-spacing-sm);
      align-items: center;
    }
    .btn {
      padding: 8px 16px;
      border-radius: var(--eyed-radius);
      font-size: 0.875rem;
      font-family: inherit;
      cursor: pointer;
      border: 1px solid var(--eyed-border);
    }
    .btn-primary {
      background: var(--eyed-accent-dim);
      color: var(--eyed-text);
      border-color: var(--eyed-accent);
    }
    .btn-primary:hover { background: var(--eyed-accent); color: #000; }
    .btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }
    .latency {
      font-size: 0.75rem;
      color: var(--eyed-text-muted);
      font-family: var(--eyed-font-mono);
    }

    /* --- Results panel --- */
    .results {
      overflow-y: auto;
      max-height: calc(100vh - 120px);
    }
    .empty {
      color: var(--eyed-text-muted);
      padding: var(--eyed-spacing-lg);
      border: 1px dashed var(--eyed-border);
      border-radius: var(--eyed-radius);
      text-align: center;
    }
    .error-msg {
      color: var(--eyed-danger);
      padding: var(--eyed-spacing-md);
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-danger);
      border-radius: var(--eyed-radius);
    }
    .warning-msg {
      color: var(--eyed-warning);
      padding: var(--eyed-spacing-sm) var(--eyed-spacing-md);
      background: rgba(210, 153, 34, 0.1);
      border: 1px solid var(--eyed-warning);
      border-radius: var(--eyed-radius);
      margin-bottom: var(--eyed-spacing-md);
      font-size: 0.8125rem;
    }
    .section {
      background: var(--eyed-surface);
      border: 1px solid var(--eyed-border);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-md);
      margin-bottom: var(--eyed-spacing-md);
    }
    .image-pair {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: var(--eyed-spacing-sm);
    }
    @media (max-width: 900px) {
      .image-pair { grid-template-columns: 1fr; }
    }
    .img-card {
      text-align: center;
    }
    .img-card img {
      max-width: 100%;
      border-radius: var(--eyed-radius);
      border: 1px solid var(--eyed-border);
    }
    .img-label {
      font-size: 0.6875rem;
      color: var(--eyed-text-muted);
      margin-top: 4px;
    }
    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
      gap: var(--eyed-spacing-sm);
    }
    .metric {
      background: var(--eyed-bg);
      border-radius: var(--eyed-radius);
      padding: var(--eyed-spacing-sm);
    }
    .metric-label {
      font-size: 0.6875rem;
      color: var(--eyed-text-muted);
      margin-bottom: 2px;
    }
    .metric-value {
      font-size: 1rem;
      font-family: var(--eyed-font-mono);
      color: var(--eyed-text);
    }
    .match-result {
      display: flex;
      align-items: center;
      gap: var(--eyed-spacing-sm);
      padding: var(--eyed-spacing-sm);
      border-radius: var(--eyed-radius);
    }
    .match-result.is-match {
      background: rgba(63, 185, 80, 0.15);
      border: 1px solid var(--eyed-success);
    }
    .match-result.no-match {
      background: rgba(210, 153, 34, 0.15);
      border: 1px solid var(--eyed-warning);
    }
    .match-result.no-gallery {
      background: var(--eyed-bg);
      border: 1px solid var(--eyed-border);
    }
    .match-hd {
      font-family: var(--eyed-font-mono);
      font-size: 1.25rem;
    }
    .match-label {
      font-size: 0.8125rem;
    }
    .spinner {
      display: inline-block;
      width: 16px;
      height: 16px;
      border: 2px solid var(--eyed-border);
      border-top-color: var(--eyed-accent);
      border-radius: 50%;
      animation: spin 0.6s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
  `;

  connectedCallback() {
    super.connectedCallback();
    this.loadDatasets();
  }

  private async loadDatasets() {
    this.loading = true;
    try {
      this.datasets = await listDatasets();
      if (this.datasets.length > 0) {
        this.selectedDataset = this.datasets[0].name;
        await this.loadImages();
      }
    } catch (e) {
      this.error = `Failed to load datasets: ${e}`;
    } finally {
      this.loading = false;
    }
  }

  private async selectDataset(name: string) {
    this.selectedDataset = name;
    this.selectedSubject = '';
    this.selectedImage = null;
    this.result = null;
    await this.loadImages();
  }

  private async loadImages() {
    try {
      this.images = await listDatasetImages(this.selectedDataset);
      // Extract unique subjects
      const subjectSet = new Set(this.images.map(i => i.subject_id));
      this.subjects = Array.from(subjectSet).sort();
      if (this.subjects.length > 0 && !this.selectedSubject) {
        this.selectedSubject = this.subjects[0];
      }
    } catch (e) {
      this.error = `Failed to load images: ${e}`;
    }
  }

  private selectSubject(subject: string) {
    this.selectedSubject = subject;
    this.selectedImage = null;
  }

  private selectImage(img: DatasetImage) {
    this.selectedImage = img;
    this.result = null;
  }

  private async runAnalysis() {
    if (!this.selectedImage) return;
    this.analyzing = true;
    this.error = '';
    this.result = null;
    try {
      this.result = await analyzeDetailed(
        this.selectedDataset,
        this.selectedImage.path,
        this.selectedImage.eye_side,
      );
    } catch (e) {
      this.error = `Analysis failed: ${e}`;
    } finally {
      this.analyzing = false;
    }
  }

  private get filteredImages(): DatasetImage[] {
    if (!this.selectedSubject) return this.images;
    return this.images.filter(i => i.subject_id === this.selectedSubject);
  }

  render() {
    return html`
      <h1>Analysis</h1>
      ${this.error ? html`<div class="error-msg">${this.error}</div>` : nothing}
      <div class="layout">
        ${this.renderBrowser()}
        ${this.renderResults()}
      </div>
    `;
  }

  private renderBrowser() {
    return html`
      <div class="browser">
        <h2>Dataset</h2>
        <div class="ds-tabs">
          ${this.datasets.map(ds => html`
            <button
              class="ds-tab"
              ?active=${ds.name === this.selectedDataset}
              @click=${() => this.selectDataset(ds.name)}
            >${ds.name} <span style="opacity:0.5">(${ds.count})</span></button>
          `)}
        </div>

        <h2>Subject</h2>
        <div class="subject-list">
          ${this.subjects.map(s => html`
            <button
              class="subject-btn"
              ?active=${s === this.selectedSubject}
              @click=${() => this.selectSubject(s)}
            >${s}</button>
          `)}
        </div>

        <h2>Images</h2>
        <div class="image-grid">
          ${this.filteredImages.map(img => html`
            <div
              class="image-thumb"
              ?selected=${this.selectedImage?.path === img.path}
              @click=${() => this.selectImage(img)}
            >
              <img
                src="${getDatasetImageUrl(this.selectedDataset, img.path)}"
                alt="${img.filename}"
                loading="lazy"
              />
              <span class="eye-badge">${img.eye_side === 'left' ? 'L' : 'R'}</span>
            </div>
          `)}
        </div>

        <div class="action-bar">
          <button
            class="btn btn-primary"
            ?disabled=${!this.selectedImage || this.analyzing}
            @click=${this.runAnalysis}
          >
            ${this.analyzing ? html`<span class="spinner"></span> Analyzing...` : 'Analyze'}
          </button>
          ${this.result ? html`
            <span class="latency">${this.result.latency_ms.toFixed(0)}ms</span>
          ` : nothing}
        </div>
      </div>
    `;
  }

  private renderResults() {
    if (!this.result) {
      return html`
        <div class="results">
          <div class="empty">
            ${this.selectedImage
              ? 'Select an image and click "Analyze" to run the pipeline.'
              : 'Select a dataset image from the browser to begin.'}
          </div>
        </div>
      `;
    }

    const r = this.result;
    const hasVisuals = r.segmentation_overlay_b64 || r.normalized_iris_b64
      || r.iris_code_b64 || r.quality || r.geometry;

    return html`
      <div class="results">
        ${r.error ? html`
          <div class="${hasVisuals ? 'warning-msg' : 'error-msg'}">
            ${hasVisuals
              ? `Pipeline partially completed: some stages failed. ${r.error}`
              : `Pipeline error: ${r.error}`}
          </div>
        ` : nothing}

        <!-- Segmentation -->
        <div class="section">
          <h2>Segmentation</h2>
          <div class="image-pair">
            ${r.original_image_b64 ? html`
              <div class="img-card">
                <img src="data:image/png;base64,${r.original_image_b64}" />
                <div class="img-label">Original</div>
              </div>
            ` : nothing}
            ${r.segmentation_overlay_b64 ? html`
              <div class="img-card">
                <img src="data:image/png;base64,${r.segmentation_overlay_b64}" />
                <div class="img-label">Pupil / Iris Contours</div>
              </div>
            ` : nothing}
          </div>
        </div>

        <!-- Normalized Iris + Iris Code -->
        <div class="section">
          <h2>Pipeline Outputs</h2>
          <div class="image-pair">
            ${r.normalized_iris_b64 ? html`
              <div class="img-card">
                <img src="data:image/png;base64,${r.normalized_iris_b64}" />
                <div class="img-label">Normalized Iris (128 x 512)</div>
              </div>
            ` : nothing}
            ${r.iris_code_b64 ? html`
              <div class="img-card">
                <img src="data:image/png;base64,${r.iris_code_b64}" />
                <div class="img-label">Iris Code</div>
              </div>
            ` : nothing}
          </div>
          ${r.noise_mask_b64 ? html`
            <div class="img-card" style="margin-top: var(--eyed-spacing-sm);">
              <img src="data:image/png;base64,${r.noise_mask_b64}" style="max-width:320px;" />
              <div class="img-label">Noise Mask</div>
            </div>
          ` : nothing}
        </div>

        <!-- Quality Metrics -->
        ${r.quality ? html`
          <div class="section">
            <h2>Quality Metrics</h2>
            <div class="metrics-grid">
              <div class="metric">
                <div class="metric-label">Sharpness</div>
                <div class="metric-value">${r.quality.sharpness.toFixed(1)}</div>
              </div>
              <div class="metric">
                <div class="metric-label">Offgaze</div>
                <div class="metric-value">${r.quality.offgaze_score.toFixed(6)}</div>
              </div>
              <div class="metric">
                <div class="metric-label">Occlusion (90)</div>
                <div class="metric-value">${(r.quality.occlusion_90 * 100).toFixed(1)}%</div>
              </div>
              <div class="metric">
                <div class="metric-label">Occlusion (30)</div>
                <div class="metric-value">${(r.quality.occlusion_30 * 100).toFixed(1)}%</div>
              </div>
              <div class="metric">
                <div class="metric-label">Pupil/Iris Ratio</div>
                <div class="metric-value">${r.quality.pupil_iris_ratio.toFixed(3)}</div>
              </div>
            </div>
          </div>
        ` : nothing}

        <!-- Geometry -->
        ${r.geometry ? html`
          <div class="section">
            <h2>Geometry</h2>
            <div class="metrics-grid">
              <div class="metric">
                <div class="metric-label">Pupil Center</div>
                <div class="metric-value">(${r.geometry.pupil_center[0].toFixed(1)}, ${r.geometry.pupil_center[1].toFixed(1)})</div>
              </div>
              <div class="metric">
                <div class="metric-label">Iris Center</div>
                <div class="metric-value">(${r.geometry.iris_center[0].toFixed(1)}, ${r.geometry.iris_center[1].toFixed(1)})</div>
              </div>
              <div class="metric">
                <div class="metric-label">Pupil Radius</div>
                <div class="metric-value">${r.geometry.pupil_radius.toFixed(1)} px</div>
              </div>
              <div class="metric">
                <div class="metric-label">Iris Radius</div>
                <div class="metric-value">${r.geometry.iris_radius.toFixed(1)} px</div>
              </div>
              <div class="metric">
                <div class="metric-label">Eye Orientation</div>
                <div class="metric-value">${(r.geometry.eye_orientation * 180 / Math.PI).toFixed(2)}&deg;</div>
              </div>
            </div>
          </div>
        ` : nothing}

        <!-- Match Result -->
        <div class="section">
          <h2>Match Result</h2>
          ${r.match ? html`
            <div class="match-result ${r.match.is_match ? 'is-match' : 'no-match'}">
              <span class="match-hd">${r.match.hamming_distance.toFixed(4)}</span>
              <span class="match-label">
                ${r.match.is_match
                  ? `Match: ${r.match.matched_identity_id || 'unknown'}`
                  : 'No match found'}
              </span>
            </div>
          ` : r.error ? html`
            <div class="match-result no-gallery">
              <span class="match-label">No template produced — matching unavailable for this image.</span>
            </div>
          ` : html`
            <div class="match-result no-gallery">
              <span class="match-label">Gallery is empty. Enroll templates to enable matching.</span>
            </div>
          `}
        </div>
      </div>
    `;
  }
}
