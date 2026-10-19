#!/usr/bin/env python3
"""Time fixed native graphics workloads and save repeatable baseline results."""

import json
from pathlib import Path
import statistics
import subprocess
import sys
import time


WORKLOADS = {
    "draw": (24, 640 * 480),
    "copy": (24, 640 * 480),
    "alpha": (12, 640 * 480),
    "compose": (12, 640 * 480),
    "partial": (240, 64 * 64),
    "present": (12, 640 * 480),
    "present_partial": (240, 64 * 64),
}


def measure(executable, mode):
    samples = []
    for _ in range(4):
        start = time.perf_counter_ns()
        result = subprocess.run([str(executable), mode], check=True,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=30)
        elapsed = time.perf_counter_ns() - start
        if result.stdout or result.stderr:
            raise RuntimeError(f"unexpected benchmark output: {mode}")
        samples.append(elapsed)
    return statistics.median(samples[1:])


def main():
    executable = Path(sys.argv[1]).resolve()
    destination = Path(sys.argv[2])
    results = {}
    for mode, (frames, pixels_per_frame) in WORKLOADS.items():
        elapsed = measure(executable, mode)
        results[mode] = {
            "frames": frames,
            "pixels_per_frame": pixels_per_frame,
            "median_ms": round(elapsed / 1_000_000, 3),
            "ms_per_frame": round(elapsed / 1_000_000 / frames, 4),
            "megapixels_per_second": round(
                frames * pixels_per_frame * 1000 / elapsed, 3),
        }
    results["compose_speedup_per_frame"] = round(
        results["compose"]["ms_per_frame"] /
        results["partial"]["ms_per_frame"], 2)
    # The small dirty rectangle must remain meaningfully cheaper to compose
    # and transfer than a whole screen, even on a busy host.
    if results["compose_speedup_per_frame"] < 4 or (
        results["present"]["ms_per_frame"] /
        results["present_partial"]["ms_per_frame"] < 4
    ):
        raise AssertionError("partial rendering lost its frame-time advantage")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
