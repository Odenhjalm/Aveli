#!/usr/bin/env python3
"""Media robustness auditor + migration tooling (Plan B).

This script is intentionally conservative:
- Default is dry-run (no DB writes).
- Use --apply to persist changes.
- No media is ever deleted (DB rows or Storage objects).

Primary outputs (deterministic):
- JSON report (machine-readable)
- Markdown report (human-readable)

Scope:
- Legacy lesson media (app.lesson_media + app.media_objects)
- Pipeline lesson media (app.lesson_media.media_asset_id + app.media_assets)
- Orphan detection for app.media_assets / app.media_objects (DB-level)
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence
from urllib.parse import urlparse

import psycopg
from psycopg import errors


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.utils.media_robustness import (  # noqa: E402
    MediaCategory,
    MediaRecommendedAction,
    MediaStatus,
    SUPPORTED_MEDIA_KINDS,
    normalize_media_kind,
    recommended_action_for_status,
)


DEFAULT_BUCKETS: tuple[str, ...] = ("course-media", "public-media", "lesson-media")
PUBLIC_BUCKETS: tuple[str, ...] = ("public-media", "users", "avatars", "hero", "logos")


@dataclass(frozen=True, slots=True)
class LegacyLessonMediaRow:
    lesson_media_id: str
    kind: str
    media_object_id: str | None
    lesson_storage_bucket: str | None
    lesson_storage_path: str | None
    object_storage_bucket: str | None
    object_storage_path: str | None
    content_type: str | None
    original_name: str | None


@dataclass(frozen=True, slots=True)
class PipelineLessonMediaRow:
    lesson_media_id: str
    kind: str
    media_asset_id: str
    media_state: str | None
    storage_bucket: str | None
    original_object_path: str | None
    streaming_object_path: str | None
    original_filename: str | None
    error_message: str | None


@dataclass(frozen=True, slots=True)
class OrphanMediaAssetRow:
    media_asset_id: str
    media_state: str | None
    storage_bucket: str | None
    original_object_path: str | None
    streaming_object_path: str | None
    original_filename: str | None
    error_message: str | None


@dataclass(frozen=True, slots=True)
class OrphanMediaObjectRow:
    media_object_id: str
    storage_bucket: str | None
    storage_path: str | None
    content_type: str | None
    original_name: str | None
    byte_size: int | None


@dataclass(frozen=True, slots=True)
class ProposedUpdate:
    table: str
    id: str
    fields: dict[str, Any]


@dataclass(frozen=True, slots=True)
class MediaReportRecord:
    category: str
    status: str
    recommended_action: str
    resolvable_for_editor: bool
    resolvable_for_student: bool
    lesson_media_id: str | None
    media_id: str | None
    kind: str | None
    storage_bucket: str | None
    storage_path: str | None
    bytes_exist: bool | None
    issue_reason: str | None
    issue_details: dict[str, Any] | None
    proposed_updates: list[ProposedUpdate]


def _ensure_db_url(url: str | None) -> str | None:
    if not url:
        return None
    if "sslmode=" in url:
        return url
    if "localhost" in url or "127.0.0.1" in url:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}sslmode=require"


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit and optionally repair media robustness issues.")
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL") or os.getenv("SUPABASE_DB_URL"),
        help="Postgres connection string (default: $DATABASE_URL or $SUPABASE_DB_URL).",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply fixes (default is dry-run).",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=200,
        help="Transaction batch size when applying (default: %(default)s).",
    )
    parser.add_argument(
        "--limit-legacy",
        type=int,
        default=None,
        help="Limit number of legacy lesson_media rows scanned (default: no limit).",
    )
    parser.add_argument(
        "--limit-pipeline",
        type=int,
        default=None,
        help="Limit number of pipeline lesson_media rows scanned (default: no limit).",
    )
    parser.add_argument(
        "--buckets",
        default=",".join(DEFAULT_BUCKETS),
        help="Comma-separated bucket ids to consider when normalizing bucket/key drift.",
    )
    parser.add_argument(
        "--no-orphans",
        action="store_true",
        help="Exclude orphaned media_assets/media_objects from the report.",
    )
    parser.add_argument(
        "--orphans-limit",
        type=int,
        default=5000,
        help="Limit orphan rows per table (default: %(default)s).",
    )
    parser.add_argument(
        "--output-dir",
        default=".",
        help="Output directory for report files (default: current directory).",
    )
    parser.add_argument(
        "--json-out",
        default="media_robustness_report.json",
        help="JSON report filename or '-' for stdout (default: %(default)s).",
    )
    parser.add_argument(
        "--md-out",
        default="media_robustness_report.md",
        help="Markdown report filename or '-' for stdout (default: %(default)s).",
    )
    return parser.parse_args(argv)


def _normalize_bucket(value: str | None) -> str | None:
    normalized = (value or "").strip().strip("/")
    return normalized or None


def _normalize_path(value: str | None) -> str | None:
    if value is None:
        return None
    raw = str(value).strip()
    parsed = urlparse(raw)
    if parsed.scheme in {"http", "https"} and parsed.path:
        raw = parsed.path
    normalized = raw.replace("\\", "/").lstrip("/")
    for prefix in (
        "api/files/",
        "storage/v1/object/public/",
        "storage/v1/object/sign/",
        "object/public/",
        "object/sign/",
    ):
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix) :].lstrip("/")
            break
    return normalized or None


def _strip_prefix(path: str, prefix: str) -> str:
    prefix_norm = prefix.strip().strip("/")
    if not prefix_norm:
        return path
    token = f"{prefix_norm}/"
    if path.startswith(token):
        stripped = path[len(token) :].lstrip("/")
        return stripped or path
    return path


def _detect_kind(content_type: str | None, filename_hint: str | None) -> str:
    mime = (content_type or "").strip().lower()
    if mime.startswith("image/"):
        return "image"
    if mime.startswith("video/"):
        return "video"
    if mime.startswith("audio/"):
        return "audio"
    if mime == "application/pdf":
        return "pdf"

    name = (filename_hint or "").strip()
    suffix = Path(name).suffix.lower()
    if suffix in {".png", ".jpg", ".jpeg", ".webp", ".gif"}:
        return "image"
    if suffix in {".mp4", ".mov", ".webm"}:
        return "video"
    if suffix in {".mp3", ".wav", ".m4a", ".aac", ".ogg"}:
        return "audio"
    if suffix == ".pdf":
        return "pdf"
    return "other"


def _guess_content_type(filename_hint: str | None) -> str | None:
    name = (filename_hint or "").strip()
    if not name:
        return None
    guessed, _ = mimetypes.guess_type(name)
    return guessed or None


def fetch_legacy_lesson_media_rows(
    conn: psycopg.Connection,
    *,
    limit: int | None,
) -> list[LegacyLessonMediaRow]:
    params: list[Any] = []
    if limit is not None and limit > 0:
        limit_sql = " LIMIT %s"
        params.append(int(limit))
    else:
        limit_sql = ""

    query = f"""
        SELECT
          lm.id AS lesson_media_id,
          lm.kind,
          lm.media_id AS media_object_id,
          lm.storage_bucket AS lesson_storage_bucket,
          lm.storage_path AS lesson_storage_path,
          mo.storage_bucket AS object_storage_bucket,
          mo.storage_path AS object_storage_path,
          mo.content_type,
          mo.original_name
        FROM app.lesson_media lm
        LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
        WHERE lm.media_asset_id IS NULL
        ORDER BY lm.id ASC
        {limit_sql}
    """

    rows: list[LegacyLessonMediaRow] = []
    with conn.cursor() as cur:
        cur.execute(query, params)
        for (
            lesson_media_id,
            kind,
            media_object_id,
            lesson_storage_bucket,
            lesson_storage_path,
            object_storage_bucket,
            object_storage_path,
            content_type,
            original_name,
        ) in cur.fetchall():
            rows.append(
                LegacyLessonMediaRow(
                    lesson_media_id=str(lesson_media_id),
                    kind=str(kind or ""),
                    media_object_id=str(media_object_id) if media_object_id is not None else None,
                    lesson_storage_bucket=str(lesson_storage_bucket) if lesson_storage_bucket is not None else None,
                    lesson_storage_path=str(lesson_storage_path) if lesson_storage_path is not None else None,
                    object_storage_bucket=str(object_storage_bucket) if object_storage_bucket is not None else None,
                    object_storage_path=str(object_storage_path) if object_storage_path is not None else None,
                    content_type=str(content_type) if content_type is not None else None,
                    original_name=str(original_name) if original_name is not None else None,
                )
            )
    return rows


def fetch_pipeline_lesson_media_rows(
    conn: psycopg.Connection,
    *,
    limit: int | None,
) -> list[PipelineLessonMediaRow]:
    params: list[Any] = []
    if limit is not None and limit > 0:
        limit_sql = " LIMIT %s"
        params.append(int(limit))
    else:
        limit_sql = ""

    query = f"""
        SELECT
          lm.id AS lesson_media_id,
          lm.kind,
          lm.media_asset_id AS media_asset_id,
          ma.state AS media_state,
          ma.storage_bucket,
          ma.original_object_path,
          ma.streaming_object_path,
          ma.original_filename,
          ma.error_message
        FROM app.lesson_media lm
        LEFT JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        WHERE lm.media_asset_id IS NOT NULL
        ORDER BY lm.id ASC
        {limit_sql}
    """

    rows: list[PipelineLessonMediaRow] = []
    with conn.cursor() as cur:
        cur.execute(query, params)
        for (
            lesson_media_id,
            kind,
            media_asset_id,
            media_state,
            storage_bucket,
            original_object_path,
            streaming_object_path,
            original_filename,
            error_message,
        ) in cur.fetchall():
            if media_asset_id is None:
                continue
            rows.append(
                PipelineLessonMediaRow(
                    lesson_media_id=str(lesson_media_id),
                    kind=str(kind or ""),
                    media_asset_id=str(media_asset_id),
                    media_state=str(media_state) if media_state is not None else None,
                    storage_bucket=str(storage_bucket) if storage_bucket is not None else None,
                    original_object_path=str(original_object_path) if original_object_path is not None else None,
                    streaming_object_path=str(streaming_object_path) if streaming_object_path is not None else None,
                    original_filename=str(original_filename) if original_filename is not None else None,
                    error_message=str(error_message) if error_message is not None else None,
                )
            )
    return rows


def fetch_orphan_media_assets(
    conn: psycopg.Connection,
    *,
    limit: int,
) -> list[OrphanMediaAssetRow]:
    resolved_limit = max(1, int(limit))
    query = """
        SELECT
          ma.id AS media_asset_id,
          ma.state AS media_state,
          ma.storage_bucket,
          ma.original_object_path,
          ma.streaming_object_path,
          ma.original_filename,
          ma.error_message
        FROM app.media_assets ma
        LEFT JOIN app.lesson_media lm ON lm.media_asset_id = ma.id
        LEFT JOIN app.courses c ON c.cover_media_id = ma.id
        LEFT JOIN app.home_player_uploads hpu ON hpu.media_asset_id = ma.id
        WHERE lm.id IS NULL
          AND c.id IS NULL
          AND hpu.id IS NULL
        ORDER BY ma.id ASC
        LIMIT %s
    """

    rows: list[OrphanMediaAssetRow] = []
    with conn.cursor() as cur:
        cur.execute(query, (resolved_limit,))
        for (
            media_asset_id,
            media_state,
            storage_bucket,
            original_object_path,
            streaming_object_path,
            original_filename,
            error_message,
        ) in cur.fetchall():
            rows.append(
                OrphanMediaAssetRow(
                    media_asset_id=str(media_asset_id),
                    media_state=str(media_state) if media_state is not None else None,
                    storage_bucket=str(storage_bucket) if storage_bucket is not None else None,
                    original_object_path=str(original_object_path) if original_object_path is not None else None,
                    streaming_object_path=str(streaming_object_path) if streaming_object_path is not None else None,
                    original_filename=str(original_filename) if original_filename is not None else None,
                    error_message=str(error_message) if error_message is not None else None,
                )
            )
    return rows


def fetch_orphan_media_objects(
    conn: psycopg.Connection,
    *,
    limit: int,
) -> list[OrphanMediaObjectRow]:
    resolved_limit = max(1, int(limit))
    has_events_table = False
    with conn.cursor() as cur:
        cur.execute("SELECT to_regclass('app.events') IS NOT NULL")
        row = cur.fetchone()
        has_events_table = bool(row[0]) if row else False

    joins = [
        "FROM app.media_objects mo",
        "LEFT JOIN app.lesson_media lm ON lm.media_id = mo.id",
        "LEFT JOIN app.home_player_uploads hpu ON hpu.media_id = mo.id",
        "LEFT JOIN app.teacher_profile_media tpm ON tpm.cover_media_id = mo.id",
        "LEFT JOIN app.profiles p ON p.avatar_media_id = mo.id",
        "LEFT JOIN app.meditations m ON m.media_id = mo.id",
    ]
    where_clauses = [
        "WHERE lm.id IS NULL",
        "  AND hpu.id IS NULL",
        "  AND tpm.id IS NULL",
        "  AND p.user_id IS NULL",
        "  AND m.id IS NULL",
    ]
    if has_events_table:
        joins.append("LEFT JOIN app.events e ON e.image_id = mo.id")
        where_clauses.append("  AND e.id IS NULL")

    joins_sql = "\n".join(joins)
    where_sql = "\n".join(where_clauses)

    query = f"""
        SELECT
          mo.id AS media_object_id,
          mo.storage_bucket,
          mo.storage_path,
          mo.content_type,
          mo.original_name,
          mo.byte_size
        {joins_sql}
        {where_sql}
        ORDER BY mo.id ASC
        LIMIT %s
    """

    rows: list[OrphanMediaObjectRow] = []
    with conn.cursor() as cur:
        cur.execute(query, (resolved_limit,))
        for (
            media_object_id,
            storage_bucket,
            storage_path,
            content_type,
            original_name,
            byte_size,
        ) in cur.fetchall():
            rows.append(
                OrphanMediaObjectRow(
                    media_object_id=str(media_object_id),
                    storage_bucket=str(storage_bucket) if storage_bucket is not None else None,
                    storage_path=str(storage_path) if storage_path is not None else None,
                    content_type=str(content_type) if content_type is not None else None,
                    original_name=str(original_name) if original_name is not None else None,
                    byte_size=int(byte_size) if byte_size is not None else None,
                )
            )
    return rows


def _candidate_pairs_for_storage_ref(
    *,
    storage_bucket: str | None,
    storage_path: str | None,
    buckets: set[str],
) -> list[tuple[str, str]]:
    bucket = _normalize_bucket(storage_bucket)
    path = _normalize_path(storage_path)
    if not path:
        return []

    derived_bucket = bucket
    prefix_bucket = path.split("/", 1)[0]
    if not derived_bucket and prefix_bucket in buckets:
        derived_bucket = prefix_bucket

    pairs: list[tuple[str, str]] = []

    def add(b: str, p: str) -> None:
        pair = (b, p)
        if pair not in pairs:
            pairs.append(pair)

    # Primary bucket (explicit or derived), prefer bucket-relative key when bucket is redundantly prefixed.
    if derived_bucket:
        stripped = _strip_prefix(path, derived_bucket)
        if stripped != path:
            add(derived_bucket, stripped)
        add(derived_bucket, path)

    # Bucket mismatch heuristic: if the path starts with a known bucket id, try that too.
    if prefix_bucket in buckets and prefix_bucket != derived_bucket:
        prefix_stripped = _strip_prefix(path, prefix_bucket)
        if prefix_stripped != path:
            add(prefix_bucket, prefix_stripped)
        add(prefix_bucket, path)

    return pairs


def fetch_storage_existence(
    conn: psycopg.Connection,
    pairs: Iterable[tuple[str, str]],
) -> tuple[dict[tuple[str, str], bool], bool]:
    unique_pairs = sorted({(b, p) for b, p in pairs if b and p})
    if not unique_pairs:
        return {}, True

    placeholders = ", ".join(["(%s, %s)"] * len(unique_pairs))
    params: list[Any] = []
    for bucket, name in unique_pairs:
        params.extend([bucket, name])

    query = f"""
        WITH candidates(bucket_id, name) AS (
          VALUES {placeholders}
        )
        SELECT c.bucket_id, c.name, (o.id IS NOT NULL) AS exists
        FROM candidates c
        LEFT JOIN storage.objects o
          ON o.bucket_id = c.bucket_id
         AND o.name = c.name
    """
    existence: dict[tuple[str, str], bool] = {}
    try:
        with conn.cursor() as cur:
            cur.execute(query, params)
            for bucket_id, name, exists in cur.fetchall():
                existence[(str(bucket_id), str(name))] = bool(exists)
        return existence, True
    except errors.UndefinedTable:
        return {}, False


def _resolve_best_storage_candidate(
    *,
    storage_bucket: str | None,
    storage_path: str | None,
    buckets: set[str],
    existence: dict[tuple[str, str], bool],
    storage_table_available: bool,
) -> tuple[str | None, str | None, str | None, bool | None, list[dict[str, str]]]:
    normalized_bucket = _normalize_bucket(storage_bucket)
    normalized_path = _normalize_path(storage_path)
    if not normalized_path:
        return None, None, "unsupported", None, []

    candidates = _candidate_pairs_for_storage_ref(
        storage_bucket=normalized_bucket,
        storage_path=normalized_path,
        buckets=buckets,
    )
    candidate_details = [{"bucket": b, "key": k} for b, k in candidates]
    if not storage_table_available:
        return normalized_bucket, normalized_path, "manual_review", None, candidate_details

    exists_map = {pair: existence.get(pair, False) for pair in candidates}

    # 1) Same bucket: prefer stripped key if it exists.
    if normalized_bucket:
        stripped_key = _strip_prefix(normalized_path, normalized_bucket)
        if stripped_key != normalized_path and exists_map.get((normalized_bucket, stripped_key)):
            return (
                normalized_bucket,
                stripped_key,
                "key_format_drift",
                True,
                candidate_details,
            )
        if exists_map.get((normalized_bucket, normalized_path)):
            # Detect "unfixable" drift: key is bucket-prefixed and the canonical key does not exist.
            if normalized_path.startswith(f"{normalized_bucket}/"):
                return (
                    normalized_bucket,
                    normalized_path,
                    "manual_review",
                    True,
                    candidate_details,
                )
            return (
                normalized_bucket,
                normalized_path,
                None,
                True,
                candidate_details,
            )

    # 2) Alternate bucket if path prefix suggests mismatch.
    prefix_bucket = normalized_path.split("/", 1)[0]
    if prefix_bucket in buckets and prefix_bucket != normalized_bucket:
        prefix_stripped = _strip_prefix(normalized_path, prefix_bucket)
        if exists_map.get((prefix_bucket, prefix_stripped)):
            return (
                prefix_bucket,
                prefix_stripped,
                "bucket_mismatch",
                True,
                candidate_details,
            )
        if exists_map.get((prefix_bucket, normalized_path)):
            return (
                prefix_bucket,
                normalized_path,
                "bucket_mismatch",
                True,
                candidate_details,
            )

    return (
        normalized_bucket,
        normalized_path,
        "missing_object",
        False,
        candidate_details,
    )


def _proposed_updates_for_legacy_row(
    row: LegacyLessonMediaRow,
    *,
    resolved_bucket: str | None,
    resolved_key: str | None,
    issue_reason: str | None,
    issue_details: dict[str, Any] | None,
    bytes_exist: bool | None,
    storage_table_available: bool,
) -> list[ProposedUpdate]:
    updates: list[ProposedUpdate] = []

    # Target storage reference mirrors runtime coalesce: prefer media_objects when present.
    target_table = "app.lesson_media"
    target_id = row.lesson_media_id
    current_bucket = row.lesson_storage_bucket
    current_path = row.lesson_storage_path
    if row.media_object_id and row.object_storage_path:
        target_table = "app.media_objects"
        target_id = row.media_object_id
        current_bucket = row.object_storage_bucket
        current_path = row.object_storage_path

    current_bucket_norm = _normalize_bucket(current_bucket)
    current_path_norm = _normalize_path(current_path)

    # Only propose bucket/path rewrites when:
    # - storage.objects is available
    # - bytes existence was confirmed
    # - we resolved to a specific candidate
    # - and the reason is a fixable drift (not a manual_review)
    if (
        storage_table_available
        and bytes_exist is True
        and resolved_bucket
        and resolved_key
        and issue_reason in {"bucket_mismatch", "key_format_drift"}
    ):
        storage_fields: dict[str, Any] = {}
        if resolved_bucket != current_bucket_norm:
            storage_fields["storage_bucket"] = resolved_bucket
        if current_path_norm and resolved_key != current_path_norm:
            storage_fields["storage_path"] = resolved_key
        if storage_fields:
            updates.append(ProposedUpdate(table=target_table, id=target_id, fields=storage_fields))

    # Metadata backfill (best-effort, never destructive).
    filename_hint = row.original_name or (current_path_norm or "")
    derived_kind = _detect_kind(row.content_type, filename_hint)
    kind_normalized = normalize_media_kind(row.kind)
    if kind_normalized == "other" and derived_kind in SUPPORTED_MEDIA_KINDS:
        updates.append(
            ProposedUpdate(
                table="app.lesson_media",
                id=row.lesson_media_id,
                fields={"kind": derived_kind},
            )
        )

    if target_table == "app.media_objects" and target_id:
        if (row.content_type or "").strip() == "":
            guessed = _guess_content_type(filename_hint)
            if guessed:
                updates.append(
                    ProposedUpdate(
                        table="app.media_objects",
                        id=target_id,
                        fields={"content_type": guessed},
                    )
                )

    # Persist only "hard" issues (bytes missing / unsupported refs).
    if issue_reason in {"missing_object", "unsupported"} and issue_details is not None:
        updates.append(
            ProposedUpdate(
                table="app.lesson_media_issues",
                id=row.lesson_media_id,
                fields={
                    "issue": issue_reason,
                    "details": issue_details,
                },
            )
        )

    return updates


def build_legacy_records(
    rows: Sequence[LegacyLessonMediaRow],
    *,
    existence: dict[tuple[str, str], bool],
    buckets: set[str],
    storage_table_available: bool,
) -> list[MediaReportRecord]:
    records: list[MediaReportRecord] = []

    for row in rows:
        storage_bucket = row.object_storage_bucket or row.lesson_storage_bucket
        storage_path = row.object_storage_path or row.lesson_storage_path

        (
            resolved_bucket,
            resolved_key,
            issue_reason,
            bytes_exist,
            candidate_details,
        ) = _resolve_best_storage_candidate(
            storage_bucket=storage_bucket,
            storage_path=storage_path,
            buckets=buckets,
            existence=existence,
            storage_table_available=storage_table_available,
        )

        kind = normalize_media_kind(row.kind)
        supported_kind = kind in SUPPORTED_MEDIA_KINDS

        category = MediaCategory.legacy_lesson_media
        status: MediaStatus

        if issue_reason == "manual_review":
            status = MediaStatus.manual_review
        elif not supported_kind:
            status = MediaStatus.unsupported
            issue_reason = "unsupported"
        elif issue_reason == "missing_object" or bytes_exist is False:
            status = MediaStatus.missing_bytes
            issue_reason = "missing_object"
        elif issue_reason in {"bucket_mismatch", "key_format_drift"}:
            status = MediaStatus.needs_migration
        else:
            status = MediaStatus.ok_legacy

        recommended_action = recommended_action_for_status(status)

        # Invariants: only "resolvable" when bytes exist and kind is supported.
        resolvable = bool(bytes_exist) and supported_kind

        issue_details: dict[str, Any] | None = None
        if issue_reason:
            issue_details = {
                "storage_bucket": _normalize_bucket(storage_bucket),
                "storage_path": _normalize_path(storage_path),
                "resolved_bucket": resolved_bucket,
                "resolved_key": resolved_key,
                "candidates": candidate_details,
            }

        proposed_updates = _proposed_updates_for_legacy_row(
            row,
            resolved_bucket=resolved_bucket,
            resolved_key=resolved_key,
            issue_reason=issue_reason,
            issue_details=issue_details,
            bytes_exist=bytes_exist,
            storage_table_available=storage_table_available,
        )

        records.append(
            MediaReportRecord(
                category=str(category),
                status=str(status),
                recommended_action=str(recommended_action),
                resolvable_for_editor=resolvable,
                resolvable_for_student=resolvable,
                lesson_media_id=row.lesson_media_id,
                media_id=row.media_object_id,
                kind=kind,
                storage_bucket=resolved_bucket or _normalize_bucket(storage_bucket),
                storage_path=resolved_key or _normalize_path(storage_path),
                bytes_exist=bytes_exist,
                issue_reason=issue_reason,
                issue_details=issue_details,
                proposed_updates=proposed_updates,
            )
        )

    records.sort(
        key=lambda r: (
            r.category,
            r.status,
            r.lesson_media_id or "",
            r.media_id or "",
        )
    )
    return records


def build_pipeline_records(
    rows: Sequence[PipelineLessonMediaRow],
    *,
    existence: dict[tuple[str, str], bool],
    storage_table_available: bool,
) -> list[MediaReportRecord]:
    records: list[MediaReportRecord] = []

    for row in rows:
        category = MediaCategory.pipeline_media_asset
        kind = normalize_media_kind(row.kind)
        supported_kind = kind in SUPPORTED_MEDIA_KINDS or kind == "audio"

        state = (row.media_state or "").strip().lower()
        bucket = _normalize_bucket(row.storage_bucket)
        key = _normalize_path(row.streaming_object_path)

        bytes_exist: bool | None = None
        if storage_table_available and bucket and key:
            bytes_exist = bool(existence.get((bucket, key), False))

        status: MediaStatus
        issue_reason: str | None = None

        if not supported_kind:
            status = MediaStatus.unsupported
            issue_reason = "unsupported"
        elif state == "ready" and bucket and key and bytes_exist is True:
            status = MediaStatus.ok
        elif state == "ready" and bucket and key and bytes_exist is False:
            status = MediaStatus.missing_bytes
            issue_reason = "missing_object"
        elif state == "failed":
            status = MediaStatus.unsupported
            issue_reason = "pipeline_failed"
        elif not storage_table_available:
            status = MediaStatus.manual_review
            issue_reason = "manual_review"
        else:
            # uploaded/processing – not yet playable but not necessarily broken.
            status = MediaStatus.ok
            issue_reason = "processing"

        recommended_action: MediaRecommendedAction
        if issue_reason == "processing":
            recommended_action = MediaRecommendedAction.keep
        else:
            recommended_action = recommended_action_for_status(status)

        resolvable = (
            status == MediaStatus.ok
            and state == "ready"
            and bool(bytes_exist)
            and supported_kind
        )

        issue_details: dict[str, Any] | None = None
        if issue_reason:
            issue_details = {
                "media_state": row.media_state,
                "storage_bucket": bucket,
                "streaming_object_path": key,
                "error_message": row.error_message,
            }

        records.append(
            MediaReportRecord(
                category=str(category),
                status=str(status),
                recommended_action=str(recommended_action),
                resolvable_for_editor=resolvable,
                resolvable_for_student=resolvable,
                lesson_media_id=row.lesson_media_id,
                media_id=row.media_asset_id,
                kind=kind,
                storage_bucket=bucket,
                storage_path=key,
                bytes_exist=bytes_exist,
                issue_reason=issue_reason,
                issue_details=issue_details,
                proposed_updates=[],
            )
        )

    records.sort(
        key=lambda r: (
            r.category,
            r.status,
            r.lesson_media_id or "",
            r.media_id or "",
        )
    )
    return records


def build_orphan_asset_records(
    rows: Sequence[OrphanMediaAssetRow],
    *,
    existence: dict[tuple[str, str], bool],
    storage_table_available: bool,
) -> list[MediaReportRecord]:
    records: list[MediaReportRecord] = []
    for row in rows:
        bucket = _normalize_bucket(row.storage_bucket)
        key = _normalize_path(row.streaming_object_path) or _normalize_path(row.original_object_path)
        bytes_exist: bool | None = None
        if storage_table_available and bucket and key:
            bytes_exist = bool(existence.get((bucket, key), False))
        records.append(
            MediaReportRecord(
                category=str(MediaCategory.orphan),
                status=str(MediaStatus.orphaned),
                recommended_action=str(MediaRecommendedAction.safe_to_delete),
                resolvable_for_editor=False,
                resolvable_for_student=False,
                lesson_media_id=None,
                media_id=row.media_asset_id,
                kind=None,
                storage_bucket=bucket,
                storage_path=key,
                bytes_exist=bytes_exist,
                issue_reason="orphaned_asset",
                issue_details={
                    "media_state": row.media_state,
                    "original_object_path": row.original_object_path,
                    "streaming_object_path": row.streaming_object_path,
                    "error_message": row.error_message,
                },
                proposed_updates=[],
            )
        )
    records.sort(key=lambda r: (r.media_id or ""))
    return records


def build_orphan_object_records(
    rows: Sequence[OrphanMediaObjectRow],
    *,
    existence: dict[tuple[str, str], bool],
    buckets: set[str],
    storage_table_available: bool,
) -> list[MediaReportRecord]:
    records: list[MediaReportRecord] = []
    for row in rows:
        bucket = _normalize_bucket(row.storage_bucket)
        key = _normalize_path(row.storage_path)
        bytes_exist: bool | None = None
        if storage_table_available and bucket and key:
            bytes_exist = bool(existence.get((bucket, key), False))
        if storage_table_available and bytes_exist is None and key:
            derived_bucket = key.split("/", 1)[0]
            if derived_bucket in buckets:
                derived_key = _strip_prefix(key, derived_bucket)
                derived_exists = bool(existence.get((derived_bucket, derived_key), False))
                if derived_exists:
                    bucket = derived_bucket
                    key = derived_key
                    bytes_exist = True
        records.append(
            MediaReportRecord(
                category=str(MediaCategory.orphan),
                status=str(MediaStatus.orphaned),
                recommended_action=str(MediaRecommendedAction.safe_to_delete),
                resolvable_for_editor=False,
                resolvable_for_student=False,
                lesson_media_id=None,
                media_id=row.media_object_id,
                kind=None,
                storage_bucket=bucket,
                storage_path=key,
                bytes_exist=bytes_exist,
                issue_reason="orphaned_object",
                issue_details={
                    "content_type": row.content_type,
                    "original_name": row.original_name,
                    "byte_size": row.byte_size,
                },
                proposed_updates=[],
            )
        )
    records.sort(key=lambda r: (r.media_id or ""))
    return records


def collapse_updates(updates: Sequence[ProposedUpdate]) -> list[ProposedUpdate]:
    merged: dict[tuple[str, str], dict[str, Any]] = {}
    for update in updates:
        key = (update.table, update.id)
        merged.setdefault(key, {})
        merged[key].update(update.fields)
    collapsed = [
        ProposedUpdate(table=table, id=id_value, fields=fields)
        for (table, id_value), fields in sorted(merged.items())
        if fields
    ]
    return collapsed


def build_report(
    *,
    legacy_records: Sequence[MediaReportRecord],
    pipeline_records: Sequence[MediaReportRecord],
    orphan_records: Sequence[MediaReportRecord],
    buckets: set[str],
) -> dict[str, Any]:
    records: list[MediaReportRecord] = list(legacy_records) + list(pipeline_records) + list(orphan_records)

    def counts_by(fn) -> dict[str, int]:
        counts: dict[str, int] = {}
        for record in records:
            key = str(fn(record))
            counts[key] = counts.get(key, 0) + 1
        return {k: counts[k] for k in sorted(counts)}

    summary = {
        "total_records": len(records),
        "by_category": counts_by(lambda r: r.category),
        "by_status": counts_by(lambda r: r.status),
        "by_recommended_action": counts_by(lambda r: r.recommended_action),
        "buckets_considered": sorted(buckets),
    }

    return {
        "summary": summary,
        "records": [
            {
                "category": r.category,
                "status": r.status,
                "recommended_action": r.recommended_action,
                "resolvable_for_editor": r.resolvable_for_editor,
                "resolvable_for_student": r.resolvable_for_student,
                "lesson_media_id": r.lesson_media_id,
                "media_id": r.media_id,
                "kind": r.kind,
                "storage_bucket": r.storage_bucket,
                "storage_path": r.storage_path,
                "bytes_exist": r.bytes_exist,
                "issue_reason": r.issue_reason,
                "issue_details": r.issue_details,
                "proposed_updates": [
                    {"table": u.table, "id": u.id, "fields": u.fields}
                    for u in r.proposed_updates
                    if u.fields
                ],
            }
            for r in records
        ],
    }


def format_report(report: dict[str, Any]) -> str:
    return json.dumps(report, indent=2, sort_keys=True)


def format_markdown_report(report: dict[str, Any]) -> str:
    summary: dict[str, Any] = dict(report.get("summary") or {})
    records: list[dict[str, Any]] = list(report.get("records") or [])

    lines: list[str] = []
    lines.append("# Media Robustness Report")
    lines.append("")
    lines.append(f"- Total records: `{summary.get('total_records', 0)}`")
    lines.append("")

    def emit_counts(title: str, mapping: dict[str, Any]) -> None:
        lines.append(f"## {title}")
        lines.append("")
        if not mapping:
            lines.append("_None_")
            lines.append("")
            return
        for key in sorted(mapping):
            lines.append(f"- `{key}`: `{mapping[key]}`")
        lines.append("")

    emit_counts("By Category", dict(summary.get("by_category") or {}))
    emit_counts("By Status", dict(summary.get("by_status") or {}))
    emit_counts("By Recommended Action", dict(summary.get("by_recommended_action") or {}))

    lines.append("## Records")
    lines.append("")
    lines.append("| category | status | action | editor | student | lesson_media_id | media_id | kind | bucket | path |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")

    def cell(value: Any) -> str:
        raw = "" if value is None else str(value)
        return raw.replace("\n", " ").replace("|", "\\|")

    for row in records:
        lines.append(
            "| "
            + " | ".join(
                [
                    cell(row.get("category")),
                    cell(row.get("status")),
                    cell(row.get("recommended_action")),
                    "✅" if row.get("resolvable_for_editor") else "❌",
                    "✅" if row.get("resolvable_for_student") else "❌",
                    cell(row.get("lesson_media_id")),
                    cell(row.get("media_id")),
                    cell(row.get("kind")),
                    cell(row.get("storage_bucket")),
                    cell(row.get("storage_path")),
                ]
            )
            + " |"
        )

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- Dry-run output is deterministic (no timestamps).")
    lines.append("- No deletes are performed by this tool.")
    lines.append("")
    return "\n".join(lines)


def _chunked(items: Sequence[Any], size: int) -> Iterable[Sequence[Any]]:
    resolved = max(1, int(size))
    for idx in range(0, len(items), resolved):
        yield items[idx : idx + resolved]


def apply_updates_in_batches(
    conn: psycopg.Connection,
    updates: Sequence[ProposedUpdate],
    *,
    batch_size: int,
) -> dict[str, int]:
    counts = {
        "media_objects_updated": 0,
        "lesson_media_updated": 0,
        "issues_upserted": 0,
    }

    media_object_updates = [u for u in updates if u.table == "app.media_objects" and u.fields]
    lesson_media_updates = [u for u in updates if u.table == "app.lesson_media" and u.fields]
    issue_updates = [u for u in updates if u.table == "app.lesson_media_issues" and u.fields]

    for batch in _chunked(media_object_updates, batch_size):
        with conn.cursor() as cur:
            for update in batch:
                fields_sql: list[str] = []
                params: list[Any] = []
                for key, value in sorted(update.fields.items()):
                    fields_sql.append(f"{key} = %s")
                    params.append(value)
                fields_sql.append("updated_at = now()")
                params.append(update.id)
                cur.execute(
                    f"UPDATE app.media_objects SET {', '.join(fields_sql)} WHERE id = %s",
                    params,
                )
                counts["media_objects_updated"] += int(cur.rowcount or 0)
        conn.commit()

    for batch in _chunked(lesson_media_updates, batch_size):
        with conn.cursor() as cur:
            for update in batch:
                fields_sql: list[str] = []
                params: list[Any] = []
                for key, value in sorted(update.fields.items()):
                    fields_sql.append(f"{key} = %s")
                    params.append(value)
                fields_sql.append("updated_at = now()")
                params.append(update.id)
                cur.execute(
                    f"UPDATE app.lesson_media SET {', '.join(fields_sql)} WHERE id = %s",
                    params,
                )
                counts["lesson_media_updated"] += int(cur.rowcount or 0)
        conn.commit()

    for batch in _chunked(issue_updates, batch_size):
        with conn.cursor() as cur:
            for update in batch:
                issue = update.fields.get("issue")
                details = update.fields.get("details") or {}
                try:
                    cur.execute(
                        """
                        INSERT INTO app.lesson_media_issues (
                          lesson_media_id,
                          issue,
                          details,
                          updated_at
                        )
                        VALUES (%s, %s, %s, now())
                        ON CONFLICT (lesson_media_id) DO UPDATE
                          SET issue = excluded.issue,
                              details = excluded.details,
                              updated_at = now()
                        """,
                        (update.id, issue, json.dumps(details)),
                    )
                    counts["issues_upserted"] += int(cur.rowcount or 0)
                except errors.UndefinedTable:
                    # Migrations not applied – skip silently (report still shows issues).
                    continue
        conn.commit()

    return counts


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    db_url = _ensure_db_url(args.database_url)
    if not db_url:
        print("Error: provide --database-url or set $DATABASE_URL", file=sys.stderr)
        return 1

    buckets = {b.strip() for b in str(args.buckets or "").split(",") if b.strip()}
    if not buckets:
        buckets = set(DEFAULT_BUCKETS)

    include_orphans = not bool(args.no_orphans)

    try:
        with psycopg.connect(db_url, autocommit=False) as conn:
            legacy_rows = fetch_legacy_lesson_media_rows(conn, limit=args.limit_legacy)
            pipeline_rows = fetch_pipeline_lesson_media_rows(conn, limit=args.limit_pipeline)

            orphan_asset_rows: list[OrphanMediaAssetRow] = []
            orphan_object_rows: list[OrphanMediaObjectRow] = []
            if include_orphans:
                orphan_asset_rows = fetch_orphan_media_assets(conn, limit=args.orphans_limit)
                orphan_object_rows = fetch_orphan_media_objects(conn, limit=args.orphans_limit)

            candidate_pairs: list[tuple[str, str]] = []

            for row in legacy_rows:
                bucket = row.object_storage_bucket or row.lesson_storage_bucket
                path = row.object_storage_path or row.lesson_storage_path
                candidate_pairs.extend(
                    _candidate_pairs_for_storage_ref(
                        storage_bucket=bucket,
                        storage_path=path,
                        buckets=buckets,
                    )
                )

            for row in pipeline_rows:
                bucket = _normalize_bucket(row.storage_bucket)
                key = _normalize_path(row.streaming_object_path)
                if bucket and key:
                    candidate_pairs.append((bucket, key))

            if include_orphans:
                for orphan in orphan_asset_rows:
                    bucket = _normalize_bucket(orphan.storage_bucket)
                    key = _normalize_path(orphan.streaming_object_path) or _normalize_path(orphan.original_object_path)
                    if bucket and key:
                        candidate_pairs.append((bucket, key))
                for orphan in orphan_object_rows:
                    bucket = _normalize_bucket(orphan.storage_bucket)
                    key = _normalize_path(orphan.storage_path)
                    if bucket and key:
                        candidate_pairs.append((bucket, key))

            existence, storage_table_available = fetch_storage_existence(conn, candidate_pairs)

            legacy_records = build_legacy_records(
                legacy_rows,
                existence=existence,
                buckets=buckets,
                storage_table_available=storage_table_available,
            )
            pipeline_records = build_pipeline_records(
                pipeline_rows,
                existence=existence,
                storage_table_available=storage_table_available,
            )
            orphan_records: list[MediaReportRecord] = []
            if include_orphans:
                orphan_records.extend(
                    build_orphan_asset_records(
                        orphan_asset_rows,
                        existence=existence,
                        storage_table_available=storage_table_available,
                    )
                )
                orphan_records.extend(
                    build_orphan_object_records(
                        orphan_object_rows,
                        existence=existence,
                        buckets=buckets,
                        storage_table_available=storage_table_available,
                    )
                )

            report = build_report(
                legacy_records=legacy_records,
                pipeline_records=pipeline_records,
                orphan_records=orphan_records,
                buckets=buckets,
            )

            updates: list[ProposedUpdate] = []
            for record in legacy_records:
                updates.extend(record.proposed_updates)
            updates = collapse_updates(updates)

            if args.apply and updates:
                applied = apply_updates_in_batches(conn, updates, batch_size=args.batch_size)
                report["applied"] = applied

            json_payload = format_report(report)
            md_payload = format_markdown_report(report)

            output_dir = Path(str(args.output_dir or ".")).resolve()
            json_out = str(args.json_out or "").strip() or "-"
            md_out = str(args.md_out or "").strip() or "-"

            if json_out == "-":
                print(json_payload)
            else:
                output_dir.mkdir(parents=True, exist_ok=True)
                json_path = output_dir / json_out
                json_path.write_text(json_payload + "\n", encoding="utf-8")
                print(f"Wrote JSON report to {json_path}")

            if md_out == "-":
                print(md_payload)
            else:
                output_dir.mkdir(parents=True, exist_ok=True)
                md_path = output_dir / md_out
                md_path.write_text(md_payload + "\n", encoding="utf-8")
                print(f"Wrote Markdown report to {md_path}")

            return 0
    except psycopg.Error as exc:
        print(f"Database error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
