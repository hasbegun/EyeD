#!/usr/bin/env python3
"""
EyeD V&V Analyzer

Reads CSV outputs from benchmark.py and computes:
- FMR, FNMR, EER, FTE, FTA, Wrong ID Rate, d' (decidability)
- Threshold sweep with DET/ROC curves
- HD histograms (genuine vs impostor)
- Latency statistics
- Per-subject accuracy heatmap
- Optional comparison against a previous run

Usage:
    python scripts/vnv/analyze.py --input reports/vnv/latest
    python scripts/vnv/analyze.py --input reports/vnv/latest --compare reports/vnv/2026-04-25T14-00-00
"""

import argparse
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# Data Loading
# ---------------------------------------------------------------------------

def load_run(run_dir: Path) -> dict:
    """Load all CSVs and metadata from a benchmark run directory."""
    data = {}

    enrollment_path = run_dir / "enrollment.csv"
    genuine_path = run_dir / "genuine.csv"
    impostor_path = run_dir / "impostor.csv"

    if not enrollment_path.exists():
        raise FileNotFoundError(f"enrollment.csv not found in {run_dir}")
    if not genuine_path.exists():
        raise FileNotFoundError(f"genuine.csv not found in {run_dir}")
    if not impostor_path.exists():
        raise FileNotFoundError(f"impostor.csv not found in {run_dir}")

    data["enrollment"] = pd.read_csv(enrollment_path)
    data["genuine"] = pd.read_csv(genuine_path)
    data["impostor"] = pd.read_csv(impostor_path)

    meta_path = run_dir / "metadata.json"
    if meta_path.exists():
        with open(meta_path) as f:
            data["metadata"] = json.load(f)
    else:
        data["metadata"] = {}

    summary_path = run_dir / "summary.json"
    if summary_path.exists():
        with open(summary_path) as f:
            data["summary"] = json.load(f)
    else:
        data["summary"] = {}

    profile_path = run_dir / "profile.csv"
    if profile_path.exists():
        data["profile"] = pd.read_csv(profile_path)
    else:
        data["profile"] = None

    return data


# ---------------------------------------------------------------------------
# Metric Computation
# ---------------------------------------------------------------------------

def compute_enrollment_metrics(df: pd.DataFrame) -> dict:
    """Compute enrollment metrics from enrollment.csv."""
    total = len(df)
    success = len(df[(df["error"] == "") | df["error"].isna()])
    success = len(df[df["template_id"].notna() & (df["template_id"] != "")])
    duplicates = len(df[df["is_duplicate"] == True])
    failed = total - success - duplicates

    latencies = pd.to_numeric(df["latency_ms"], errors="coerce").dropna()

    return {
        "total": int(total),
        "success": int(success),
        "duplicates": int(duplicates),
        "failed": int(failed),
        "fte_rate": failed / total if total > 0 else 0,
        "latency_min_ms": float(latencies.min()) if len(latencies) > 0 else 0,
        "latency_max_ms": float(latencies.max()) if len(latencies) > 0 else 0,
        "latency_mean_ms": float(latencies.mean()) if len(latencies) > 0 else 0,
        "latency_median_ms": float(latencies.median()) if len(latencies) > 0 else 0,
        "latency_p95_ms": float(latencies.quantile(0.95)) if len(latencies) > 0 else 0,
        "latency_p99_ms": float(latencies.quantile(0.99)) if len(latencies) > 0 else 0,
        "latency_std_ms": float(latencies.std()) if len(latencies) > 0 else 0,
    }


