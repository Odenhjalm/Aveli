#!/usr/bin/env python3
"""Backfill canonical media identity metadata for local Baseline V2 media assets.

This script is intentionally narrow:
- local PostgreSQL only
- app.media_assets identity columns only
- no relationship changes
- binary streamed file hashing
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any
from urllib.parse import urlsplit

try:
    import psycopg
except Exception as exc:  # pragma: no cover - surfaced in direct script usage
    raise SystemExit("psycopg is required for media asset identity backfill") from exc


BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
HASH_ALGORITHM = "sha256"
DEFAULT_BATCH_SIZE = 50
READ_CHUNK_SIZE = 1024 * 1024

INCOMPLETE_IDENTITY_WHERE = """
(
  file_size is null
  or content_hash is null
  or content_hash_algorithm is distinct from 'sha256'
  or content_identity_computed_at is null
)
"""

RELATIONSHIP_COUNT_SQL = """
select 'courses', count(*) from app.courses
union all
select 'lessons', count(*) from app.lessons
union all
select 'lesson_contents', count(*) from app.lesson_contents
union all
select 'lesson_media', count(*) from app.lesson_media
union all
select 'media_assets', count(*) from app.media_assets
"""


class BackfillFileError(Exception):
    def __init__(self, category: str, message: str) -> None:
        super().__init__(message)
        self.category = category
        self.message = message


@dataclass(frozen=True)
class MediaAssetRow:
    id: str
    original_object_path: str
    created_at: datetime


@dataclass(frozen=True)
class IdentityResult:
    file_size: int
    content_hash: str


@dataclass(frozen=True)
class ErrorResult:
    category: str
    message: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Backfill app.media_assets file_size and SHA256 content_hash locally."
    )
    parser.add_argument(
        "--database-url",
        default=os.environ.get("AVELI_LOCAL_DATABASE_URL")
        or os.environ.get("DATABASE_URL")
        or DEFAULT_DATABASE_URL,
        help="Local PostgreSQL URL. Defaults to aveli_local on 127.0.0.1.",
    )
    parser.add_argument(
        "--media-root",
        default=str(REPO_ROOT),
        help="Root used to resolve media_assets.original_object_path.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=DEFAULT_BATCH_SIZE,
        help=f"Rows per deterministic DB batch. Default: {DEFAULT_BATCH_SIZE}.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional maximum number of incomplete rows to attempt in this run.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute identities and errors without writing updates.",
    )
    return parser.parse_args()


def require_local_database(database_url: str) -> None:
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise SystemExit(f"database URL must be PostgreSQL, got {parsed.scheme!r}")
    if parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise SystemExit(
            f"refusing media identity backfill for non-local host {parsed.hostname!r}"
        )


def resolved_media_root(media_root: str) -> Path:
    root = Path(media_root).expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"media root does not exist or is not a directory: {root}")
    return root


def resolve_media_path(media_root: Path, original_object_path: str) -> Path:
    raw = str(original_object_path or "").strip()
    if not raw:
        raise BackfillFileError("UNSAFE_PATH", "original_object_path is blank")

    if Path(raw).is_absolute() or PureWindowsPath(raw).is_absolute():
        raise BackfillFileError("UNSAFE_PATH", f"absolute path is not allowed: {raw}")

    normalized = raw.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    if not parts or any(part == ".." for part in parts):
        raise BackfillFileError("UNSAFE_PATH", f"path traversal is not allowed: {raw}")

    candidate = (media_root / Path(*parts)).resolve(strict=False)
    common = os.path.commonpath(
        [
            os.path.normcase(str(media_root)),
            os.path.normcase(str(candidate)),
        ]
    )
    if common != os.path.normcase(str(media_root)):
        raise BackfillFileError("UNSAFE_PATH", f"path resolves outside media root: {raw}")

    return candidate


def compute_identity(file_path: Path) -> IdentityResult:
    try:
        before = file_path.stat()
    except FileNotFoundError as exc:
        raise BackfillFileError("MISSING_FILE", str(file_path)) from exc
    except PermissionError as exc:
        raise BackfillFileError("UNREADABLE_FILE", f"{type(exc).__name__}: {exc}") from exc
    except OSError as exc:
        raise BackfillFileError("UNREADABLE_FILE", f"{type(exc).__name__}: {exc}") from exc

    if not file_path.is_file():
        raise BackfillFileError("PATH_NOT_FILE", str(file_path))

    hasher = hashlib.sha256()
    bytes_read = 0
    try:
        with file_path.open("rb") as handle:
            while True:
                chunk = handle.read(READ_CHUNK_SIZE)
                if not chunk:
                    break
                bytes_read += len(chunk)
                hasher.update(chunk)
    except FileNotFoundError as exc:
        raise BackfillFileError("MISSING_FILE", str(file_path)) from exc
    except PermissionError as exc:
        raise BackfillFileError("UNREADABLE_FILE", f"{type(exc).__name__}: {exc}") from exc
    except OSError as exc:
        raise BackfillFileError("UNREADABLE_FILE", f"{type(exc).__name__}: {exc}") from exc

    try:
        after = file_path.stat()
    except FileNotFoundError as exc:
        raise BackfillFileError("UNSTABLE_FILE", f"file disappeared: {file_path}") from exc
    except OSError as exc:
        raise BackfillFileError("UNSTABLE_FILE", f"{type(exc).__name__}: {exc}") from exc

    if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
        raise BackfillFileError("UNSTABLE_FILE", f"file changed during hashing: {file_path}")

    if bytes_read != after.st_size:
        raise BackfillFileError(
            "UNSTABLE_FILE",
            f"bytes read {bytes_read} did not match final size {after.st_size}: {file_path}",
        )

    return IdentityResult(file_size=int(after.st_size), content_hash=hasher.hexdigest())


def fetch_counts(conn: psycopg.Connection) -> dict[str, int]:
    with conn.cursor() as cur:
        cur.execute(RELATIONSHIP_COUNT_SQL)
        return {str(name): int(count) for name, count in cur.fetchall()}


def fetch_coverage(conn: psycopg.Connection) -> dict[str, int]:
    with conn.cursor() as cur:
        cur.execute(
            """
            select
              count(*)::int as total,
              count(*) filter (where file_size is not null)::int as with_file_size,
              count(*) filter (where content_hash is not null)::int as with_content_hash,
              count(*) filter (
                where content_hash_algorithm = 'sha256'
              )::int as with_sha256_algorithm,
              count(*) filter (where content_identity_error is not null)::int as with_error,
              count(*) filter (where file_size = 0)::int as zero_byte_files,
              count(*) filter (
                where file_size is not null
                  and content_hash is not null
                  and content_hash_algorithm = 'sha256'
                  and content_identity_computed_at is not null
              )::int as complete_identity,
              count(*) filter (where """ + INCOMPLETE_IDENTITY_WHERE + """)::int
                as incomplete_identity
            from app.media_assets
            """
        )
        row = cur.fetchone()
    keys = (
        "total",
        "with_file_size",
        "with_content_hash",
        "with_sha256_algorithm",
        "with_error",
        "zero_byte_files",
        "complete_identity",
        "incomplete_identity",
    )
    return {key: int(value) for key, value in zip(keys, row, strict=True)}


def fetch_duplicate_path_summary(conn: psycopg.Connection) -> dict[str, int]:
    with conn.cursor() as cur:
        cur.execute(
            """
            with duplicate_paths as (
              select original_object_path, count(*) asset_count
              from app.media_assets
              group by original_object_path
              having count(*) > 1
            )
            select
              count(*)::int as duplicate_path_groups,
              coalesce(sum(asset_count), 0)::int as duplicate_path_assets
            from duplicate_paths
            """
        )
        groups, assets = cur.fetchone()
    return {
        "duplicate_path_groups": int(groups),
        "duplicate_path_assets": int(assets),
    }


def fetch_batch(
    conn: psycopg.Connection,
    batch_size: int,
    remaining_limit: int | None,
) -> list[MediaAssetRow]:
    effective_limit = batch_size if remaining_limit is None else min(batch_size, remaining_limit)
    if effective_limit <= 0:
        return []

    with conn.cursor() as cur:
        cur.execute(
            """
            select id::text, original_object_path, created_at
            from app.media_assets
            where """ + INCOMPLETE_IDENTITY_WHERE + """
            order by created_at asc, id asc
            limit %s
            """,
            (effective_limit,),
        )
        return [
            MediaAssetRow(
                id=str(row_id),
                original_object_path=str(original_object_path),
                created_at=created_at,
            )
            for row_id, original_object_path, created_at in cur.fetchall()
        ]


def update_success(
    conn: psycopg.Connection,
    asset_id: str,
    identity: IdentityResult,
    computed_at: datetime,
) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            update app.media_assets
               set file_size = %s,
                   content_hash = %s,
                   content_hash_algorithm = 'sha256',
                   content_identity_computed_at = %s,
                   content_identity_error = null
             where id = %s
               and """ + INCOMPLETE_IDENTITY_WHERE,
            (identity.file_size, identity.content_hash, computed_at, asset_id),
        )
        return cur.rowcount == 1


