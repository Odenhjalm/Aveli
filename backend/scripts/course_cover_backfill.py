#!/usr/bin/env python3
"""Backfill legacy course covers into app.media_assets.

Dry-run is the default. Use ``--apply`` to assign ``courses.cover_media_id`` for
safely verifiable legacy covers while keeping ``cover_url`` intact.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview classifications and planned mutations only (default).",
    )
    mode.add_argument(
        "--apply",
        action="store_true",
        help="Mutate legacy_migratable courses using the application backfill service.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=100,
        help="Number of courses to scan per batch (default: %(default)s).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional max number of courses with cover_url to scan.",
    )
    parser.add_argument(
        "--format",
        choices=("json", "tsv"),
        default="json",
        help="Output format (default: %(default)s).",
    )
    return parser.parse_args()


def _print_tsv(report: dict) -> None:
    print(
        "\t".join(
            (
                "course_id",
                "slug",
                "classification",
                "reason",
                "planned_action",
                "mutation_action",
                "cover_media_id",
                "assigned_media_id",
                "legacy_storage_path",
                "error",
            )
        )
    )
    for item in report.get("items", []):
        print(
            "\t".join(
                (
                    str(item.get("course_id") or ""),
                    str(item.get("slug") or ""),
                    str(item.get("classification") or ""),
                    str(item.get("reason") or ""),
                    str(item.get("planned_action") or ""),
                    str(item.get("mutation_action") or ""),
                    str(item.get("cover_media_id") or ""),
                    str(item.get("assigned_media_id") or ""),
                    str(item.get("legacy_storage_path") or ""),
                    str(item.get("error") or ""),
                )
            )
        )
    print()
    print(json.dumps({k: v for k, v in report.items() if k != "items"}, indent=2))


async def _main() -> None:
    args = parse_args()
    try:
        from app.db import pool  # noqa: WPS433
        from app.services.course_cover_backfill import (  # noqa: WPS433
            run_course_cover_backfill,
        )
    except ModuleNotFoundError as exc:  # pragma: no cover - environment-specific
        missing = str(exc).split("No module named ", 1)[-1]
        raise SystemExit(
            f"Missing backend dependency {missing}. Run this script with the backend environment active."
        ) from exc

    if pool.closed:
        await pool.open(wait=True)
    try:
        report = await run_course_cover_backfill(
            apply=bool(args.apply),
            batch_size=args.batch_size,
            max_courses=args.limit,
        )
        payload = report.to_dict()
        if args.format == "tsv":
            _print_tsv(payload)
        else:
            print(json.dumps(payload, default=str, indent=2))
    finally:
        await pool.close()


if __name__ == "__main__":
    asyncio.run(_main())