def compute_genuine_metrics(df: pd.DataFrame) -> dict:
    """Compute genuine verification metrics."""
    total = len(df)
    pipeline_fail = len(df[df["error"].notna() & (df["error"] != "")])
    valid = df[(df["error"].isna()) | (df["error"] == "")]
    valid_count = len(valid)

    correct = len(valid[valid["correct"] == True])
    false_negative = len(valid[(valid["is_match"] == False)])
    wrong_identity = len(valid[(valid["is_match"] == True) & (valid["correct"] == False)])

    latencies = pd.to_numeric(valid["client_latency_ms"], errors="coerce").dropna()
    server_latencies = pd.to_numeric(valid["server_latency_ms"], errors="coerce").dropna()

    hd_values = pd.to_numeric(valid["hamming_distance"], errors="coerce").dropna()

    return {
        "total": int(total),
        "valid": int(valid_count),
        "pipeline_fail": int(pipeline_fail),
        "correct": int(correct),
        "false_negative": int(false_negative),
        "wrong_identity": int(wrong_identity),
        "fnmr": false_negative / valid_count if valid_count > 0 else 0,
        "wrong_id_rate": wrong_identity / valid_count if valid_count > 0 else 0,
        "fta_rate": pipeline_fail / total if total > 0 else 0,
        "hd_mean": float(hd_values.mean()) if len(hd_values) > 0 else 0,
        "hd_std": float(hd_values.std()) if len(hd_values) > 0 else 0,
        "hd_min": float(hd_values.min()) if len(hd_values) > 0 else 0,
        "hd_max": float(hd_values.max()) if len(hd_values) > 0 else 0,
        "client_latency_min_ms": float(latencies.min()) if len(latencies) > 0 else 0,
        "client_latency_max_ms": float(latencies.max()) if len(latencies) > 0 else 0,
        "client_latency_mean_ms": float(latencies.mean()) if len(latencies) > 0 else 0,
        "client_latency_median_ms": float(latencies.median()) if len(latencies) > 0 else 0,
        "client_latency_p95_ms": float(latencies.quantile(0.95)) if len(latencies) > 0 else 0,
        "client_latency_p99_ms": float(latencies.quantile(0.99)) if len(latencies) > 0 else 0,
        "server_latency_mean_ms": float(server_latencies.mean()) if len(server_latencies) > 0 else 0,
        "server_latency_p99_ms": float(server_latencies.quantile(0.99)) if len(server_latencies) > 0 else 0,
    }


def compute_impostor_metrics(df: pd.DataFrame) -> dict:
    """Compute impostor verification metrics."""
    total = len(df)
    pipeline_fail = len(df[df["error"].notna() & (df["error"] != "")])
    valid = df[(df["error"].isna()) | (df["error"] == "")]
    valid_count = len(valid)

    true_reject = len(valid[valid["is_match"] == False])
    false_positive = len(valid[valid["is_match"] == True])

    latencies = pd.to_numeric(valid["client_latency_ms"], errors="coerce").dropna()
    server_latencies = pd.to_numeric(valid["server_latency_ms"], errors="coerce").dropna()

    hd_values = pd.to_numeric(valid["hamming_distance"], errors="coerce").dropna()

    return {
        "total": int(total),
        "valid": int(valid_count),
        "pipeline_fail": int(pipeline_fail),
        "true_reject": int(true_reject),
        "false_positive": int(false_positive),
        "fmr": false_positive / valid_count if valid_count > 0 else 0,
        "fta_rate": pipeline_fail / total if total > 0 else 0,
        "hd_mean": float(hd_values.mean()) if len(hd_values) > 0 else 0,
        "hd_std": float(hd_values.std()) if len(hd_values) > 0 else 0,
        "hd_min": float(hd_values.min()) if len(hd_values) > 0 else 0,
        "hd_max": float(hd_values.max()) if len(hd_values) > 0 else 0,
        "client_latency_mean_ms": float(latencies.mean()) if len(latencies) > 0 else 0,
        "client_latency_p99_ms": float(latencies.quantile(0.99)) if len(latencies) > 0 else 0,
        "server_latency_mean_ms": float(server_latencies.mean()) if len(server_latencies) > 0 else 0,
        "server_latency_p99_ms": float(server_latencies.quantile(0.99)) if len(server_latencies) > 0 else 0,
    }


def compute_decidability(genuine_hd: np.ndarray, impostor_hd: np.ndarray) -> float:
    """Compute decidability index d'."""
    if len(genuine_hd) == 0 or len(impostor_hd) == 0:
        return 0.0
    mu_g = genuine_hd.mean()
    mu_i = impostor_hd.mean()
    var_g = genuine_hd.var()
    var_i = impostor_hd.var()
    denom = np.sqrt(0.5 * (var_g + var_i))
    if denom == 0:
        return 0.0
    return float(abs(mu_g - mu_i) / denom)


