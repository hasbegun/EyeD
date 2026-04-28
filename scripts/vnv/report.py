#!/usr/bin/env python3
"""
EyeD V&V HTML Report Generator

Reads summary.json, metadata.json, and plots from a benchmark run directory
and produces a self-contained report.html with all images embedded as base64.

Usage:
    python scripts/vnv/report.py --input reports/vnv/latest
"""

import argparse
import base64
import json
import sys
from datetime import datetime
from pathlib import Path

from jinja2 import Environment, BaseLoader

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def img_to_base64(path: Path) -> str:
    """Convert an image file to a base64 data URI."""
    if not path.exists():
        return ""
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode("ascii")
    suffix = path.suffix.lstrip(".")
    mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg"}.get(suffix, "image/png")
    return f"data:{mime};base64,{data}"


def fmt_rate(value, digits=6):
    """Format a rate value with full precision."""
    if value is None:
        return "N/A"
    return f"{value:.{digits}f}"


def fmt_ms(value, digits=1):
    """Format a millisecond value."""
    if value is None:
        return "N/A"
    return f"{value:.{digits}f}"


def fmt_pct(value, digits=4):
    """Format as percentage."""
    if value is None:
        return "N/A"
    return f"{value * 100:.{digits}f}%"


def gate_badge(passed):
    """Return HTML badge for gate pass/fail."""
    if passed:
        return '<span class="badge pass">PASS</span>'
    return '<span class="badge fail">FAIL</span>'


