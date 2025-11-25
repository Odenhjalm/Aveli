#!/usr/bin/env python3
"""
Bulk import runner for course manifests under courses/.

Features
- Scans a directory (default: courses/) for YAML/JSON manifests
- Optional order file support (default: courses/order.txt)
- Filters via --only/--exclude (substring match against filename or slug)
- Runs validation only (--dry-run) or performs real import by invoking scripts/import_course.py

Requirements
- Python 3.10+
- requests, pyyaml (same as scripts/import_course.py when using YAML manifests)

Examples
  # Validate all manifests (no uploads)
  python scripts/bulk_import.py --dry-run

  # Import all with a dedicated _Assets lesson for covers
  python scripts/bulk_import.py \
    --base-url http://127.0.0.1:8080 \
    --email teacher@example.com \
    --password teacher123 \
    --create-assets-lesson

  # Import a single course by slug/filename match
  python scripts/bulk_import.py --only tarot-basics \
    --base-url http://127.0.0.1:8080 --email ... --password ...
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path
from typing import Iterable, List, Optional, Tuple
import sys


def find_manifests(root: Path) -> list[Path]:
    exts = (".yaml", ".yml", ".json")
    return sorted([p for p in root.glob("*") if p.suffix.lower() in exts and p.is_file()])


def load_slug(path: Path) -> Optional[str]:
    try:
        text = path.read_text(encoding="utf-8")
        if path.suffix.lower() == ".json":
            data = json.loads(text)
            slug = data.get("slug")
        else:
            # Lazy import for YAML so script works without PyYAML when not needed
            import yaml  # type: ignore

            data = yaml.safe_load(text)
            slug = data.get("slug")
        if isinstance(slug, str):
            return slug
    except Exception:
        return None
    return None


def apply_order(manifests: list[Path], order_file: Path) -> list[Path]:
    if not order_file.exists():
        return manifests
    order_lines = [
        ln.strip()
        for ln in order_file.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]
    if not order_lines:
        return manifests

    # Build lookup by filename and slug
    by_name = {p.name: p for p in manifests}
    by_slug = {load_slug(p): p for p in manifests}

    ordered: list[Path] = []
    seen: set[Path] = set()

    for key in order_lines:
        p = by_name.get(key) or by_slug.get(key)
        if p and p in manifests and p not in seen:
            ordered.append(p)
            seen.add(p)

    for p in manifests:
        if p not in seen:
            ordered.append(p)
            seen.add(p)
    return ordered


def filter_manifests(
    manifests: Iterable[Path], only: list[str], exclude: list[str]
) -> list[Path]:
    def match_any(p: Path, needles: list[str]) -> bool:
        if not needles:
            return True
        slug = load_slug(p) or ""
        hay = f"{p.name} {slug}".lower()
        return any(n.lower() in hay for n in needles)

    out: list[Path] = []
    for p in manifests:
        if only and not match_any(p, only):
            continue
        if exclude and match_any(p, exclude):
            continue
        out.append(p)
    return out


def run_import(
    manifest: Path,
    *,
    base_url: str,
    email: str,
    password: str,
    dry_run: bool,
    max_size_mb: int | None,
    create_assets_lesson: bool,
    cleanup_duplicates: bool,
) -> int:
    cmd = [
        sys.executable or "python",
        "scripts/import_course.py",
        "--manifest",
        str(manifest),
        "--base-url",
        base_url,
        "--email",
        email,
        "--password",
        password,
    ]
    if dry_run:
        cmd.append("--dry-run")
        if max_size_mb is not None:
            cmd += ["--max-size-mb", str(max_size_mb)]
    if create_assets_lesson:
        cmd.append("--create-assets-lesson")
    if cleanup_duplicates:
        cmd.append("--cleanup-duplicates")

    print(f"$ {' '.join(cmd)}")
    proc = subprocess.run(cmd, check=False)
    return proc.returncode


def main() -> None:
    ap = argparse.ArgumentParser(description="Bulk import courses from manifests")
    ap.add_argument("--dir", default="courses", help="Directory with manifests")
    ap.add_argument("--order-file", default=None, help="Optional order file (default: <dir>/order.txt)")
    ap.add_argument("--only", action="append", default=[], help="Only import manifests matching this (slug or filename). Can be repeated.")
    ap.add_argument("--exclude", action="append", default=[], help="Skip manifests matching this (slug or filename). Can be repeated.")
    ap.add_argument("--dry-run", action="store_true", help="Validate manifests and files only; no uploads.")
    ap.add_argument("--max-size-mb", type=int, default=None, help="Warn on files larger than this many MB (dry-run only).")
    ap.add_argument("--create-assets-lesson", action="store_true", help="Upload cover into _Assets/_Course Assets lesson and set cover_url.")
    ap.add_argument("--cleanup-duplicates", action="store_true", help="Delete duplicate lesson media entries after import.")
    ap.add_argument("--continue-on-error", action="store_true", help="Continue processing other manifests on failure.")
    ap.add_argument("--base-url", default=os.getenv("API_BASE_URL", "http://127.0.0.1:8080"))
    ap.add_argument("--email", default=os.getenv("IMPORT_EMAIL", "teacher@example.com"))
    ap.add_argument("--password", default=os.getenv("IMPORT_PASSWORD", "teacher123"))

    args = ap.parse_args()

    root = Path(args.dir).resolve()
    if not root.exists():
        raise SystemExit(f"Manifest directory not found: {root}")

    manifests = find_manifests(root)
    if not manifests:
        print("No manifests found.")
        return

    order_file = Path(args.order_file) if args.order_file else (root / "order.txt")
    manifests = apply_order(manifests, order_file)
    manifests = filter_manifests(manifests, args.only, args.exclude)

    print(f"Found {len(manifests)} manifest(s) under {root}")
    if order_file.exists():
        print(f"Using order from {order_file}")

    failures: list[Tuple[Path, int]] = []
    for i, m in enumerate(manifests, start=1):
        print(f"\n[{i}/{len(manifests)}] Processing: {m.name}")
        code = run_import(
            m,
            base_url=args.base_url,
            email=args.email,
            password=args.password,
            dry_run=args.dry_run,
            max_size_mb=args.max_size_mb,
            create_assets_lesson=args.create_assets_lesson,
            cleanup_duplicates=args.cleanup_duplicates,
        )
        if code != 0:
            print(f"!! Failed: {m} (exit {code})")
            failures.append((m, code))
            if not args.continue_on_error:
                break

    if failures:
        print("\nSummary: failures detected")
        for m, code in failures:
            print(f"  - {m} (exit {code})")
        raise SystemExit(1)

    print("\nSummary: all manifests processed successfully")


if __name__ == "__main__":
    main()
