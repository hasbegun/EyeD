#!/usr/bin/env python3
"""Export curated training datasets from the EyeD archive.

Queries the match_log database for high-confidence frames and copies the
corresponding raw images + metadata from the archive directory into a
self-contained training export.

Usage:
    python scripts/export_training.py \
        --db-url postgresql://eyed:eyed_dev@localhost:9506/eyed \
        --archive-root ./data/archive \
        --output-dir ./data/training-export/export-001 \
        --min-confidence 0.8 \
        --max-frames 10000
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    print("Error: psycopg2 not installed. Run: pip install psycopg2-binary", file=sys.stderr)
    sys.exit(1)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Export training data from the EyeD archive.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--db-url", required=True, help="PostgreSQL connection URL")
    p.add_argument("--archive-root", required=True, help="Path to archive root directory")
    p.add_argument("--output-dir", required=True, help="Output directory for export")
    p.add_argument("--min-confidence", type=float, default=0.0,
                   help="Minimum quality score filter (from metadata, default: 0.0)")
    p.add_argument("--max-frames", type=int, default=0,
                   help="Maximum frames to export (0 = unlimited)")
    p.add_argument("--matches-only", action="store_true",
                   help="Only export frames that had a match")
    p.add_argument("--no-match-only", action="store_true",
                   help="Only export frames that had no match (hard negatives)")
    p.add_argument("--dry-run", action="store_true",
                   help="Print what would be exported without copying files")
    return p.parse_args()


def find_archive_files(archive_root: Path, frame_id: str) -> tuple[Path | None, Path | None]:
    """Search the archive for a frame's JPEG and metadata files.

    Archive layout: raw/{YYYY-MM-DD}/{device_id}/{frame_id}.jpg
    We need to search because we don't know the date/device upfront.
    """
    raw_dir = archive_root / "raw"
    if not raw_dir.exists():
        return None, None

    for date_dir in sorted(raw_dir.iterdir(), reverse=True):
        if not date_dir.is_dir():
            continue
        for device_dir in date_dir.iterdir():
            if not device_dir.is_dir():
                continue
            jpg = device_dir / f"{frame_id}.jpg"
            meta = device_dir / f"{frame_id}.meta.json"
            if jpg.exists():
                return jpg, meta if meta.exists() else None

    return None, None


def export(args: argparse.Namespace) -> None:
    archive_root = Path(args.archive_root)
    output_dir = Path(args.output_dir)

    if not archive_root.exists():
        print(f"Error: Archive root not found: {archive_root}", file=sys.stderr)
        sys.exit(1)

    # Connect to database
    print(f"Connecting to database...")
    conn = psycopg2.connect(args.db_url)
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    # Query match_log for frames to export
    query = "SELECT DISTINCT probe_frame_id, hamming_distance, is_match, device_id FROM match_log"
    conditions = []

    if args.matches_only:
        conditions.append("is_match = true")
    elif args.no_match_only:
        conditions.append("is_match = false")

    if conditions:
        query += " WHERE " + " AND ".join(conditions)

    query += " ORDER BY probe_frame_id"

    if args.max_frames > 0:
        query += f" LIMIT {args.max_frames}"

    cur.execute(query)
    rows = cur.fetchall()
    print(f"Found {len(rows)} frames in match_log")

    if not rows:
        print("No frames to export.")
        return

    # Create output directory structure
    if not args.dry_run:
        (output_dir / "images").mkdir(parents=True, exist_ok=True)
        (output_dir / "metadata").mkdir(parents=True, exist_ok=True)

    exported = 0
    skipped_no_file = 0
    skipped_quality = 0
    manifest_entries = []

    for row in rows:
        frame_id = row["probe_frame_id"]
        device_id = row["device_id"] or "unknown"

        # Find archive files
        jpg_path, meta_path = find_archive_files(archive_root, frame_id)

        if jpg_path is None:
            skipped_no_file += 1
            continue

        # Check quality filter from metadata
        if args.min_confidence > 0 and meta_path:
            try:
                meta = json.loads(meta_path.read_text())
                quality = meta.get("quality_score", 0.0)
                if quality < args.min_confidence:
                    skipped_quality += 1
                    continue
            except (json.JSONDecodeError, KeyError):
                pass

        if args.dry_run:
            print(f"  Would export: {frame_id} ({jpg_path})")
        else:
            # Copy JPEG
            safe_frame_id = frame_id.replace("/", "_").replace("\\", "_")
            shutil.copy2(jpg_path, output_dir / "images" / f"{safe_frame_id}.jpg")

            # Copy metadata
            if meta_path:
                shutil.copy2(meta_path, output_dir / "metadata" / f"{safe_frame_id}.meta.json")

        manifest_entries.append({
            "frame_id": frame_id,
            "device_id": device_id,
            "hamming_distance": float(row["hamming_distance"]),
            "is_match": bool(row["is_match"]),
        })
        exported += 1

    # Write manifest
    if not args.dry_run and manifest_entries:
        manifest = {
            "export_date": datetime.now(timezone.utc).isoformat(),
            "total_frames": exported,
            "filters": {
                "min_confidence": args.min_confidence,
                "matches_only": args.matches_only,
                "no_match_only": args.no_match_only,
            },
            "frames": manifest_entries,
        }
        manifest_path = output_dir / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2))

    # Summary
    print(f"\nExport summary:")
    print(f"  Exported:         {exported}")
    print(f"  Skipped (no file):{skipped_no_file}")
    print(f"  Skipped (quality):{skipped_quality}")
    if not args.dry_run and exported > 0:
        print(f"  Output:           {output_dir}")
        print(f"  Manifest:         {output_dir / 'manifest.json'}")

    cur.close()
    conn.close()


if __name__ == "__main__":
    args = parse_args()
    export(args)
