#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence

import psycopg
from psycopg.rows import dict_row


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.utils.audio_content_types import (  # noqa: E402
    GENERIC_BINARY_CONTENT_TYPES,
    SUPPORTED_AUDIO_CONTENT_TYPES,
    audio_content_type_from_extension,
    detect_extension,
    normalize_content_type,
)


UPDATE_TARGETS = {
    "app.media_objects": "content_type",
    "app.media_assets": "original_content_type",
}


@dataclass(frozen=True, slots=True)
class AudioContentRow:
    source_table: str
    media_row_id: str
    lesson_id: str | None
    lesson_title: str | None
    kind: str | None
    content_type: str | None
    storage_bucket: str | None
    storage_path: str | None


@dataclass(frozen=True, slots=True)
class AudioContentIssue:
    source_table: str
    media_row_id: str
    lesson_id: str | None
    lesson_title: str | None
    kind: str | None
    content_type: str | None
    storage_bucket: str | None
    storage_path: str | None
    detected_extension: str | None
    issue_type: str
    proposed_content_type: str | None
    can_apply: bool


@dataclass(frozen=True, slots=True)
class AudioContentUpdate:
    source_table: str
    media_row_id: str
    content_type_column: str
    content_type: str


@dataclass(frozen=True, slots=True)
class AudioScanReport:
    rows: list[AudioContentRow]
    issues: list[AudioContentIssue]
    updates: list[AudioContentUpdate]
    summary: dict[str, int]


def _ensure_db_url(url: str | None) -> str | None:
    if not url:
        return None
    if "sslmode=" in url:
        return url
    if "localhost" in url or "127.0.0.1" in url:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}sslmode=require"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan and optionally normalize audio content types."
    )
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL") or os.getenv("SUPABASE_DB_URL"),
        help="Postgres connection string (default: $DATABASE_URL or $SUPABASE_DB_URL).",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist safe content-type updates. Dry-run is the default.",
    )
    return parser.parse_args(argv)


def _row_from_mapping(data: dict[str, Any]) -> AudioContentRow:
    return AudioContentRow(
        source_table=str(data["source_table"]),
        media_row_id=str(data["media_row_id"]),
        lesson_id=str(data["lesson_id"]) if data.get("lesson_id") is not None else None,
        lesson_title=(
            str(data["lesson_title"]) if data.get("lesson_title") is not None else None
        ),
        kind=str(data["kind"]) if data.get("kind") is not None else None,
        content_type=(
            str(data["content_type"]) if data.get("content_type") is not None else None
        ),
        storage_bucket=(
            str(data["storage_bucket"]) if data.get("storage_bucket") is not None else None
        ),
        storage_path=(
            str(data["storage_path"]) if data.get("storage_path") is not None else None
        ),
    )


