#!/usr/bin/env python3
"""
EyeD V&V Docker Resource Profiler

Captures docker stats at 1-second intervals and writes to profile.csv
in the latest (or specified) run directory.

Run in background before starting benchmark.py:
    python scripts/vnv/profile.py --output reports/vnv/ &

Stop with Ctrl+C or kill. The CSV is flushed on every write.
"""

import argparse
import csv
import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


# ---------------------------------------------------------------------------
# Docker stats parsing
# ---------------------------------------------------------------------------

def parse_docker_stats(container_name: str = "iris-engine2") -> dict | None:
    """
    Run 'docker stats --no-stream' and parse the output for the target container.
    Returns dict with cpu_percent, mem_usage_mb, mem_limit_mb, net_in_mb, net_out_mb.
    """
    try:
        result = subprocess.run(
            ["docker", "stats", "--no-stream",
             "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return None

        for line in result.stdout.strip().split("\n"):
            parts = line.split("\t")
            if len(parts) < 4:
                continue

            name = parts[0].strip()
            if container_name not in name:
                continue

            # CPU: "12.34%"
            cpu_str = parts[1].strip().rstrip("%")
            try:
                cpu_pct = float(cpu_str)
            except ValueError:
                cpu_pct = 0.0

            # Memory: "123.4MiB / 8GiB"
            mem_parts = parts[2].strip().split("/")
            mem_usage = parse_mem(mem_parts[0].strip()) if len(mem_parts) >= 1 else 0
            mem_limit = parse_mem(mem_parts[1].strip()) if len(mem_parts) >= 2 else 0

            # Network: "1.23MB / 4.56MB"
            net_parts = parts[3].strip().split("/")
            net_in = parse_mem(net_parts[0].strip()) if len(net_parts) >= 1 else 0
            net_out = parse_mem(net_parts[1].strip()) if len(net_parts) >= 2 else 0

            return {
                "cpu_percent": cpu_pct,
                "mem_usage_mb": mem_usage,
                "mem_limit_mb": mem_limit,
                "net_in_mb": net_in,
                "net_out_mb": net_out,
            }

    except Exception:
        return None

    return None


def parse_mem(s: str) -> float:
    """Parse memory strings like '123.4MiB', '1.5GiB', '500kB' to MB."""
    s = s.strip()
    match = re.match(r"([\d.]+)\s*(\w+)", s)
    if not match:
        return 0.0
    value = float(match.group(1))
    unit = match.group(2).lower()
    if "gib" in unit or "gb" in unit:
        return value * 1024
    elif "mib" in unit or "mb" in unit:
        return value
    elif "kib" in unit or "kb" in unit:
        return value / 1024
    elif "b" in unit:
        return value / (1024 * 1024)
    return value


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="EyeD V&V Docker Resource Profiler")
    parser.add_argument("--output", default="reports/vnv/",
                        help="Output directory root (default: reports/vnv/)")
    parser.add_argument("--container", default="iris-engine2",
                        help="Docker container name to monitor (default: iris-engine2)")
    parser.add_argument("--interval", type=float, default=1.0,
                        help="Sampling interval in seconds (default: 1.0)")
    args = parser.parse_args()

    output_root = Path(args.output)

    # Find or create the run directory
    latest_link = output_root / "latest"
    if latest_link.is_symlink() or latest_link.exists():
        run_dir = latest_link.resolve()
    else:
        timestamp = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
        run_dir = output_root / timestamp
        run_dir.mkdir(parents=True, exist_ok=True)
        latest_link.symlink_to(timestamp)

    csv_path = run_dir / "profile.csv"
    print(f"Profiling container '{args.container}' every {args.interval}s")
    print(f"Writing to: {csv_path}")
    print("Press Ctrl+C to stop.\n")

    # Handle graceful shutdown
    running = True

    def handle_signal(sig, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    fields = ["timestamp", "elapsed_sec", "cpu_percent", "mem_usage_mb",
              "mem_limit_mb", "net_in_mb", "net_out_mb"]

    csv_file = open(csv_path, "w", newline="")
    writer = csv.DictWriter(csv_file, fieldnames=fields)
    writer.writeheader()

    start_time = time.monotonic()
    sample_count = 0

    while running:
        stats = parse_docker_stats(args.container)
        if stats:
            elapsed = time.monotonic() - start_time
            row = {
                "timestamp": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
                "elapsed_sec": f"{elapsed:.1f}",
                **{k: f"{v:.2f}" for k, v in stats.items()},
            }
            writer.writerow(row)
            csv_file.flush()
            sample_count += 1

            if sample_count % 10 == 1:
                print(f"  [{row['timestamp']}] CPU: {stats['cpu_percent']:.1f}%  "
                      f"Mem: {stats['mem_usage_mb']:.0f}/{stats['mem_limit_mb']:.0f} MB  "
                      f"Net: {stats['net_in_mb']:.1f}/{stats['net_out_mb']:.1f} MB")
        else:
            if sample_count == 0:
                print(f"  WARNING: Container '{args.container}' not found in docker stats. Retrying...")

        time.sleep(args.interval)

    csv_file.close()
    print(f"\nProfiler stopped. {sample_count} samples written to {csv_path}")


if __name__ == "__main__":
    main()
