#!/usr/bin/env python3
"""Discover every test-ci-* Make target and run it as a blocking CI test.

No registry of test names is maintained here. GNU Make expands generated and
included targets first; this script reads its resolved target database. Targets
run serially within a shard because many QEMU tests rewrite shared ISO files.
Separate GitHub runners give shards separate working directories.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys
import time

CI_TARGET = re.compile(r"^(test-ci-[A-Za-z0-9][A-Za-z0-9_.-]*):(?=\s|$)", re.MULTILINE)


def parse_targets(make_database: str) -> list[str]:
    """Only explicit test-ci-* targets, never pattern rules or dependencies."""
    return sorted(set(CI_TARGET.findall(make_database)))


def discover_targets(root: Path) -> list[str]:
    # -q prevents recipe execution; -p prints GNU Make's expanded database.
    # Exit 1 means the phony 'help' target would need running, not a failure.
    result = subprocess.run(
        ["make", "-rRqp", "-f", "Makefile", "help"],
        cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError("Could not inspect Make targets:\n" + result.stderr)
    targets = parse_targets(result.stdout)
    if not targets:
        raise RuntimeError("No test-ci-* targets found. Refusing to pass an empty suite.")
    return targets


def select_shard(targets: list[str], index: int, count: int) -> list[str]:
    if count < 1 or index < 0 or index >= count:
        raise ValueError("shard index must be between 0 and shards - 1")
    return [target for position, target in enumerate(targets) if position % count == index]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--shards", type=int, default=1)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--timeout", type=int, default=600, help="seconds per test")
    parser.add_argument("--list", action="store_true", help="show selected tests without running")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    try:
        root = args.root.resolve()
        targets = discover_targets(root)
        selected = select_shard(targets, args.shard, args.shards)
    except (RuntimeError, ValueError) as error:
        parser.error(str(error))

    print(
        f"Discovered {len(targets)} unique CI tests; "
        f"shard {args.shard + 1}/{args.shards} runs {len(selected)}.",
        flush=True,
    )
    for target in selected:
        print(f"  {target}", flush=True)
    if args.list:
        return 0

    failed: list[str] = []
    for position, target in enumerate(selected, 1):
        print(f"\n=== [{position}/{len(selected)}] {target} ===", flush=True)
        started = time.monotonic()
        try:
            result = subprocess.run(
                ["make", "--no-print-directory", "-j1", target],
                cwd=root, timeout=args.timeout, check=False,
            )
            status = result.returncode
        except subprocess.TimeoutExpired:
            status = 124
            print(f"TIMEOUT after {args.timeout}s: {target}", file=sys.stderr, flush=True)
        elapsed = time.monotonic() - started
        if status:
            failed.append(target)
        print(
            f"{'PASS' if status == 0 else 'FAIL'} {target}: "
            f"exit={status}, elapsed={elapsed:.1f}s",
            flush=True,
        )

    print(f"\nCI shard summary: {len(selected) - len(failed)}/{len(selected)} passed.", flush=True)
    if failed:
        print("Failed CI tests: " + ", ".join(failed), file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