def update_error(conn: psycopg.Connection, asset_id: str, error: ErrorResult) -> bool:
    message = f"{error.category}: {error.message}"
    with conn.cursor() as cur:
        cur.execute(
            """
            update app.media_assets
               set content_identity_error = %s
             where id = %s
               and """ + INCOMPLETE_IDENTITY_WHERE,
            (message[:2000], asset_id),
        )
        return cur.rowcount == 1


def process_row(media_root: Path, row: MediaAssetRow) -> IdentityResult | ErrorResult:
    try:
        media_path = resolve_media_path(media_root, row.original_object_path)
        return compute_identity(media_path)
    except BackfillFileError as exc:
        return ErrorResult(category=exc.category, message=exc.message)


def run_backfill(args: argparse.Namespace) -> dict[str, Any]:
    require_local_database(args.database_url)
    if args.batch_size < 1:
        raise SystemExit("--batch-size must be >= 1")
    if args.limit is not None and args.limit < 1:
        raise SystemExit("--limit must be >= 1 when provided")

    media_root = resolved_media_root(args.media_root)
    started_at = datetime.now(timezone.utc)
    attempted = 0
    updated_success = 0
    updated_error = 0
    skipped_complete_before = 0
    skipped_concurrent_complete = 0
    error_categories: Counter[str] = Counter()

    with psycopg.connect(args.database_url) as conn:
        before_counts = fetch_counts(conn)
        before_coverage = fetch_coverage(conn)
        duplicate_path_summary = fetch_duplicate_path_summary(conn)
        skipped_complete_before = before_coverage["complete_identity"]

        remaining_limit = args.limit
        while True:
            batch = fetch_batch(conn, args.batch_size, remaining_limit)
            if not batch:
                break

            updates: list[tuple[MediaAssetRow, IdentityResult | ErrorResult]] = []
            for row in batch:
                updates.append((row, process_row(media_root, row)))

            if not args.dry_run:
                with conn.transaction():
                    for row, result in updates:
                        if isinstance(result, IdentityResult):
                            computed_at = datetime.now(timezone.utc)
                            if update_success(conn, row.id, result, computed_at):
                                updated_success += 1
                            else:
                                skipped_concurrent_complete += 1
                        else:
                            error_categories[result.category] += 1
                            if update_error(conn, row.id, result):
                                updated_error += 1
                            else:
                                skipped_concurrent_complete += 1
            else:
                for _row, result in updates:
                    if isinstance(result, ErrorResult):
                        error_categories[result.category] += 1

            attempted += len(updates)
            if remaining_limit is not None:
                remaining_limit -= len(updates)
                if remaining_limit <= 0:
                    break

        after_counts = fetch_counts(conn)
        after_coverage = fetch_coverage(conn)

    return {
        "database": urlsplit(args.database_url).path.lstrip("/"),
        "media_root": str(media_root),
        "dry_run": bool(args.dry_run),
        "hash_algorithm": HASH_ALGORITHM,
        "batch_size": args.batch_size,
        "ordering": "created_at ASC, id ASC",
        "started_at": started_at.isoformat(),
        "attempted_rows": attempted,
        "updated_success": updated_success,
        "updated_error": updated_error,
        "skipped_complete_before": skipped_complete_before,
        "skipped_concurrent_complete": skipped_concurrent_complete,
        "error_categories": dict(sorted(error_categories.items())),
        "duplicate_path_summary": duplicate_path_summary,
        "relationship_counts_before": before_counts,
        "relationship_counts_after": after_counts,
        "relationship_counts_changed": before_counts != after_counts,
        "coverage_before": before_coverage,
        "coverage_after": after_coverage,
    }


def main() -> int:
    args = parse_args()
    result = run_backfill(args)
    print(json.dumps(result, indent=2, sort_keys=True, default=str))
    if result["relationship_counts_changed"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