# ---------------------------------------------------------------------------
# HTML Template
# ---------------------------------------------------------------------------

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>EyeD V&amp;V Report — {{ timestamp }}</title>
<style>
  :root {
    --bg: #f8f9fa; --card: #ffffff; --border: #dee2e6;
    --text: #212529; --muted: #6c757d; --accent: #0d6efd;
    --pass-bg: #d1e7dd; --pass-fg: #0f5132;
    --fail-bg: #f8d7da; --fail-fg: #842029;
    --warn-bg: #fff3cd; --warn-fg: #664d03;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         background: var(--bg); color: var(--text); line-height: 1.6; padding: 2rem; }
  .container { max-width: 1200px; margin: 0 auto; }
  h1 { font-size: 1.8rem; margin-bottom: 0.5rem; }
  h2 { font-size: 1.3rem; margin: 2rem 0 1rem; padding-bottom: 0.3rem;
       border-bottom: 2px solid var(--accent); }
  h3 { font-size: 1.1rem; margin: 1.5rem 0 0.5rem; }
  .subtitle { color: var(--muted); margin-bottom: 2rem; }
  .card { background: var(--card); border: 1px solid var(--border);
          border-radius: 8px; padding: 1.5rem; margin-bottom: 1.5rem; }
  table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
  th, td { padding: 0.5rem 0.75rem; text-align: left; border-bottom: 1px solid var(--border); }
  th { background: var(--bg); font-weight: 600; }
  td.num { text-align: right; font-family: "SF Mono", "Fira Code", monospace; }
  .badge { display: inline-block; padding: 0.15rem 0.6rem; border-radius: 4px;
           font-size: 0.8rem; font-weight: 700; }
  .badge.pass { background: var(--pass-bg); color: var(--pass-fg); }
  .badge.fail { background: var(--fail-bg); color: var(--fail-fg); }
  .badge.warn { background: var(--warn-bg); color: var(--warn-fg); }
  .overall-pass { font-size: 1.2rem; padding: 1rem; text-align: center;
                  border-radius: 8px; font-weight: 700; margin: 1rem 0; }
  .overall-pass.yes { background: var(--pass-bg); color: var(--pass-fg); }
  .overall-pass.no { background: var(--fail-bg); color: var(--fail-fg); }
  .plot-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
  .plot-grid img { width: 100%; border-radius: 6px; border: 1px solid var(--border); }
  .plot-full img { width: 100%; border-radius: 6px; border: 1px solid var(--border); }
  .meta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem 2rem; }
  .meta-grid dt { color: var(--muted); font-size: 0.85rem; }
  .meta-grid dd { font-weight: 500; margin-bottom: 0.5rem; }
  .delta-positive { color: #198754; }
  .delta-negative { color: #dc3545; }
  @media (max-width: 768px) { .plot-grid { grid-template-columns: 1fr; } }
  @media print { body { padding: 0; } .card { break-inside: avoid; } }
</style>
</head>
<body>
<div class="container">

<h1>EyeD V&amp;V Benchmark Report</h1>
<p class="subtitle">Run: {{ timestamp }} &nbsp;|&nbsp; Git: <code>{{ git_sha }}</code> &nbsp;|&nbsp; API: {{ api_version }}</p>

<!-- Overall Result -->
<div class="overall-pass {{ 'yes' if all_gates_pass else 'no' }}">
  {{ 'ALL GATES PASS' if all_gates_pass else 'SOME GATES FAILED' }}
</div>

<!-- Gate Summary -->
<h2>Gate Evaluation</h2>
<div class="card">
<table>
  <tr><th>Gate</th><th>Description</th><th>Value</th><th>Result</th></tr>
  {% for name, gate in gates.items() %}
  <tr>
    <td><code>{{ name }}</code></td>
    <td>{{ gate.description }}</td>
    <td class="num">{{ fmt_rate(gate.value) }}</td>
    <td>{{ gate_badge(gate.passed) }}</td>
  </tr>
  {% endfor %}
</table>
</div>

<!-- Accuracy Metrics -->
<h2>Biometric Accuracy (VNV-1)</h2>
<div class="card">
<h3>Enrollment</h3>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  <tr><td>Total attempts</td><td class="num">{{ enrollment.total }}</td></tr>
  <tr><td>Successful</td><td class="num">{{ enrollment.success }}</td></tr>
  <tr><td>Duplicates</td><td class="num">{{ enrollment.duplicates }}</td></tr>
  <tr><td>Failed</td><td class="num">{{ enrollment.failed }}</td></tr>
  <tr><td>FTE Rate</td><td class="num">{{ fmt_rate(enrollment.fte_rate) }}</td></tr>
</table>

<h3>Genuine Verification</h3>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  <tr><td>Total probes</td><td class="num">{{ genuine.total }}</td></tr>
  <tr><td>Valid (no error)</td><td class="num">{{ genuine.valid }}</td></tr>
  <tr><td>Correct matches</td><td class="num">{{ genuine.correct }}</td></tr>
  <tr><td>False negatives</td><td class="num">{{ genuine.false_negative }}</td></tr>
  <tr><td>Wrong identity</td><td class="num">{{ genuine.wrong_identity }}</td></tr>
  <tr><td>Pipeline failures</td><td class="num">{{ genuine.pipeline_fail }}</td></tr>
  <tr><td><strong>FNMR</strong></td><td class="num"><strong>{{ fmt_rate(genuine.fnmr) }}</strong></td></tr>
  <tr><td>Wrong ID Rate</td><td class="num">{{ fmt_rate(genuine.wrong_id_rate) }}</td></tr>
  <tr><td>FTA Rate</td><td class="num">{{ fmt_rate(genuine.fta_rate) }}</td></tr>
  <tr><td>Genuine HD (mean &plusmn; std)</td><td class="num">{{ fmt_rate(genuine.hd_mean, 4) }} &plusmn; {{ fmt_rate(genuine.hd_std, 4) }}</td></tr>
</table>

<h3>Impostor Verification</h3>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  <tr><td>Total probes</td><td class="num">{{ impostor.total }}</td></tr>
  <tr><td>Valid (no error)</td><td class="num">{{ impostor.valid }}</td></tr>
  <tr><td>True rejects</td><td class="num">{{ impostor.true_reject }}</td></tr>
  <tr><td><strong>False positives</strong></td><td class="num"><strong>{{ impostor.false_positive }}</strong></td></tr>
  <tr><td>Pipeline failures</td><td class="num">{{ impostor.pipeline_fail }}</td></tr>
  <tr><td><strong>FMR</strong></td><td class="num"><strong>{{ fmt_rate(impostor.fmr) }}</strong></td></tr>
  <tr><td>FTA Rate</td><td class="num">{{ fmt_rate(impostor.fta_rate) }}</td></tr>
  <tr><td>Impostor HD (mean &plusmn; std)</td><td class="num">{{ fmt_rate(impostor.hd_mean, 4) }} &plusmn; {{ fmt_rate(impostor.hd_std, 4) }}</td></tr>
</table>

<h3>Threshold Analysis</h3>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  <tr><td>Operational threshold</td><td class="num">{{ operational_threshold }}</td></tr>
  <tr><td>FMR at operational threshold</td><td class="num">{{ fmt_rate(op_fmr) }}</td></tr>
  <tr><td>FNMR at operational threshold</td><td class="num">{{ fmt_rate(op_fnmr) }}</td></tr>
  <tr><td><strong>EER</strong></td><td class="num"><strong>{{ fmt_rate(eer) }}</strong></td></tr>
  <tr><td>EER threshold</td><td class="num">{{ fmt_rate(eer_threshold, 3) }}</td></tr>
  <tr><td>Optimal threshold</td><td class="num">{{ fmt_rate(optimal_threshold, 3) }}</td></tr>
  <tr><td>Decidability (d')</td><td class="num">{{ fmt_rate(decidability, 4) }}</td></tr>
</table>
</div>

<!-- Accuracy Plots -->
<h2>Accuracy Plots</h2>
<div class="card">
{% if img_hd_histogram %}
<div class="plot-full"><img src="{{ img_hd_histogram }}" alt="HD Histogram"></div>
{% endif %}
<div class="plot-grid">
  {% if img_det_curve %}<img src="{{ img_det_curve }}" alt="DET Curve">{% endif %}
  {% if img_roc_curve %}<img src="{{ img_roc_curve }}" alt="ROC Curve">{% endif %}
</div>
{% if img_subject_heatmap %}
<div class="plot-full" style="margin-top:1rem"><img src="{{ img_subject_heatmap }}" alt="Subject Accuracy Heatmap"></div>
{% endif %}
</div>

<!-- Performance -->
<h2>Performance (VNV-2)</h2>
<div class="card">
<h3>Enrollment Latency</h3>
<table>
  <tr><th>Stat</th><th>Value (ms)</th></tr>
  <tr><td>Min</td><td class="num">{{ fmt_ms(enrollment.latency_min_ms) }}</td></tr>
  <tr><td>Mean</td><td class="num">{{ fmt_ms(enrollment.latency_mean_ms) }}</td></tr>
  <tr><td>Median</td><td class="num">{{ fmt_ms(enrollment.latency_median_ms) }}</td></tr>
  <tr><td>P95</td><td class="num">{{ fmt_ms(enrollment.latency_p95_ms) }}</td></tr>
  <tr><td>P99</td><td class="num">{{ fmt_ms(enrollment.latency_p99_ms) }}</td></tr>
  <tr><td>Max</td><td class="num">{{ fmt_ms(enrollment.latency_max_ms) }}</td></tr>
  <tr><td>Std</td><td class="num">{{ fmt_ms(enrollment.latency_std_ms) }}</td></tr>
</table>

<h3>Verification Latency (client-measured)</h3>
<table>
  <tr><th>Stat</th><th>Value (ms)</th></tr>
  <tr><td>Min</td><td class="num">{{ fmt_ms(genuine.client_latency_min_ms) }}</td></tr>
  <tr><td>Mean</td><td class="num">{{ fmt_ms(genuine.client_latency_mean_ms) }}</td></tr>
  <tr><td>Median</td><td class="num">{{ fmt_ms(genuine.client_latency_median_ms) }}</td></tr>
  <tr><td>P95</td><td class="num">{{ fmt_ms(genuine.client_latency_p95_ms) }}</td></tr>
  <tr><td>P99</td><td class="num">{{ fmt_ms(genuine.client_latency_p99_ms) }}</td></tr>
  <tr><td>Server P99</td><td class="num">{{ fmt_ms(genuine.server_latency_p99_ms) }}</td></tr>
</table>
</div>

<!-- Latency Plots -->
<div class="card">
<div class="plot-grid">
  {% if img_enrollment_latency %}<img src="{{ img_enrollment_latency }}" alt="Enrollment Latency">{% endif %}
  {% if img_verification_latency %}<img src="{{ img_verification_latency }}" alt="Verification Latency">{% endif %}
</div>
</div>

<!-- Resource Profiling -->
{% if img_cpu_timeline or img_memory_timeline %}
<h2>Resource Profiling</h2>
<div class="card">
<div class="plot-grid">
  {% if img_cpu_timeline %}<img src="{{ img_cpu_timeline }}" alt="CPU Timeline">{% endif %}
  {% if img_memory_timeline %}<img src="{{ img_memory_timeline }}" alt="Memory Timeline">{% endif %}
</div>
</div>
{% endif %}

<!-- Comparison -->
{% if comparison %}
<h2>Comparison with Previous Run</h2>
<div class="card">
<table>
  <tr><th>Metric</th><th>Previous</th><th>Current</th><th>Change</th></tr>
  {% for d in comparison %}
  <tr>
    <td>{{ d.metric }}</td>
    <td class="num">{{ fmt_rate(d.previous) }}</td>
    <td class="num">{{ fmt_rate(d.current) }}</td>
    <td class="num {{ 'delta-positive' if d.improved else 'delta-negative' }}">
      {{ '+' if d.change > 0 else '' }}{{ fmt_rate(d.change) }} ({{ d.change_pct }}%)
    </td>
  </tr>
  {% endfor %}
</table>
</div>
{% endif %}

<!-- Metadata -->
<h2>Run Metadata</h2>
<div class="card">
<dl class="meta-grid">
  <dt>Timestamp</dt><dd>{{ timestamp }}</dd>
  <dt>Git SHA</dt><dd><code>{{ git_sha }}</code></dd>
  <dt>Dataset</dt><dd>{{ dataset_path }}</dd>
  <dt>API URL</dt><dd>{{ api_url }}</dd>
  <dt>API Version</dt><dd>{{ api_version }}</dd>
  <dt>SMPC Active</dt><dd>{{ smpc_active }}</dd>
  <dt>Enrolled Subjects</dt><dd>{{ enrolled_subjects }}</dd>
  <dt>Impostor Subjects</dt><dd>{{ impostor_subjects }}</dd>
  <dt>Gallery Before</dt><dd>{{ gallery_size_before }}</dd>
  <dt>Python Version</dt><dd>{{ python_version }}</dd>
</dl>
</div>

<p style="text-align:center; color:var(--muted); margin-top:2rem; font-size:0.8rem;">
  Generated {{ generated_at }} by EyeD V&amp;V report.py
</p>

</div>
</body>
</html>"""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="EyeD V&V HTML Report Generator")
    parser.add_argument("--input", required=True,
                        help="Path to benchmark run directory (e.g. reports/vnv/latest)")
    args = parser.parse_args()

    run_dir = Path(args.input).resolve()
    if run_dir.is_symlink():
        run_dir = run_dir.resolve()

    print(f"Generating report for: {run_dir}")

    # Load data
    summary_path = run_dir / "summary.json"
    metadata_path = run_dir / "metadata.json"

    if not summary_path.exists():
        print(f"ERROR: summary.json not found in {run_dir}", file=sys.stderr)
        print("Run analyze.py first.", file=sys.stderr)
        sys.exit(1)

    with open(summary_path) as f:
        summary = json.load(f)
    metadata = {}
    if metadata_path.exists():
        with open(metadata_path) as f:
            metadata = json.load(f)

    plots_dir = run_dir / "plots"

    # Build template context
    ctx = {
        # Metadata
        "timestamp": metadata.get("timestamp", summary.get("timestamp", "unknown")),
        "git_sha": metadata.get("git_sha", "unknown")[:12],
        "dataset_path": metadata.get("dataset_path", ""),
        "api_url": metadata.get("api_url", ""),
        "api_version": metadata.get("api_version", "unknown"),
        "smpc_active": metadata.get("smpc_active", False),
        "enrolled_subjects": metadata.get("enrolled_subjects", "000-799"),
        "impostor_subjects": metadata.get("impostor_subjects", "800-999"),
        "gallery_size_before": metadata.get("gallery_size_before", 0),
        "python_version": metadata.get("python_version", ""),
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),

        # Metrics
        "enrollment": summary.get("enrollment_metrics", {}),
        "genuine": summary.get("genuine_metrics", {}),
        "impostor": summary.get("impostor_metrics", {}),
        "operational_threshold": summary.get("operational_threshold", 0.39),
        "op_fmr": summary.get("metrics_at_operational_threshold", {}).get("fmr"),
        "op_fnmr": summary.get("metrics_at_operational_threshold", {}).get("fnmr"),
        "eer": summary.get("eer"),
        "eer_threshold": summary.get("eer_threshold"),
        "optimal_threshold": summary.get("optimal_threshold"),
        "decidability": summary.get("decidability"),

        # Gates
        "gates": summary.get("gates", {}),
        "all_gates_pass": summary.get("all_gates_pass", False),

        # Comparison
        "comparison": summary.get("comparison"),

        # Plots as base64 data URIs
        "img_hd_histogram": img_to_base64(plots_dir / "hd_histogram.png"),
        "img_det_curve": img_to_base64(plots_dir / "det_curve.png"),
        "img_roc_curve": img_to_base64(plots_dir / "roc_curve.png"),
        "img_subject_heatmap": img_to_base64(plots_dir / "subject_accuracy_heatmap.png"),
        "img_enrollment_latency": img_to_base64(plots_dir / "enrollment_latency.png"),
        "img_verification_latency": img_to_base64(plots_dir / "verification_latency.png"),
        "img_cpu_timeline": img_to_base64(plots_dir / "cpu_timeline.png"),
        "img_memory_timeline": img_to_base64(plots_dir / "memory_timeline.png"),

        # Helper functions
        "fmt_rate": fmt_rate,
        "fmt_ms": fmt_ms,
        "fmt_pct": fmt_pct,
        "gate_badge": gate_badge,
    }

    # Render
    env = Environment(loader=BaseLoader(), autoescape=False)
    template = env.from_string(HTML_TEMPLATE)
    html = template.render(**ctx)

    out_path = run_dir / "report.html"
    with open(out_path, "w") as f:
        f.write(html)

    print(f"Report written to: {out_path}")
    print(f"Open with: open {out_path}")


if __name__ == "__main__":
    main()