def threshold_sweep(genuine_hd: np.ndarray, impostor_hd: np.ndarray,
                    thresholds: np.ndarray) -> dict:
    """
    Sweep HD thresholds and compute FMR / FNMR at each.
    A probe is a 'match' if HD <= threshold.
    Returns dict with arrays for threshold, fmr, fnmr.
    """
    fmr_arr = []
    fnmr_arr = []

    for t in thresholds:
        # FMR: fraction of impostor probes where HD <= threshold (false match)
        fmr = np.sum(impostor_hd <= t) / len(impostor_hd) if len(impostor_hd) > 0 else 0
        # FNMR: fraction of genuine probes where HD > threshold (false non-match)
        fnmr = np.sum(genuine_hd > t) / len(genuine_hd) if len(genuine_hd) > 0 else 0
        fmr_arr.append(fmr)
        fnmr_arr.append(fnmr)

    fmr_arr = np.array(fmr_arr)
    fnmr_arr = np.array(fnmr_arr)

    # Find EER: threshold where |FMR - FNMR| is minimized
    diff = np.abs(fmr_arr - fnmr_arr)
    eer_idx = np.argmin(diff)
    eer = float((fmr_arr[eer_idx] + fnmr_arr[eer_idx]) / 2)
    eer_threshold = float(thresholds[eer_idx])

    # Find optimal threshold (minimizes FMR + FNMR)
    total_error = fmr_arr + fnmr_arr
    optimal_idx = np.argmin(total_error)
    optimal_threshold = float(thresholds[optimal_idx])

    return {
        "thresholds": thresholds,
        "fmr": fmr_arr,
        "fnmr": fnmr_arr,
        "eer": eer,
        "eer_threshold": eer_threshold,
        "optimal_threshold": optimal_threshold,
        "optimal_fmr": float(fmr_arr[optimal_idx]),
        "optimal_fnmr": float(fnmr_arr[optimal_idx]),
    }


def metrics_at_threshold(genuine_hd: np.ndarray, impostor_hd: np.ndarray,
                         threshold: float) -> dict:
    """Compute FMR and FNMR at a specific threshold."""
    fmr = float(np.sum(impostor_hd <= threshold) / len(impostor_hd)) if len(impostor_hd) > 0 else 0
    fnmr = float(np.sum(genuine_hd > threshold) / len(genuine_hd)) if len(genuine_hd) > 0 else 0
    return {"threshold": threshold, "fmr": fmr, "fnmr": fnmr}


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------