def fetch_audio_rows(conn: psycopg.Connection[Any]) -> list[AudioContentRow]:
    queries = (
        """
        SELECT
          'app.media_objects' AS source_table,
          mo.id::text AS media_row_id,
          min(lm.lesson_id::text) FILTER (
            WHERE lower(coalesce(lm.kind, '')) = 'audio'
          ) AS lesson_id,
          coalesce(
            min(nullif(btrim(hpu.title), '')) FILTER (
              WHERE lower(coalesce(hpu.kind, '')) = 'audio'
            ),
            min(nullif(btrim(l.lesson_title), '')) FILTER (
              WHERE lower(coalesce(lm.kind, '')) = 'audio'
            ),
            nullif(btrim(mo.original_name), '')
          ) AS lesson_title,
          'audio' AS kind,
          mo.content_type,
          mo.storage_bucket,
          mo.storage_path
        FROM app.media_objects mo
        LEFT JOIN app.lesson_media lm ON lm.media_id = mo.id
        LEFT JOIN app.lessons l ON l.id = lm.lesson_id
        LEFT JOIN app.home_player_uploads hpu ON hpu.media_id = mo.id
        WHERE lower(coalesce(lm.kind, '')) = 'audio'
           OR lower(coalesce(hpu.kind, '')) = 'audio'
        GROUP BY
          mo.id,
          mo.content_type,
          mo.storage_bucket,
          mo.storage_path,
          mo.original_name
        ORDER BY mo.id::text
        """,
        """
        SELECT
          'app.media_assets' AS source_table,
          ma.id::text AS media_row_id,
          min(coalesce(ma.lesson_id, lm.lesson_id)::text) FILTER (
            WHERE coalesce(ma.lesson_id, lm.lesson_id) IS NOT NULL
          ) AS lesson_id,
          coalesce(
            min(nullif(btrim(hpu.title), '')) FILTER (
              WHERE lower(coalesce(hpu.kind, '')) = 'audio'
            ),
            min(nullif(btrim(l.lesson_title), '')),
            nullif(btrim(ma.original_filename), '')
          ) AS lesson_title,
          'audio' AS kind,
          ma.original_content_type AS content_type,
          ma.storage_bucket,
          ma.original_object_path AS storage_path
        FROM app.media_assets ma
        LEFT JOIN app.lesson_media lm ON lm.media_asset_id = ma.id
        LEFT JOIN app.lessons l ON l.id = coalesce(ma.lesson_id, lm.lesson_id)
        LEFT JOIN app.home_player_uploads hpu ON hpu.media_asset_id = ma.id
        WHERE lower(coalesce(ma.media_type, '')) = 'audio'
        GROUP BY
          ma.id,
          ma.original_content_type,
          ma.storage_bucket,
          ma.original_object_path,
          ma.original_filename
        ORDER BY ma.id::text
        """,
        """
        SELECT
          'app.lesson_media' AS source_table,
          lm.id::text AS media_row_id,
          lm.lesson_id::text AS lesson_id,
          nullif(btrim(l.lesson_title), '') AS lesson_title,
          lm.kind,
          NULL::text AS content_type,
          coalesce(lm.storage_bucket, 'lesson-media') AS storage_bucket,
          lm.storage_path
        FROM app.lesson_media lm
        LEFT JOIN app.lessons l ON l.id = lm.lesson_id
        LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
        WHERE lower(coalesce(lm.kind, '')) = 'audio'
          AND lm.media_asset_id IS NULL
          AND mo.id IS NULL
        ORDER BY lm.id::text
        """,
    )

    rows: list[AudioContentRow] = []
    with conn.cursor(row_factory=dict_row) as cur:
        for query in queries:
            cur.execute(query)
            rows.extend(_row_from_mapping(dict(row)) for row in cur.fetchall())
    return rows


def _proposed_content_type(
    *,
    row: AudioContentRow,
    normalized_content_type: str | None,
    mapped_content_type: str | None,
) -> str | None:
    if row.source_table not in UPDATE_TARGETS:
        return None
    if mapped_content_type is None:
        return None
    if normalized_content_type is None:
        return mapped_content_type
    if normalized_content_type in GENERIC_BINARY_CONTENT_TYPES:
        return mapped_content_type
    if not normalized_content_type.startswith("audio/"):
        return mapped_content_type
    return None


def classify_audio_row(row: AudioContentRow) -> AudioContentIssue | None:
    normalized_content_type = normalize_content_type(row.content_type)
    detected_extension = detect_extension(row.storage_path)
    mapped_content_type = audio_content_type_from_extension(detected_extension)

    issue_type: str | None = None
    if normalized_content_type is None:
        issue_type = "missing_content_type"
    elif not normalized_content_type.startswith("audio/"):
        issue_type = "non_audio_content_type"
    elif normalized_content_type not in SUPPORTED_AUDIO_CONTENT_TYPES:
        issue_type = "unsupported_audio_content_type"
    elif detected_extension is not None:
        if mapped_content_type is None:
            issue_type = "suspicious_extension_mismatch"
        elif mapped_content_type != normalized_content_type:
            issue_type = "suspicious_extension_mismatch"

    if issue_type is None:
        return None

    proposed_content_type = _proposed_content_type(
        row=row,
        normalized_content_type=normalized_content_type,
        mapped_content_type=mapped_content_type,
    )
    return AudioContentIssue(
        source_table=row.source_table,
        media_row_id=row.media_row_id,
        lesson_id=row.lesson_id,
        lesson_title=row.lesson_title,
        kind=row.kind,
        content_type=row.content_type,
        storage_bucket=row.storage_bucket,
        storage_path=row.storage_path,
        detected_extension=detected_extension,
        issue_type=issue_type,
        proposed_content_type=proposed_content_type,
        can_apply=proposed_content_type is not None,
    )


