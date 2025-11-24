#!/usr/bin/env python3
"""
Scan database snapshots for SECURITY DEFINER functions.

By default the script looks for `functions.csv` files under `out/db_snapshot_*`
and reports every function that is marked as SECURITY DEFINER in the snapshot.

Usage examples
--------------
python scripts/security_definer_audit.py
python scripts/security_definer_audit.py --snapshots-root out --format json
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="List SECURITY DEFINER functions per DB snapshot.")
    parser.add_argument(
        "--snapshots-root",
        default="out",
        help="Directory that contains db_snapshot_* folders (default: %(default)s).",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format. text prints a readable report; json dumps machine-friendly data.",
    )
    return parser.parse_args()


def load_snapshot_functions(snapshot: Path) -> List[Dict[str, str]]:
    functions_file = snapshot / "functions.csv"
    if not functions_file.exists():
        return []

    with functions_file.open(newline="") as fh:
        reader = csv.DictReader(fh)
        return [
            row
            for row in reader
            if row.get("security", "").strip().upper() == "SECURITY DEFINER"
        ]


def main() -> None:
    args = parse_args()
    root = Path(args.snapshots_root)
    if not root.exists():
        raise SystemExit(f"Snapshots root {root} does not exist.")

    data = {}
    for snapshot_dir in sorted(root.glob("db_snapshot_*")):
        definers = load_snapshot_functions(snapshot_dir)
        if definers:
            data[snapshot_dir.name] = definers
        else:
            data[snapshot_dir.name] = []

    if args.format == "json":
        print(json.dumps(data, indent=2))
        return

    if not data:
        print(f"No db_snapshot_* folders found in {root}")
        return

    for snap, definers in data.items():
        count = len(definers)
        print(f"{snap}: {count} SECURITY DEFINER function{'s' if count != 1 else ''}")
        if not definers:
            continue
        for row in definers:
            argtypes = row.get("argtypes", "")
            signature = f"{row.get('schema')}.{row.get('function')}({argtypes})".rstrip()
            print(f"  - {signature} -> {row.get('returns')} [{row.get('volatility')}] {row.get('lang')}")


if __name__ == "__main__":
    main()
