#!/usr/bin/env python3
"""Verify that database/schema.sql matches the concatenated migrations.

Run locally (or in CI) to ensure the monolithic schema dump stays in sync with
the versioned migration files under backend/migrations/sql/.
"""

from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = ROOT / "backend" / "migrations" / "sql"
SCHEMA_FILE = ROOT / "database" / "schema.sql"


def read_normalised(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise FileNotFoundError(f"Missing file: {path}") from exc
    # Normalise whitespace to minimise false positives
    lines = [line.rstrip() for line in text.splitlines()]
    normalised = "\n".join(lines).strip() + ("\n" if lines else "")
    return normalised


def build_migration_snapshot() -> str:
    if not MIGRATIONS_DIR.exists():
        raise FileNotFoundError(f"Missing migrations directory: {MIGRATIONS_DIR}")
    parts: list[str] = []
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        header = f"-- {path.name}"
        parts.append(header)
        parts.append(read_normalised(path))
    return "\n".join(parts).strip() + "\n"


def compare(show_diff: bool) -> int:
    schema = read_normalised(SCHEMA_FILE)
    combined = build_migration_snapshot()

    if schema == combined:
        print("✅ database/schema.sql matches backend/migrations/sql")
        return 0

    print("❌ Schema mismatch detected.", file=sys.stderr)
    if show_diff:
        diff = difflib.unified_diff(
            schema.splitlines(), combined.splitlines(),
            fromfile="database/schema.sql",
            tofile="backend/migrations/sql/*",
            lineterm="",
        )
        for line in diff:
            print(line, file=sys.stderr)
    else:
        print("Run with --diff to see differences.", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--diff",
        action="store_true",
        help="Show unified diff when mismatch is detected.",
    )
    args = parser.parse_args()
    try:
        return compare(show_diff=args.diff)
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