def build_scan_report(rows: Sequence[AudioContentRow]) -> AudioScanReport:
    issues: list[AudioContentIssue] = []
    updates: list[AudioContentUpdate] = []

    for row in rows:
        issue = classify_audio_row(row)
        if issue is None:
            continue
        issues.append(issue)
        if issue.proposed_content_type is None:
            continue
        column = UPDATE_TARGETS.get(issue.source_table)
        if column is None:
            continue
        updates.append(
            AudioContentUpdate(
                source_table=issue.source_table,
                media_row_id=issue.media_row_id,
                content_type_column=column,
                content_type=issue.proposed_content_type,
            )
        )

    summary = {
        "total_audio_rows": len(rows),
        "rows_with_issues": len(issues),
        "missing_content_type": sum(
            1 for issue in issues if issue.issue_type == "missing_content_type"
        ),
        "non_audio_content_type": sum(
            1 for issue in issues if issue.issue_type == "non_audio_content_type"
        ),
        "suspicious_extension_mismatch": sum(
            1
            for issue in issues
            if issue.issue_type == "suspicious_extension_mismatch"
        ),
        "unsupported_audio_content_type": sum(
            1
            for issue in issues
            if issue.issue_type == "unsupported_audio_content_type"
        ),
        "safe_auto_fix_rows": len(updates),
        "manual_review_rows": len(issues) - len(updates),
    }
    return AudioScanReport(
        rows=list(rows),
        issues=issues,
        updates=updates,
        summary=summary,
    )


def apply_updates(
    conn: psycopg.Connection[Any],
    updates: Sequence[AudioContentUpdate],
) -> int:
    total_updated = 0
    with conn.cursor() as cur:
        for update in updates:
            column = UPDATE_TARGETS.get(update.source_table)
            if column is None:
                continue
            cur.execute(
                f"""
                UPDATE {update.source_table}
                SET {column} = %s,
                    updated_at = now()
                WHERE id = %s
                """,
                (update.content_type, update.media_row_id),
            )
            total_updated += int(cur.rowcount or 0)
    conn.commit()
    return total_updated


def _print_issues(issues: Sequence[AudioContentIssue]) -> None:
    for issue in issues:
        record = asdict(issue)
        print("ISSUE", record)


def _print_updates(
    *,
    report: AudioScanReport,
    applied: bool,
) -> None:
    updates_by_row = {
        (update.source_table, update.media_row_id): update for update in report.updates
    }
    prefix = "UPDATED" if applied else "WOULD_UPDATE"
    for issue in report.issues:
        update = updates_by_row.get((issue.source_table, issue.media_row_id))
        if update is None:
            continue
        print(
            prefix,
            {
                "source_table": update.source_table,
                "media_row_id": update.media_row_id,
                "content_type_column": update.content_type_column,
                "from_content_type": issue.content_type,
                "to_content_type": update.content_type,
                "detected_extension": issue.detected_extension,
            },
        )


def _print_summary(summary: dict[str, int]) -> None:
    print("Summary:")
    for key in (
        "total_audio_rows",
        "rows_with_issues",
        "missing_content_type",
        "non_audio_content_type",
        "suspicious_extension_mismatch",
        "unsupported_audio_content_type",
        "safe_auto_fix_rows",
        "manual_review_rows",
    ):
        print(f"  {key}: {summary[key]}")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    database_url = _ensure_db_url(args.database_url)
    if not database_url:
        print(
            "Missing database URL. Set DATABASE_URL or SUPABASE_DB_URL, or pass --database-url.",
            file=sys.stderr,
        )
        return 2

    try:
        with psycopg.connect(database_url, row_factory=dict_row) as conn:
            rows = fetch_audio_rows(conn)
            report = build_scan_report(rows)
            print(f"Mode: {'apply' if args.apply else 'dry-run'}")
            _print_issues(report.issues)
            if args.apply:
                _print_updates(report=report, applied=False)
                updated = apply_updates(conn, report.updates)
                print(f"Applied updates: {updated}")
                _print_updates(report=report, applied=True)
            else:
                _print_updates(report=report, applied=False)
            _print_summary(report.summary)
    except psycopg.OperationalError as exc:
        print(f"Database connection failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
