#!/usr/bin/env python3
"""
EyeD V&V Benchmark Runner

Enrollment + Genuine Verification + Impostor Verification against the live HTTP API.
Produces timestamped CSV files in reports/vnv/<timestamp>/.

Usage:
    python scripts/vnv/benchmark.py \
        --dataset /path/to/CASIA-Iris-Thousand \
        --api http://localhost:9510 \
        --output reports/vnv/

No source code changes. Results are recorded exactly as returned by the API.
"""

import argparse
import base64
import csv
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import requests
from tqdm import tqdm

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ENROLL_SUBJECTS = range(0, 800)      # 000–799 enrolled (80%)
IMPOSTOR_SUBJECTS = range(800, 1000) # 800–999 never enrolled (20%)
EYE_SIDES = {"L": "left", "R": "right"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def subject_dir_name(subject_idx: int) -> str:
    """Convert subject index to 3-digit directory name: 0 -> '000', 42 -> '042'."""
    return f"{subject_idx:03d}"


def load_jpeg_b64(path: Path) -> str:
    """Read a JPEG file and return its base64-encoded string."""
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def sorted_images(directory: Path) -> list[Path]:
    """Return sorted list of .jpg files in a directory."""
    if not directory.is_dir():
        return []
    return sorted(directory.glob("*.jpg"))


def get_git_sha() -> str:
    """Get current git commit SHA, or 'unknown'."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip() if result.returncode == 0 else "unknown"
    except Exception:
        return "unknown"


def check_api_ready(api_url: str) -> dict:
    """Check if the API is ready. Returns the health response or raises."""
    resp = requests.get(f"{api_url}/health/ready", timeout=10)
    resp.raise_for_status()
    data = resp.json()
    if not data.get("ready"):
        raise RuntimeError(f"API not ready: {data}")
    return data


def get_gallery_size(api_url: str) -> int:
    """Get current gallery size."""
    resp = requests.get(f"{api_url}/gallery/size", timeout=10)
    resp.raise_for_status()
    return resp.json().get("gallery_size", 0)


# ---------------------------------------------------------------------------
# Enrollment
# ---------------------------------------------------------------------------

def run_enrollment(dataset: Path, api_url: str, writer: csv.DictWriter,
                   progress: bool = True) -> dict:
    """
    Enroll first image per eye for subjects 000–799.
    Returns summary stats dict.
    """
    subjects = [subject_dir_name(i) for i in ENROLL_SUBJECTS]
    total = 0
    success = 0
    duplicate = 0
    failed = 0
    errors = []

    items = []
    for subj in subjects:
        for eye_code, eye_side in EYE_SIDES.items():
            eye_dir = dataset / subj / eye_code
            images = sorted_images(eye_dir)
            if not images:
                errors.append({"subject": subj, "eye": eye_side, "error": "no images found"})
                continue
            items.append((subj, eye_code, eye_side, images[0]))

    desc = "Enrolling"
    iterator = tqdm(items, desc=desc, disable=not progress)

    for subj, eye_code, eye_side, img_path in iterator:
        total += 1
        t0 = time.monotonic()
        try:
            jpeg_b64 = load_jpeg_b64(img_path)
            resp = requests.post(
                f"{api_url}/enroll",
                json={
                    "identity_id": subj,
                    "identity_name": subj,
                    "eye_side": eye_side,
                    "jpeg_b64": jpeg_b64,
                    "device_id": "vnv-benchmark",
                },
                timeout=60,
            )
            latency_ms = (time.monotonic() - t0) * 1000
            status_code = resp.status_code
            body = resp.json()

            is_dup = body.get("is_duplicate", False)
            error = body.get("error")
            template_id = body.get("template_id", "")
            smpc_protected = body.get("smpc_protected", False)

            if error:
                failed += 1
            elif is_dup:
                duplicate += 1
            else:
                success += 1

            writer.writerow({
                "subject_id": subj,
                "eye_side": eye_side,
                "image_file": img_path.name,
                "http_status": status_code,
                "template_id": template_id,
                "is_duplicate": is_dup,
                "smpc_protected": smpc_protected,
                "error": error if error else "",
                "latency_ms": f"{latency_ms:.2f}",
            })

        except Exception as e:
            latency_ms = (time.monotonic() - t0) * 1000
            failed += 1
            writer.writerow({
                "subject_id": subj,
                "eye_side": eye_side,
                "image_file": img_path.name,
                "http_status": 0,
                "template_id": "",
                "is_duplicate": False,
                "smpc_protected": False,
                "error": str(e),
                "latency_ms": f"{latency_ms:.2f}",
            })

        iterator.set_postfix(ok=success, dup=duplicate, fail=failed)

    return {
        "total": total,
        "success": success,
        "duplicate": duplicate,
        "failed": failed,
        "fte_rate": failed / total if total > 0 else 0,
    }


# ---------------------------------------------------------------------------
# Genuine Verification (positive tests)
# ---------------------------------------------------------------------------

def run_genuine_verification(dataset: Path, api_url: str, writer: csv.DictWriter,
                             progress: bool = True) -> dict:
    """
    Send remaining images from enrolled subjects (000–799) as genuine probes.
    The system should match them to their own identity.
    """
    subjects = [subject_dir_name(i) for i in ENROLL_SUBJECTS]
    total = 0
    correct = 0
    false_negative = 0
    wrong_identity = 0
    pipeline_fail = 0

    items = []
    for subj in subjects:
        for eye_code, eye_side in EYE_SIDES.items():
            eye_dir = dataset / subj / eye_code
            images = sorted_images(eye_dir)
            # Skip first image (used for enrollment), use rest as probes
            for img_path in images[1:]:
                items.append((subj, eye_code, eye_side, img_path))

    desc = "Genuine probes"
    iterator = tqdm(items, desc=desc, disable=not progress)

    for subj, eye_code, eye_side, img_path in iterator:
        total += 1
        t0 = time.monotonic()
        try:
            jpeg_b64 = load_jpeg_b64(img_path)
            resp = requests.post(
                f"{api_url}/analyze/json",
                json={
                    "jpeg_b64": jpeg_b64,
                    "eye_side": eye_side,
                    "frame_id": f"{subj}_{eye_code}_{img_path.stem}",
                    "device_id": "vnv-benchmark",
                },
                timeout=60,
            )
            latency_ms = (time.monotonic() - t0) * 1000
            body = resp.json()

            error = body.get("error")
            match = body.get("match")
            server_latency = body.get("latency_ms", 0)

            if error:
                pipeline_fail += 1
                writer.writerow({
                    "test_type": "genuine",
                    "subject_id": subj,
                    "eye_side": eye_side,
                    "image_file": img_path.name,
                    "expected_identity": subj,
                    "is_match": False,
                    "matched_identity_id": "",
                    "hamming_distance": "",
                    "best_rotation": "",
                    "server_latency_ms": f"{server_latency:.2f}",
                    "client_latency_ms": f"{latency_ms:.2f}",
                    "error": error,
                    "correct": False,
                })
                continue

            is_match = False
            matched_id = ""
            hd = ""
            rotation = ""

            if match is not None:
                is_match = match.get("is_match", False)
                matched_id = match.get("matched_identity_id") or ""
                hd = match.get("hamming_distance", "")
                rotation = match.get("best_rotation", "")

            if is_match and matched_id == subj:
                correct += 1
                is_correct = True
            elif is_match and matched_id != subj:
                wrong_identity += 1
                is_correct = False
            else:
                false_negative += 1
                is_correct = False

            writer.writerow({
                "test_type": "genuine",
                "subject_id": subj,
                "eye_side": eye_side,
                "image_file": img_path.name,
                "expected_identity": subj,
                "is_match": is_match,
                "matched_identity_id": matched_id,
                "hamming_distance": hd,
                "best_rotation": rotation,
                "server_latency_ms": f"{server_latency:.2f}",
                "client_latency_ms": f"{latency_ms:.2f}",
                "error": "",
                "correct": is_correct,
            })

        except Exception as e:
            latency_ms = (time.monotonic() - t0) * 1000
            pipeline_fail += 1
            writer.writerow({
                "test_type": "genuine",
                "subject_id": subj,
                "eye_side": eye_side,
                "image_file": img_path.name,
                "expected_identity": subj,
                "is_match": False,
                "matched_identity_id": "",
                "hamming_distance": "",
                "best_rotation": "",
                "server_latency_ms": "0",
                "client_latency_ms": f"{latency_ms:.2f}",
                "error": str(e),
                "correct": False,
            })

        iterator.set_postfix(ok=correct, fn=false_negative, wrong=wrong_identity, fail=pipeline_fail)

    return {
        "total": total,
        "correct": correct,
        "false_negative": false_negative,
        "wrong_identity": wrong_identity,
        "pipeline_fail": pipeline_fail,
    }


# ---------------------------------------------------------------------------
# Impostor Verification (negative tests — real unenrolled subjects)
# ---------------------------------------------------------------------------

def run_impostor_verification(dataset: Path, api_url: str, writer: csv.DictWriter,
                              progress: bool = True) -> dict:
    """
    Send ALL images from unenrolled subjects (800–999) as impostor probes.
    The system must return is_match=false for every single one.
    Any match is a true false positive.
    """
    subjects = [subject_dir_name(i) for i in IMPOSTOR_SUBJECTS]
    total = 0
    true_reject = 0
    false_positive = 0
    pipeline_fail = 0

    items = []
    for subj in subjects:
        for eye_code, eye_side in EYE_SIDES.items():
            eye_dir = dataset / subj / eye_code
            images = sorted_images(eye_dir)
            for img_path in images:
                items.append((subj, eye_code, eye_side, img_path))

    desc = "Impostor probes"
    iterator = tqdm(items, desc=desc, disable=not progress)

    for subj, eye_code, eye_side, img_path in iterator:
        total += 1
        t0 = time.monotonic()
        try:
            jpeg_b64 = load_jpeg_b64(img_path)
            resp = requests.post(
                f"{api_url}/analyze/json",
                json={
                    "jpeg_b64": jpeg_b64,
                    "eye_side": eye_side,
                    "frame_id": f"impostor_{subj}_{eye_code}_{img_path.stem}",
                    "device_id": "vnv-benchmark",
                },
                timeout=60,
            )
            latency_ms = (time.monotonic() - t0) * 1000
            body = resp.json()

            error = body.get("error")
            match = body.get("match")
            server_latency = body.get("latency_ms", 0)

            if error:
                pipeline_fail += 1
                writer.writerow({
                    "test_type": "impostor",
                    "subject_id": subj,
                    "eye_side": eye_side,
                    "image_file": img_path.name,
                    "expected_identity": "",
                    "is_match": False,
                    "matched_identity_id": "",
                    "hamming_distance": "",
                    "best_rotation": "",
                    "server_latency_ms": f"{server_latency:.2f}",
                    "client_latency_ms": f"{latency_ms:.2f}",
                    "error": error,
                    "correct": False,
                })
                continue

            is_match = False
            matched_id = ""
            hd = ""
            rotation = ""

            if match is not None:
                is_match = match.get("is_match", False)
                matched_id = match.get("matched_identity_id") or ""
                hd = match.get("hamming_distance", "")
                rotation = match.get("best_rotation", "")

            if is_match:
                false_positive += 1
                is_correct = False
            else:
                true_reject += 1
                is_correct = True

            writer.writerow({
                "test_type": "impostor",
                "subject_id": subj,
                "eye_side": eye_side,
                "image_file": img_path.name,
                "expected_identity": "",
                "is_match": is_match,
                "matched_identity_id": matched_id,
                "hamming_distance": hd,
                "best_rotation": rotation,
                "server_latency_ms": f"{server_latency:.2f}",
                "client_latency_ms": f"{latency_ms:.2f}",
                "error": "",
                "correct": is_correct,
            })

        except Exception as e:
            latency_ms = (time.monotonic() - t0) * 1000
            pipeline_fail += 1
            writer.writerow({
                "test_type": "impostor",
                "subject_id": subj,
                "eye_side": eye_side,
                "image_file": img_path.name,
                "expected_identity": "",
                "is_match": False,
                "matched_identity_id": "",
                "hamming_distance": "",
                "best_rotation": "",
                "server_latency_ms": "0",
                "client_latency_ms": f"{latency_ms:.2f}",
                "error": str(e),
                "correct": False,
            })

        iterator.set_postfix(reject=true_reject, fp=false_positive, fail=pipeline_fail)

    return {
        "total": total,
        "true_reject": true_reject,
        "false_positive": false_positive,
        "pipeline_fail": pipeline_fail,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="EyeD V&V Benchmark Runner")
    parser.add_argument("--dataset",
                        default=os.environ.get("VNV_DATASET", ""),
                        help="Path to CASIA-Iris-Thousand dataset root")
    parser.add_argument("--api",
                        default=os.environ.get("VNV_API_URL", "http://localhost:9510"),
                        help="EyeD API base URL")
    parser.add_argument("--output",
                        default=os.environ.get("VNV_OUTPUT", "reports/vnv/"),
                        help="Output directory root")
    parser.add_argument("--no-progress", action="store_true",
                        help="Disable progress bars")
    args = parser.parse_args()

    dataset = Path(args.dataset)
    if not dataset.is_dir():
        print(f"ERROR: Dataset directory not found: {dataset}", file=sys.stderr)
        sys.exit(1)

    api_url = args.api.rstrip("/")
    show_progress = not args.no_progress

    # ── Check API readiness ──────────────────────────────────────────────
    print(f"Checking API at {api_url} ...")
    health = check_api_ready(api_url)
    gallery_before = get_gallery_size(api_url)
    print(f"  API ready. Gallery size: {gallery_before}, SMPC active: {health.get('smpc_active')}")

    if gallery_before > 0:
        print(f"  WARNING: Gallery is not empty ({gallery_before} templates).")
        print(f"  For a clean benchmark, run 'make db-reset' and restart the service.")
        print(f"  Proceeding anyway — results will reflect current gallery state.")

    # ── Create timestamped output directory ──────────────────────────────
    timestamp = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    run_dir = Path(args.output) / timestamp
    plots_dir = run_dir / "plots"
    plots_dir.mkdir(parents=True, exist_ok=True)

    # Update 'latest' symlink
    latest_link = Path(args.output) / "latest"
    if latest_link.is_symlink() or latest_link.exists():
        latest_link.unlink()
    latest_link.symlink_to(timestamp)

    print(f"Output directory: {run_dir}")

    # ── Save metadata ────────────────────────────────────────────────────
    metadata = {
        "timestamp": timestamp,
        "git_sha": get_git_sha(),
        "dataset_path": str(dataset),
        "api_url": api_url,
        "gallery_size_before": gallery_before,
        "smpc_active": health.get("smpc_active", False),
        "api_version": health.get("version", "unknown"),
        "enrolled_subjects": "000-799",
        "impostor_subjects": "800-999",
        "python_version": sys.version,
    }
    with open(run_dir / "metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)

    # ── Phase 1: Enrollment ──────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("PHASE 1: ENROLLMENT (subjects 000–799, first image per eye)")
    print("=" * 60)

    enrollment_fields = [
        "subject_id", "eye_side", "image_file", "http_status",
        "template_id", "is_duplicate", "smpc_protected", "error", "latency_ms",
    ]
    enrollment_file = open(run_dir / "enrollment.csv", "w", newline="")
    enrollment_writer = csv.DictWriter(enrollment_file, fieldnames=enrollment_fields)
    enrollment_writer.writeheader()

    t_enroll_start = time.monotonic()
    enroll_stats = run_enrollment(dataset, api_url, enrollment_writer, show_progress)
    t_enroll_end = time.monotonic()
    enrollment_file.close()

    enroll_stats["duration_sec"] = round(t_enroll_end - t_enroll_start, 2)
    gallery_after_enroll = get_gallery_size(api_url)
    enroll_stats["gallery_size_after"] = gallery_after_enroll

    print(f"\nEnrollment complete:")
    print(f"  Total: {enroll_stats['total']}")
    print(f"  Success: {enroll_stats['success']}")
    print(f"  Duplicate: {enroll_stats['duplicate']}")
    print(f"  Failed: {enroll_stats['failed']}")
    print(f"  FTE rate: {enroll_stats['fte_rate']:.6f}")
    print(f"  Gallery size: {gallery_after_enroll}")
    print(f"  Duration: {enroll_stats['duration_sec']}s")

    # ── Phase 2: Genuine Verification ────────────────────────────────────
    print("\n" + "=" * 60)
    print("PHASE 2: GENUINE VERIFICATION (remaining images from enrolled subjects)")
    print("=" * 60)

    verify_fields = [
        "test_type", "subject_id", "eye_side", "image_file",
        "expected_identity", "is_match", "matched_identity_id",
        "hamming_distance", "best_rotation",
        "server_latency_ms", "client_latency_ms", "error", "correct",
    ]
    genuine_file = open(run_dir / "genuine.csv", "w", newline="")
    genuine_writer = csv.DictWriter(genuine_file, fieldnames=verify_fields)
    genuine_writer.writeheader()

    t_genuine_start = time.monotonic()
    genuine_stats = run_genuine_verification(dataset, api_url, genuine_writer, show_progress)
    t_genuine_end = time.monotonic()
    genuine_file.close()

    genuine_stats["duration_sec"] = round(t_genuine_end - t_genuine_start, 2)

    print(f"\nGenuine verification complete:")
    print(f"  Total probes: {genuine_stats['total']}")
    print(f"  Correct matches: {genuine_stats['correct']}")
    print(f"  False negatives: {genuine_stats['false_negative']}")
    print(f"  Wrong identity: {genuine_stats['wrong_identity']}")
    print(f"  Pipeline failures: {genuine_stats['pipeline_fail']}")
    print(f"  Duration: {genuine_stats['duration_sec']}s")

    # ── Phase 3: Impostor Verification ───────────────────────────────────
    print("\n" + "=" * 60)
    print("PHASE 3: IMPOSTOR VERIFICATION (all images from unenrolled subjects 800–999)")
    print("=" * 60)

    impostor_file = open(run_dir / "impostor.csv", "w", newline="")
    impostor_writer = csv.DictWriter(impostor_file, fieldnames=verify_fields)
    impostor_writer.writeheader()

    t_impostor_start = time.monotonic()
    impostor_stats = run_impostor_verification(dataset, api_url, impostor_writer, show_progress)
    t_impostor_end = time.monotonic()
    impostor_file.close()

    impostor_stats["duration_sec"] = round(t_impostor_end - t_impostor_start, 2)

    print(f"\nImpostor verification complete:")
    print(f"  Total probes: {impostor_stats['total']}")
    print(f"  True rejects: {impostor_stats['true_reject']}")
    print(f"  FALSE POSITIVES: {impostor_stats['false_positive']}")
    print(f"  Pipeline failures: {impostor_stats['pipeline_fail']}")
    print(f"  Duration: {impostor_stats['duration_sec']}s")

    # ── Save summary ─────────────────────────────────────────────────────
    summary = {
        "timestamp": timestamp,
        "enrollment": enroll_stats,
        "genuine": genuine_stats,
        "impostor": impostor_stats,
        "total_duration_sec": round(
            enroll_stats["duration_sec"]
            + genuine_stats["duration_sec"]
            + impostor_stats["duration_sec"], 2
        ),
    }
    with open(run_dir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    # ── Final report ─────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("BENCHMARK COMPLETE")
    print("=" * 60)
    print(f"  Output: {run_dir}")
    print(f"  Total duration: {summary['total_duration_sec']}s")
    print(f"  Enrollment FTE: {enroll_stats['fte_rate']:.6f}")

    genuine_total_valid = genuine_stats["total"] - genuine_stats["pipeline_fail"]
    if genuine_total_valid > 0:
        fnmr = genuine_stats["false_negative"] / genuine_total_valid
        wrong_rate = genuine_stats["wrong_identity"] / genuine_total_valid
        print(f"  Genuine FNMR: {fnmr:.6f} ({genuine_stats['false_negative']}/{genuine_total_valid})")
        print(f"  Wrong ID rate: {wrong_rate:.6f} ({genuine_stats['wrong_identity']}/{genuine_total_valid})")

    impostor_total_valid = impostor_stats["total"] - impostor_stats["pipeline_fail"]
    if impostor_total_valid > 0:
        fmr = impostor_stats["false_positive"] / impostor_total_valid
        print(f"  Impostor FMR: {fmr:.6f} ({impostor_stats['false_positive']}/{impostor_total_valid})")

    if impostor_stats["false_positive"] > 0:
        print(f"\n  ⚠ WARNING: {impostor_stats['false_positive']} FALSE POSITIVES DETECTED")
        print(f"  This means unenrolled subjects were incorrectly matched.")

    print(f"\nNext step: python scripts/vnv/analyze.py --input {run_dir}")


if __name__ == "__main__":
    main()