def plot_hd_histogram(genuine_hd: np.ndarray, impostor_hd: np.ndarray,
                      operational_threshold: float, out_path: Path):
    """Overlaid genuine vs impostor HD histograms."""
    fig, ax = plt.subplots(figsize=(10, 6))

    bins = np.linspace(0, 0.55, 110)

    if len(genuine_hd) > 0:
        ax.hist(genuine_hd, bins=bins, alpha=0.6, color="green",
                label=f"Genuine (n={len(genuine_hd)}, μ={genuine_hd.mean():.4f})", density=True)
    if len(impostor_hd) > 0:
        ax.hist(impostor_hd, bins=bins, alpha=0.6, color="red",
                label=f"Impostor (n={len(impostor_hd)}, μ={impostor_hd.mean():.4f})", density=True)

    ax.axvline(operational_threshold, color="black", linestyle="--", linewidth=1.5,
               label=f"Threshold = {operational_threshold}")
    ax.set_xlabel("Hamming Distance")
    ax.set_ylabel("Density")
    ax.set_title("Genuine vs Impostor Hamming Distance Distributions")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_det_curve(thresholds: np.ndarray, fmr: np.ndarray, fnmr: np.ndarray,
                   eer: float, out_path: Path):
    """DET curve: FNMR vs FMR on log-log scale."""
    fig, ax = plt.subplots(figsize=(8, 8))

    # Avoid log(0)
    fmr_plot = np.clip(fmr, 1e-6, 1.0)
    fnmr_plot = np.clip(fnmr, 1e-6, 1.0)

    ax.loglog(fmr_plot, fnmr_plot, "b-", linewidth=1.5)
    ax.plot([1e-6, 1.0], [1e-6, 1.0], "k--", alpha=0.3, label="EER line")
    ax.plot(eer, eer, "ro", markersize=8, label=f"EER = {eer:.4f}")

    ax.set_xlabel("False Match Rate (FMR)")
    ax.set_ylabel("False Non-Match Rate (FNMR)")
    ax.set_title("Detection Error Tradeoff (DET) Curve")
    ax.legend()
    ax.grid(True, alpha=0.3, which="both")
    ax.set_xlim(1e-4, 1.0)
    ax.set_ylim(1e-4, 1.0)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_roc_curve(thresholds: np.ndarray, fmr: np.ndarray, fnmr: np.ndarray,
                   out_path: Path):
    """ROC curve: (1-FNMR) vs FMR."""
    fig, ax = plt.subplots(figsize=(8, 8))
    tpr = 1.0 - fnmr

    ax.semilogx(np.clip(fmr, 1e-6, 1.0), tpr, "b-", linewidth=1.5)

    ax.set_xlabel("False Match Rate (FMR)")
    ax.set_ylabel("True Match Rate (1 - FNMR)")
    ax.set_title("Receiver Operating Characteristic (ROC) Curve")
    ax.grid(True, alpha=0.3, which="both")
    ax.set_xlim(1e-4, 1.0)
    ax.set_ylim(0.0, 1.05)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_subject_accuracy_heatmap(genuine_df: pd.DataFrame, out_path: Path):
    """Heatmap showing per-subject FNMR."""
    valid = genuine_df[(genuine_df["error"].isna()) | (genuine_df["error"] == "")]
    if len(valid) == 0:
        return

    subject_stats = valid.groupby("subject_id").agg(
        total=("correct", "count"),
        correct=("correct", "sum"),
    ).reset_index()
    subject_stats["fnmr"] = 1.0 - (subject_stats["correct"] / subject_stats["total"])
    subject_stats = subject_stats.sort_values("subject_id")

    # Reshape into a grid
    n_subjects = len(subject_stats)
    cols = 40
    rows = (n_subjects + cols - 1) // cols

    grid = np.full((rows, cols), np.nan)
    labels = np.full((rows, cols), "", dtype=object)
    for i, (_, row) in enumerate(subject_stats.iterrows()):
        r, c = divmod(i, cols)
        grid[r, c] = row["fnmr"]
        labels[r, c] = row["subject_id"]

    fig, ax = plt.subplots(figsize=(20, max(4, rows * 0.5)))
    cmap = plt.cm.RdYlGn_r
    im = ax.imshow(grid, cmap=cmap, vmin=0, vmax=1, aspect="auto")

    ax.set_title("Per-Subject False Non-Match Rate (FNMR)\n(0=perfect, 1=all failed)")
    ax.set_xticks([])
    ax.set_yticks([])
    plt.colorbar(im, ax=ax, label="FNMR", shrink=0.6)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_latency_histogram(latencies: np.ndarray, title: str, out_path: Path):
    """Histogram of latency values."""
    if len(latencies) == 0:
        return
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.hist(latencies, bins=50, color="steelblue", alpha=0.7, edgecolor="white")
    ax.axvline(np.median(latencies), color="orange", linestyle="--",
               label=f"Median: {np.median(latencies):.0f} ms")
    ax.axvline(np.percentile(latencies, 99), color="red", linestyle="--",
               label=f"P99: {np.percentile(latencies, 99):.0f} ms")
    ax.set_xlabel("Latency (ms)")
    ax.set_ylabel("Count")
    ax.set_title(title)
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_profile_timelines(profile_df: pd.DataFrame, plots_dir: Path):
    """Plot CPU and memory timelines from profile.csv."""
    if profile_df is None or len(profile_df) == 0:
        return

    if "timestamp" in profile_df.columns:
        x = range(len(profile_df))
    else:
        x = range(len(profile_df))

    # CPU timeline
    if "cpu_percent" in profile_df.columns:
        fig, ax = plt.subplots(figsize=(12, 4))
        ax.plot(x, profile_df["cpu_percent"], "b-", linewidth=0.8)
        ax.set_xlabel("Time (seconds)")
        ax.set_ylabel("CPU %")
        ax.set_title("iris-engine2 Container CPU Usage During Benchmark")
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        fig.savefig(plots_dir / "cpu_timeline.png", dpi=150)
        plt.close(fig)

    # Memory timeline
    if "mem_usage_mb" in profile_df.columns:
        fig, ax = plt.subplots(figsize=(12, 4))
        ax.plot(x, profile_df["mem_usage_mb"], "r-", linewidth=0.8)
        ax.set_xlabel("Time (seconds)")
        ax.set_ylabel("Memory (MB)")
        ax.set_title("iris-engine2 Container Memory Usage During Benchmark")
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        fig.savefig(plots_dir / "memory_timeline.png", dpi=150)
        plt.close(fig)


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

def compare_runs(current: dict, previous: dict) -> list[dict]:
    """Compare two summary.json metrics. Returns list of delta rows."""
    deltas = []

    def add_delta(name, cur_val, prev_val, unit="", lower_is_better=True):
        if cur_val is None or prev_val is None:
            return
        change = cur_val - prev_val
        pct = (change / prev_val * 100) if prev_val != 0 else 0
        improved = (change < 0) if lower_is_better else (change > 0)
        deltas.append({
            "metric": name,
            "previous": prev_val,
            "current": cur_val,
            "change": change,
            "change_pct": round(pct, 2),
            "improved": improved,
            "unit": unit,
        })

    # Key accuracy metrics
    cur_g = current.get("genuine_metrics", {})
    prev_g = previous.get("genuine_metrics", {})
    cur_i = current.get("impostor_metrics", {})
    prev_i = previous.get("impostor_metrics", {})
    cur_e = current.get("enrollment_metrics", {})
    prev_e = previous.get("enrollment_metrics", {})

    add_delta("FMR", cur_i.get("fmr"), prev_i.get("fmr"))
    add_delta("FNMR", cur_g.get("fnmr"), prev_g.get("fnmr"))
    add_delta("EER", current.get("eer"), previous.get("eer"))
    add_delta("FTE Rate", cur_e.get("fte_rate"), prev_e.get("fte_rate"))
    add_delta("Wrong ID Rate", cur_g.get("wrong_id_rate"), prev_g.get("wrong_id_rate"))
    add_delta("d'", current.get("decidability"), previous.get("decidability"),
              lower_is_better=False)
    add_delta("Enroll P99 (ms)", cur_e.get("latency_p99_ms"), prev_e.get("latency_p99_ms"), "ms")
    add_delta("Verify P99 (ms)", cur_g.get("client_latency_p99_ms"),
              prev_g.get("client_latency_p99_ms"), "ms")

    return deltas


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="EyeD V&V Analyzer")
    parser.add_argument("--input", required=True,
                        help="Path to benchmark run directory (e.g. reports/vnv/latest)")
    parser.add_argument("--compare", default=None,
                        help="Path to previous run directory for comparison")
    parser.add_argument("--threshold", type=float, default=0.39,
                        help="Operational HD threshold (default: 0.39)")
    args = parser.parse_args()

    run_dir = Path(args.input).resolve()
    if run_dir.is_symlink():
        run_dir = run_dir.resolve()

    print(f"Analyzing run: {run_dir}")

    # ── Load data ────────────────────────────────────────────────────────
    data = load_run(run_dir)
    plots_dir = run_dir / "plots"
    plots_dir.mkdir(exist_ok=True)

    # ── Compute metrics ──────────────────────────────────────────────────
    print("Computing enrollment metrics...")
    enrollment_metrics = compute_enrollment_metrics(data["enrollment"])

    print("Computing genuine verification metrics...")
    genuine_metrics = compute_genuine_metrics(data["genuine"])

    print("Computing impostor verification metrics...")
    impostor_metrics = compute_impostor_metrics(data["impostor"])

    # ── Extract HD arrays for threshold analysis ─────────────────────────
    genuine_valid = data["genuine"][(data["genuine"]["error"].isna()) | (data["genuine"]["error"] == "")]
    impostor_valid = data["impostor"][(data["impostor"]["error"].isna()) | (data["impostor"]["error"] == "")]

    genuine_hd = pd.to_numeric(genuine_valid["hamming_distance"], errors="coerce").dropna().values
    impostor_hd = pd.to_numeric(impostor_valid["hamming_distance"], errors="coerce").dropna().values

    print(f"  Genuine HD samples: {len(genuine_hd)}")
    print(f"  Impostor HD samples: {len(impostor_hd)}")

    # ── Decidability ─────────────────────────────────────────────────────
    decidability = compute_decidability(genuine_hd, impostor_hd)
    print(f"  Decidability (d'): {decidability:.4f}")

    # ── Threshold sweep ──────────────────────────────────────────────────
    print("Running threshold sweep (0.0 to 0.5, step 0.005)...")
    thresholds = np.arange(0.0, 0.505, 0.005)
    sweep = threshold_sweep(genuine_hd, impostor_hd, thresholds)
    print(f"  EER: {sweep['eer']:.6f} at threshold {sweep['eer_threshold']:.3f}")
    print(f"  Optimal threshold: {sweep['optimal_threshold']:.3f} "
          f"(FMR={sweep['optimal_fmr']:.6f}, FNMR={sweep['optimal_fnmr']:.6f})")

    # ── Metrics at operational threshold ─────────────────────────────────
    op_metrics = metrics_at_threshold(genuine_hd, impostor_hd, args.threshold)
    print(f"  At operational threshold {args.threshold}:")
    print(f"    FMR = {op_metrics['fmr']:.6f}")
    print(f"    FNMR = {op_metrics['fnmr']:.6f}")

    # ── Generate plots ───────────────────────────────────────────────────
    print("Generating plots...")

    plot_hd_histogram(genuine_hd, impostor_hd, args.threshold,
                      plots_dir / "hd_histogram.png")
    print("  ✓ hd_histogram.png")

    if len(genuine_hd) > 0 and len(impostor_hd) > 0:
        plot_det_curve(sweep["thresholds"], sweep["fmr"], sweep["fnmr"],
                       sweep["eer"], plots_dir / "det_curve.png")
        print("  ✓ det_curve.png")

        plot_roc_curve(sweep["thresholds"], sweep["fmr"], sweep["fnmr"],
                       plots_dir / "roc_curve.png")
        print("  ✓ roc_curve.png")

    plot_subject_accuracy_heatmap(data["genuine"], plots_dir / "subject_accuracy_heatmap.png")
    print("  ✓ subject_accuracy_heatmap.png")

    # Latency histograms
    enroll_latencies = pd.to_numeric(data["enrollment"]["latency_ms"], errors="coerce").dropna().values
    verify_latencies = pd.to_numeric(genuine_valid["client_latency_ms"], errors="coerce").dropna().values

    plot_latency_histogram(enroll_latencies, "Enrollment Latency Distribution",
                           plots_dir / "enrollment_latency.png")
    print("  ✓ enrollment_latency.png")

    plot_latency_histogram(verify_latencies, "Verification Latency Distribution",
                           plots_dir / "verification_latency.png")
    print("  ✓ verification_latency.png")

    # Profile timelines
    if data["profile"] is not None:
        plot_profile_timelines(data["profile"], plots_dir)
        print("  ✓ cpu_timeline.png, memory_timeline.png")

    # ── Gate evaluation ──────────────────────────────────────────────────
    gates = {
        "fmr_zero": {
            "description": "FMR = 0% for unenrolled subjects at threshold 0.39",
            "passed": op_metrics["fmr"] == 0.0,
            "value": op_metrics["fmr"],
        },
        "fnmr_below_10pct": {
            "description": "FNMR < 10% at operational threshold",
            "passed": op_metrics["fnmr"] < 0.10,
            "value": op_metrics["fnmr"],
        },
        "fte_below_1pct": {
            "description": "FTE < 1%",
            "passed": enrollment_metrics["fte_rate"] < 0.01,
            "value": enrollment_metrics["fte_rate"],
        },
    }

    all_gates_pass = all(g["passed"] for g in gates.values())

    print("\n" + "=" * 60)
    print("GATE EVALUATION")
    print("=" * 60)
    for name, gate in gates.items():
        status = "PASS" if gate["passed"] else "FAIL"
        print(f"  [{status}] {gate['description']} (actual: {gate['value']:.6f})")

    print(f"\n  Overall: {'ALL GATES PASS' if all_gates_pass else 'SOME GATES FAILED'}")

    # ── Comparison ───────────────────────────────────────────────────────
    comparison = None
    if args.compare:
        prev_dir = Path(args.compare).resolve()
        prev_summary_path = prev_dir / "summary.json"
        if prev_summary_path.exists():
            print(f"\nComparing with previous run: {prev_dir.name}")
            with open(prev_summary_path) as f:
                prev_summary = json.load(f)
            # Build comparable dict from previous
            prev_data = load_run(prev_dir)
            prev_analysis = {
                "enrollment_metrics": compute_enrollment_metrics(prev_data["enrollment"]),
                "genuine_metrics": compute_genuine_metrics(prev_data["genuine"]),
                "impostor_metrics": compute_impostor_metrics(prev_data["impostor"]),
            }
            prev_genuine_hd = pd.to_numeric(
                prev_data["genuine"]["hamming_distance"], errors="coerce"
            ).dropna().values
            prev_impostor_hd = pd.to_numeric(
                prev_data["impostor"]["hamming_distance"], errors="coerce"
            ).dropna().values
            prev_sweep = threshold_sweep(prev_genuine_hd, prev_impostor_hd, thresholds)
            prev_analysis["eer"] = prev_sweep["eer"]
            prev_analysis["decidability"] = compute_decidability(prev_genuine_hd, prev_impostor_hd)

            current_analysis = {
                "enrollment_metrics": enrollment_metrics,
                "genuine_metrics": genuine_metrics,
                "impostor_metrics": impostor_metrics,
                "eer": sweep["eer"],
                "decidability": decidability,
            }

            comparison = compare_runs(current_analysis, prev_analysis)
            print(f"  {'Metric':<25} {'Previous':>12} {'Current':>12} {'Change':>12}")
            print(f"  {'-'*25} {'-'*12} {'-'*12} {'-'*12}")
            for d in comparison:
                arrow = "↑" if d["change"] > 0 else "↓" if d["change"] < 0 else "="
                print(f"  {d['metric']:<25} {d['previous']:>12.6f} {d['current']:>12.6f} "
                      f"{arrow} {d['change']:>+.6f}")
        else:
            print(f"\nWARNING: Previous run summary not found at {prev_summary_path}")

    # ── Save analysis to summary.json ────────────────────────────────────
    analysis_summary = {
        "timestamp": data["metadata"].get("timestamp", ""),
        "operational_threshold": args.threshold,
        "enrollment_metrics": enrollment_metrics,
        "genuine_metrics": genuine_metrics,
        "impostor_metrics": impostor_metrics,
        "decidability": decidability,
        "eer": sweep["eer"],
        "eer_threshold": sweep["eer_threshold"],
        "optimal_threshold": sweep["optimal_threshold"],
        "metrics_at_operational_threshold": op_metrics,
        "gates": {k: {"passed": v["passed"], "value": v["value"], "description": v["description"]}
                  for k, v in gates.items()},
        "all_gates_pass": all_gates_pass,
    }
    if comparison:
        analysis_summary["comparison"] = comparison

    with open(run_dir / "summary.json", "w") as f:
        json.dump(analysis_summary, f, indent=2)
    print(f"\nSummary written to {run_dir / 'summary.json'}")

    # ── Next step ────────────────────────────────────────────────────────
    print(f"\nNext step: python scripts/vnv/report.py --input {run_dir}")

    return 0 if all_gates_pass else 1


if __name__ == "__main__":
    sys.exit(main())
