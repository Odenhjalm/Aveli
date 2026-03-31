#!/usr/bin/env python3
"""Production-safe, read-only media audit for Aveli.

Safety guarantees:
- Postgres connections are opened with `default_transaction_read_only=on`.
- The script executes SELECT queries only.
- Storage validation uses HTTP HEAD and GET with Range headers only.
- The script never calls the Supabase sign-url POST endpoint.
- The script writes reports locally only.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterable, Sequence
from urllib.parse import quote, urlparse

import httpx
import psycopg
from dotenv import load_dotenv
from psycopg.rows import dict_row


ROOT_DIR = Path(__file__).resolve().parents[2]
REPORTS_DIR = ROOT_DIR / "reports"
DEFAULT_BUCKETS: tuple[str, ...] = ("public-media", "lesson-media", "course-media")
KNOWN_BUCKETS = set(DEFAULT_BUCKETS)
PUBLIC_PATH_PREFIXES = (
    "storage/v1/object/public/",
    "object/public/",
)
AUTH_PATH_PREFIXES = (
    "storage/v1/object/authenticated/",
    "object/authenticated/",
    "storage/v1/object/",
    "object/",
)
PATH_PREFIXES = (
    "api/files/",
    *PUBLIC_PATH_PREFIXES,
    "storage/v1/object/sign/",
    "object/sign/",
    *AUTH_PATH_PREFIXES,
)
ENV_FILE_CANDIDATES = (
    ROOT_DIR / ".env",
    ROOT_DIR / ".env.local",
    ROOT_DIR / "backend" / ".env",
    ROOT_DIR / "backend" / ".env.local",
    ROOT_DIR / "frontend" / ".env.web",
)

SUPPORTED_AUDIO_MIMES = {"audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav"}
SUPPORTED_IMAGE_MIMES = {"image/jpeg", "image/png"}
SUPPORTED_VIDEO_MIMES = {"video/mp4"}
MIME_ALIASES = {
    "audio/mp3": "audio/mpeg",
    "audio/x-wav": "audio/wav",
    "image/jpg": "image/jpeg",
}
EXPECTED_MIME_BY_EXTENSION = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".mp4": "video/mp4",
}


@dataclass(slots=True)
class ResolvedLocation:
    bucket: str | None
    path: str | None
    path_bucket_prefix: str | None
    raw_path: str | None


@dataclass(slots=True)
class DBReference:
    media_id: str
    source_table: str
    reference_type: str
    bucket: str | None
    storage_path: str | None
    raw_storage_path: str | None
    path_bucket_prefix: str | None
    content_type: str | None
    byte_size: int | None
    media_state: str | None
    duration_seconds: int | None
    original_name: str | None
    created_at: str | None
    kind: str | None
    media_type: str | None
    purpose: str | None
    lesson_media_id: str | None
    lesson_id: str | None
    lesson_title: str | None
    course_id: str | None
    course_slug: str | None
    course_title: str | None
    related_media_asset_id: str | None
    related_media_object_id: str | None

    @property
    def pair(self) -> tuple[str, str] | None:
        if not self.bucket or not self.storage_path:
            return None
        return (self.bucket, self.storage_path)


@dataclass(slots=True)
class StorageObject:
    bucket: str
    storage_path: str
    size_bytes: int | None
    content_type: str | None
    created_at: str | None
    updated_at: str | None
    public: bool
    metadata_http_status: int | None
    object_id: str | None

    @property
    def pair(self) -> tuple[str, str]:
        return (self.bucket, self.storage_path)


@dataclass(slots=True)
class ProbeResult:
    bucket: str
    storage_path: str
    url: str
    mode: str
    head_status: int | None
    head_content_type: str | None
    head_content_length: int | None
    range_status: int | None
    range_content_type: str | None
    range_content_length: int | None
    range_content_range: str | None
    range_bytes_read: int | None
    audio_stream_status: int | None
    audio_stream_content_range: str | None
    error: str | None
    skipped_reason: str | None

    @property
    def pair(self) -> tuple[str, str]:
        return (self.bucket, self.storage_path)


def _load_env() -> None:
    for env_path in ENV_FILE_CANDIDATES:
        if env_path.exists():
            load_dotenv(env_path, override=False)


def _env(*keys: str) -> str | None:
    for key in keys:
        value = (os.environ.get(key) or "").strip()
        if value:
            return value
    return None


def _ensure_db_url(url: str | None) -> str | None:
    if not url:
        return None
    if "sslmode=" in url:
        return url
    parsed = urlparse(url)
    hostname = (parsed.hostname or "").strip().lower()
    if hostname in {"localhost", "127.0.0.1", "::1"}:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}sslmode=require"


def _normalize_bucket(value: Any) -> str | None:
    normalized = str(value or "").strip().strip("/")
    return normalized or None


def _normalize_mime(value: Any) -> str | None:
    raw = str(value or "").strip().lower()
    if not raw:
        return None
    raw = raw.split(";", 1)[0].strip()
    return MIME_ALIASES.get(raw, raw)


def _iso(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=UTC)
        return value.astimezone(UTC).isoformat()
    return str(value)


def _coerce_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _normalize_path(value: Any) -> str | None:
    if value is None:
        return None
    raw = str(value).strip()
    if not raw:
        return None
    parsed = urlparse(raw)
    if parsed.scheme in {"http", "https"} and parsed.path:
        raw = parsed.path
    normalized = raw.replace("\\", "/").lstrip("/")
    for prefix in PATH_PREFIXES:
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix) :].lstrip("/")
            break
    return normalized or None


def _resolve_location(bucket: Any, storage_path: Any) -> ResolvedLocation:
    normalized_bucket = _normalize_bucket(bucket)
    normalized_path = _normalize_path(storage_path)
    path_bucket_prefix = None

    if normalized_path:
        prefix, _, remainder = normalized_path.partition("/")
        if prefix in KNOWN_BUCKETS:
            path_bucket_prefix = prefix
            if normalized_bucket is None:
                normalized_bucket = prefix
                normalized_path = remainder or None

    if normalized_bucket and normalized_path:
        bucket_prefix = f"{normalized_bucket}/"
        if normalized_path.startswith(bucket_prefix):
            normalized_path = normalized_path[len(bucket_prefix) :] or None

    return ResolvedLocation(
        bucket=normalized_bucket,
        path=normalized_path,
        path_bucket_prefix=path_bucket_prefix,
        raw_path=str(storage_path).strip() if storage_path is not None else None,
    )


def _expected_mime(*values: Any) -> str | None:
    for value in values:
        raw = str(value or "").strip()
        if not raw:
            continue
        suffix = Path(raw).suffix.lower()
        if suffix in EXPECTED_MIME_BY_EXTENSION:
            return EXPECTED_MIME_BY_EXTENSION[suffix]
    return None


def _guess_is_audio(*values: Any) -> bool:
    mime = _normalize_mime(values[0]) if values else None
    if mime and mime.startswith("audio/"):
        return True
    for value in values[1:]:
        suffix = Path(str(value or "")).suffix.lower()
        if suffix in {".mp3", ".wav"}:
            return True
    return False


def _classify_media(content_type: str | None, *name_hints: Any) -> tuple[str, str]:
    normalized = _normalize_mime(content_type)
    if normalized in {"audio/mpeg", "audio/wav"}:
        return "SUPPORTED_AUDIO", f"{normalized} is in the supported audio set"
    if normalized in SUPPORTED_IMAGE_MIMES:
        return "SUPPORTED_IMAGE", f"{normalized} is in the supported image set"
    if normalized in SUPPORTED_VIDEO_MIMES:
        return "SUPPORTED_VIDEO", f"{normalized} is in the supported video set"

    expected = _expected_mime(*name_hints)
    if expected == "audio/mpeg" and normalized is None:
        return "SUPPORTED_AUDIO", "missing MIME; .mp3 extension implies supported audio"
    if expected == "audio/wav" and normalized is None:
        return "SUPPORTED_AUDIO", "missing MIME; .wav extension implies supported audio"
    if expected in SUPPORTED_IMAGE_MIMES and normalized is None:
        return "SUPPORTED_IMAGE", f"missing MIME; {expected} extension implies supported image"
    if expected == "video/mp4" and normalized is None:
        return "SUPPORTED_VIDEO", "missing MIME; .mp4 extension implies supported video"

    if normalized:
        return "UNSUPPORTED_TYPE", f"{normalized} is not in the supported playback set"
    if expected:
        return "UNSUPPORTED_TYPE", f"{expected} is expected from the extension but no actual MIME is present"
    return "UNSUPPORTED_TYPE", "missing MIME and unknown extension"


def _quote_path(storage_path: str) -> str:
    return quote(storage_path, safe="/")


def _public_object_url(base_url: str, bucket: str, storage_path: str) -> str:
    return f"{base_url.rstrip('/')}/storage/v1/object/public/{bucket}/{_quote_path(storage_path)}"


def _authenticated_object_url(base_url: str, bucket: str, storage_path: str) -> str:
    return f"{base_url.rstrip('/')}/storage/v1/object/{bucket}/{_quote_path(storage_path)}"


def _format_gb(byte_count: int | float) -> float:
    return round(float(byte_count) / (1024 ** 3), 3)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read-only media audit for Aveli production.")
    parser.add_argument(
        "--prod-readonly",
        action="store_true",
        help="Require production-safe read-only behavior and fail if readonly mode is not confirmed.",
    )
    parser.add_argument(
        "--database-url",
        default=_env("DATABASE_URL", "SUPABASE_DB_URL"),
        help="Postgres URL (defaults to DATABASE_URL or SUPABASE_DB_URL).",
    )
    parser.add_argument(
        "--supabase-url",
        default=_env("SUPABASE_URL"),
        help="Supabase project URL (defaults to SUPABASE_URL).",
    )
    parser.add_argument(
        "--supabase-secret-key",
        default=_env("SUPABASE_SECRET_API_KEY", "SUPABASE_SERVICE_ROLE_KEY"),
        help="Supabase secret/service key for private bucket GET/HEAD probes.",
    )
    parser.add_argument(
        "--supabase-publishable-key",
        default=_env(
            "SUPABASE_PUBLISHABLE_API_KEY",
            "SUPABASE_PUBLIC_API_KEY",
            "SUPABASE_ANON_KEY",
        ),
        help="Supabase publishable key for public bucket probes.",
    )
    parser.add_argument(
        "--buckets",
        default=",".join(DEFAULT_BUCKETS),
        help="Comma-separated bucket ids to audit (default: %(default)s).",
    )
    parser.add_argument(
        "--http-timeout",
        type=float,
        default=20.0,
        help="Timeout in seconds per HTTP request (default: %(default)s).",
    )
    parser.add_argument(
        "--http-concurrency",
        type=int,
        default=24,
        help="Maximum concurrent storage probes (default: %(default)s).",
    )
    parser.add_argument(
        "--json-out",
        default=str(REPORTS_DIR / "media_audit.json"),
        help="Path to the JSON report (default: reports/media_audit.json).",
    )
    parser.add_argument(
        "--md-out",
        default=str(REPORTS_DIR / "media_audit_report.md"),
        help="Path to the Markdown report (default: reports/media_audit_report.md).",
    )
    return parser.parse_args(argv)


def _connect(database_url: str) -> psycopg.Connection[Any]:
    return psycopg.connect(
        _ensure_db_url(database_url),
        row_factory=dict_row,
        options="-c default_transaction_read_only=on -c statement_timeout=60000 -c idle_in_transaction_session_timeout=60000",
        connect_timeout=10,
    )


def _fetch_table_presence(conn: psycopg.Connection[Any]) -> dict[str, bool]:
    query = """
        SELECT table_schema || '.' || table_name AS table_name
        FROM information_schema.tables
        WHERE (table_schema, table_name) IN (
          ('app', 'media_objects'),
          ('app', 'media_assets'),
          ('app', 'lesson_media'),
          ('app', 'lessons'),
          ('app', 'courses'),
          ('storage', 'objects'),
          ('storage', 'buckets')
        )
    """
    with conn.cursor() as cur:
        cur.execute(query)
        rows = {str(row["table_name"]) for row in cur.fetchall()}
    wanted = {
        "app.media_objects",
        "app.media_assets",
        "app.lesson_media",
        "app.lessons",
        "app.courses",
        "storage.objects",
        "storage.buckets",
    }
    return {name: name in rows for name in wanted}


def _readonly_confirmed(conn: psycopg.Connection[Any]) -> bool:
    with conn.cursor() as cur:
        cur.execute("SHOW default_transaction_read_only")
        row = cur.fetchone()
    return str((row or {}).get("default_transaction_read_only", "")).strip().lower() == "on"


def _fetch_media_objects(conn: psycopg.Connection[Any], table_presence: dict[str, bool]) -> list[dict[str, Any]]:
    if not table_presence.get("app.media_objects"):
        return []
    query = """
        SELECT
          id::text AS id,
          storage_bucket,
          storage_path,
          content_type,
          byte_size,
          original_name,
          created_at
        FROM app.media_objects
        ORDER BY created_at ASC, id ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return list(cur.fetchall())


def _fetch_media_assets(conn: psycopg.Connection[Any], table_presence: dict[str, bool]) -> list[dict[str, Any]]:
    if not table_presence.get("app.media_assets"):
        return []
    query = """
        SELECT
          id::text AS id,
          course_id::text AS course_id,
          lesson_id::text AS lesson_id,
          media_type,
          purpose,
          storage_bucket,
          original_object_path,
          original_content_type,
          original_size_bytes,
          streaming_storage_bucket,
          streaming_object_path,
          streaming_format,
          duration_seconds,
          codec,
          state,
          original_filename,
          created_at
        FROM app.media_assets
        ORDER BY created_at ASC, id ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return list(cur.fetchall())


def _fetch_lesson_media(conn: psycopg.Connection[Any], table_presence: dict[str, bool]) -> list[dict[str, Any]]:
    if not table_presence.get("app.lesson_media"):
        return []
    query = """
        SELECT
          lm.id::text AS lesson_media_id,
          lm.lesson_id::text AS lesson_id,
          l.lesson_title AS lesson_title,
          l.course_id::text AS course_id,
          c.slug AS course_slug,
          c.title AS course_title,
          lm.kind,
          lm.media_id::text AS media_id,
          lm.media_asset_id::text AS media_asset_id,
          lm.storage_bucket,
          lm.storage_path,
          lm.duration_seconds,
          lm.created_at,
          mo.id::text AS joined_media_object_id,
          mo.storage_bucket AS media_object_bucket,
          mo.storage_path AS media_object_path,
          mo.content_type AS media_object_content_type,
          mo.byte_size AS media_object_byte_size,
          mo.original_name AS media_object_original_name,
          ma.id::text AS joined_media_asset_id,
          ma.storage_bucket AS media_asset_bucket,
          ma.original_object_path AS media_asset_original_path,
          ma.original_content_type AS media_asset_original_content_type,
          ma.original_size_bytes AS media_asset_original_size_bytes,
          ma.streaming_storage_bucket AS media_asset_streaming_bucket,
          ma.streaming_object_path AS media_asset_streaming_path,
          ma.state AS media_asset_state,
          ma.original_filename AS media_asset_original_filename,
          ma.duration_seconds AS media_asset_duration_seconds,
          ma.purpose AS media_asset_purpose,
          ma.media_type AS media_asset_type
        FROM app.lesson_media lm
        LEFT JOIN app.lessons l
          ON l.id = lm.lesson_id
        LEFT JOIN app.courses c
          ON c.id = l.course_id
        LEFT JOIN app.media_objects mo
          ON mo.id = lm.media_id
        LEFT JOIN app.media_assets ma
          ON ma.id = lm.media_asset_id
        ORDER BY lm.created_at ASC, lm.id ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return list(cur.fetchall())


def _fetch_courses(conn: psycopg.Connection[Any], table_presence: dict[str, bool]) -> list[dict[str, Any]]:
    if not table_presence.get("app.courses"):
        return []
    query = """
        SELECT
          c.id::text AS course_id,
          c.slug,
          c.title,
          c.cover_media_id::text AS cover_media_id,
          ma.id::text AS joined_cover_media_id,
          ma.state AS cover_media_state,
          ma.storage_bucket AS cover_storage_bucket,
          ma.original_object_path AS cover_original_object_path,
          ma.streaming_storage_bucket AS cover_streaming_bucket,
          ma.streaming_object_path AS cover_streaming_object_path,
          ma.original_content_type AS cover_content_type,
          ma.original_size_bytes AS cover_size_bytes,
          ma.original_filename AS cover_original_name,
          ma.created_at AS cover_created_at
        FROM app.courses c
        LEFT JOIN app.media_assets ma
          ON ma.id = c.cover_media_id
        ORDER BY c.created_at ASC, c.id ASC
    """
    with conn.cursor() as cur:
        cur.execute(query)
        return list(cur.fetchall())


def _fetch_storage_objects(
    conn: psycopg.Connection[Any],
    table_presence: dict[str, bool],
    buckets: Sequence[str],
) -> tuple[list[StorageObject], dict[str, bool]]:
    if not table_presence.get("storage.objects") or not table_presence.get("storage.buckets"):
        return [], {}

    query = """
        SELECT
          o.id::text AS object_id,
          o.bucket_id,
          o.name,
          o.created_at,
          o.updated_at,
          o.metadata,
          b.public
        FROM storage.objects o
        JOIN storage.buckets b
          ON b.id = o.bucket_id
        WHERE o.bucket_id = ANY(%s)
        ORDER BY o.created_at ASC, o.id ASC
    """
    with conn.cursor() as cur:
        cur.execute(query, (list(buckets),))
        rows = list(cur.fetchall())

    objects: list[StorageObject] = []
    bucket_public: dict[str, bool] = {}
    for row in rows:
        metadata = row.get("metadata") or {}
        bucket = str(row["bucket_id"])
        bucket_public[bucket] = bool(row.get("public"))
        objects.append(
            StorageObject(
                object_id=str(row["object_id"]) if row.get("object_id") else None,
                bucket=bucket,
                storage_path=str(row["name"]),
                size_bytes=_coerce_int(metadata.get("size") or metadata.get("contentLength")),
                content_type=_normalize_mime(metadata.get("mimetype")),
                created_at=_iso(row.get("created_at")),
                updated_at=_iso(row.get("updated_at")),
                public=bool(row.get("public")),
                metadata_http_status=_coerce_int(metadata.get("httpStatusCode")),
            )
        )
    return objects, bucket_public


def _build_references(
    media_objects: Iterable[dict[str, Any]],
    media_assets: Iterable[dict[str, Any]],
    lesson_media_rows: Iterable[dict[str, Any]],
) -> list[DBReference]:
    references: list[DBReference] = []

    for row in media_objects:
        location = _resolve_location(row.get("storage_bucket"), row.get("storage_path"))
        references.append(
            DBReference(
                media_id=str(row["id"]),
                source_table="app.media_objects",
                reference_type="primary",
                bucket=location.bucket,
                storage_path=location.path,
                raw_storage_path=location.raw_path,
                path_bucket_prefix=location.path_bucket_prefix,
                content_type=_normalize_mime(row.get("content_type")),
                byte_size=_coerce_int(row.get("byte_size")),
                media_state=None,
                duration_seconds=None,
                original_name=str(row.get("original_name") or "") or None,
                created_at=_iso(row.get("created_at")),
                kind=None,
                media_type=None,
                purpose=None,
                lesson_media_id=None,
                lesson_id=None,
                lesson_title=None,
                course_id=None,
                course_slug=None,
                course_title=None,
                related_media_asset_id=None,
                related_media_object_id=str(row["id"]),
            )
        )

    for row in media_assets:
        original_location = _resolve_location(row.get("storage_bucket"), row.get("original_object_path"))
        references.append(
            DBReference(
                media_id=str(row["id"]),
                source_table="app.media_assets",
                reference_type="original",
                bucket=original_location.bucket,
                storage_path=original_location.path,
                raw_storage_path=original_location.raw_path,
                path_bucket_prefix=original_location.path_bucket_prefix,
                content_type=_normalize_mime(row.get("original_content_type")),
                byte_size=_coerce_int(row.get("original_size_bytes")),
                media_state=str(row.get("state") or "") or None,
                duration_seconds=_coerce_int(row.get("duration_seconds")),
                original_name=str(row.get("original_filename") or "") or None,
                created_at=_iso(row.get("created_at")),
                kind=None,
                media_type=str(row.get("media_type") or "") or None,
                purpose=str(row.get("purpose") or "") or None,
                lesson_media_id=None,
                lesson_id=str(row.get("lesson_id") or "") or None,
                lesson_title=None,
                course_id=str(row.get("course_id") or "") or None,
                course_slug=None,
                course_title=None,
                related_media_asset_id=str(row["id"]),
                related_media_object_id=None,
            )
        )

        streaming_path = row.get("streaming_object_path")
        if streaming_path:
            streaming_location = _resolve_location(
                row.get("streaming_storage_bucket") or row.get("storage_bucket"),
                streaming_path,
            )
            references.append(
                DBReference(
                    media_id=str(row["id"]),
                    source_table="app.media_assets",
                    reference_type="streaming",
                    bucket=streaming_location.bucket,
                    storage_path=streaming_location.path,
                    raw_storage_path=streaming_location.raw_path,
                    path_bucket_prefix=streaming_location.path_bucket_prefix,
                    content_type=_normalize_mime(row.get("streaming_format")),
                    byte_size=None,
                    media_state=str(row.get("state") or "") or None,
                    duration_seconds=_coerce_int(row.get("duration_seconds")),
                    original_name=str(row.get("original_filename") or "") or None,
                    created_at=_iso(row.get("created_at")),
                    kind=None,
                    media_type=str(row.get("media_type") or "") or None,
                    purpose=str(row.get("purpose") or "") or None,
                    lesson_media_id=None,
                    lesson_id=str(row.get("lesson_id") or "") or None,
                    lesson_title=None,
                    course_id=str(row.get("course_id") or "") or None,
                    course_slug=None,
                    course_title=None,
                    related_media_asset_id=str(row["id"]),
                    related_media_object_id=None,
                )
            )

    for row in lesson_media_rows:
        if not row.get("storage_path"):
            continue
        location = _resolve_location(row.get("storage_bucket"), row.get("storage_path"))
        references.append(
            DBReference(
                media_id=str(row["lesson_media_id"]),
                source_table="app.lesson_media",
                reference_type="direct_storage_path",
                bucket=location.bucket,
                storage_path=location.path,
                raw_storage_path=location.raw_path,
                path_bucket_prefix=location.path_bucket_prefix,
                content_type=None,
                byte_size=None,
                media_state=str(row.get("media_asset_state") or "") or None,
                duration_seconds=_coerce_int(row.get("duration_seconds")),
                original_name=None,
                created_at=_iso(row.get("created_at")),
                kind=str(row.get("kind") or "") or None,
                media_type=str(row.get("media_asset_type") or "") or None,
                purpose=str(row.get("media_asset_purpose") or "") or None,
                lesson_media_id=str(row["lesson_media_id"]),
                lesson_id=str(row.get("lesson_id") or "") or None,
                lesson_title=str(row.get("lesson_title") or "") or None,
                course_id=str(row.get("course_id") or "") or None,
                course_slug=str(row.get("course_slug") or "") or None,
                course_title=str(row.get("course_title") or "") or None,
                related_media_asset_id=str(row.get("media_asset_id") or "") or None,
                related_media_object_id=str(row.get("media_id") or "") or None,
            )
        )

    return references


def _build_relation_issues(
    lesson_media_rows: Iterable[dict[str, Any]],
    courses_rows: Iterable[dict[str, Any]],
) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []

    for row in lesson_media_rows:
        lesson_media_id = str(row["lesson_media_id"])
        media_asset_id = str(row.get("media_asset_id") or "") or None
        media_id = str(row.get("media_id") or "") or None
        direct_storage_path = str(row.get("storage_path") or "") or None

        if media_asset_id and not row.get("joined_media_asset_id"):
            issues.append(
                {
                    "severity": "error",
                    "reason": "missing_media_asset_relation",
                    "lesson_media_id": lesson_media_id,
                    "media_asset_id": media_asset_id,
                    "media_id": None,
                    "course_id": row.get("course_id"),
                    "course_slug": row.get("course_slug"),
                    "lesson_id": row.get("lesson_id"),
                    "lesson_title": row.get("lesson_title"),
                    "details": "lesson_media.media_asset_id references a missing app.media_assets row",
                }
            )

        if media_id and not row.get("joined_media_object_id"):
            issues.append(
                {
                    "severity": "error",
                    "reason": "missing_media_object_relation",
                    "lesson_media_id": lesson_media_id,
                    "media_asset_id": None,
                    "media_id": media_id,
                    "course_id": row.get("course_id"),
                    "course_slug": row.get("course_slug"),
                    "lesson_id": row.get("lesson_id"),
                    "lesson_title": row.get("lesson_title"),
                    "details": "lesson_media.media_id references a missing app.media_objects row",
                }
            )

        if not media_asset_id:
            alternative = "none"
            if media_id:
                alternative = "media_id"
            elif direct_storage_path:
                alternative = "storage_path"
            issues.append(
                {
                    "severity": "info" if alternative != "none" else "error",
                    "reason": "null_media_asset_reference",
                    "lesson_media_id": lesson_media_id,
                    "media_asset_id": None,
                    "media_id": media_id,
                    "course_id": row.get("course_id"),
                    "course_slug": row.get("course_slug"),
                    "lesson_id": row.get("lesson_id"),
                    "lesson_title": row.get("lesson_title"),
                    "details": f"lesson_media.media_asset_id is null; alternate reference={alternative}",
                    "alternate_reference": alternative,
                }
            )

        if not any((media_asset_id, media_id, direct_storage_path)):
            issues.append(
                {
                    "severity": "error",
                    "reason": "unresolvable_lesson_media",
                    "lesson_media_id": lesson_media_id,
                    "media_asset_id": None,
                    "media_id": None,
                    "course_id": row.get("course_id"),
                    "course_slug": row.get("course_slug"),
                    "lesson_id": row.get("lesson_id"),
                    "lesson_title": row.get("lesson_title"),
                    "details": "lesson_media has no media_asset_id, media_id, or storage_path",
                }
            )

    for row in courses_rows:
        cover_media_id = str(row.get("cover_media_id") or "") or None
        if cover_media_id and not row.get("joined_cover_media_id"):
            issues.append(
                {
                    "severity": "error",
                    "reason": "missing_course_cover_media_relation",
                    "lesson_media_id": None,
                    "media_asset_id": cover_media_id,
                    "media_id": cover_media_id,
                    "course_id": row.get("course_id"),
                    "course_slug": row.get("slug"),
                    "lesson_id": None,
                    "lesson_title": None,
                    "details": "courses.cover_media_id references a missing app.media_assets row",
                }
            )

    return issues


async def _probe_object(
    client: httpx.AsyncClient,
    base_url: str,
    bucket_public: bool,
    bucket: str,
    storage_path: str,
    timeout_headers: dict[str, str],
    range_headers: dict[str, str],
    audio_headers: dict[str, str] | None,
) -> ProbeResult:
    if bucket_public:
        url = _public_object_url(base_url, bucket, storage_path)
        mode = "public"
    else:
        url = _authenticated_object_url(base_url, bucket, storage_path)
        mode = "authenticated"

    head_status: int | None = None
    head_content_type: str | None = None
    head_content_length: int | None = None
    range_status: int | None = None
    range_content_type: str | None = None
    range_content_length: int | None = None
    range_content_range: str | None = None
    range_bytes_read: int | None = None
    audio_stream_status: int | None = None
    audio_stream_content_range: str | None = None
    error: str | None = None

    try:
        head = await client.head(url, headers=timeout_headers)
        head_status = head.status_code
        head_content_type = _normalize_mime(head.headers.get("content-type"))
        head_content_length = _coerce_int(head.headers.get("content-length"))
    except httpx.HTTPError as exc:
        error = f"HEAD failed: {exc.__class__.__name__}: {exc}"

    try:
        ranged = await client.get(url, headers=range_headers)
        range_status = ranged.status_code
        range_content_type = _normalize_mime(ranged.headers.get("content-type"))
        range_content_length = _coerce_int(ranged.headers.get("content-length"))
        range_content_range = ranged.headers.get("content-range")
        range_bytes_read = len(ranged.content)
        if ranged.status_code >= 400 and error is None:
            payload = ranged.text[:200].replace("\n", " ")
            error = f"GET range failed: {payload or ranged.reason_phrase}"
    except httpx.HTTPError as exc:
        if error is None:
            error = f"GET range failed: {exc.__class__.__name__}: {exc}"

    if audio_headers is not None:
        try:
            audio_resp = await client.get(url, headers=audio_headers)
            audio_stream_status = audio_resp.status_code
            audio_stream_content_range = audio_resp.headers.get("content-range")
            if audio_resp.status_code >= 400 and error is None:
                payload = audio_resp.text[:200].replace("\n", " ")
                error = f"GET audio range failed: {payload or audio_resp.reason_phrase}"
        except httpx.HTTPError as exc:
            if error is None:
                error = f"GET audio range failed: {exc.__class__.__name__}: {exc}"

    return ProbeResult(
        bucket=bucket,
        storage_path=storage_path,
        url=url,
        mode=mode,
        head_status=head_status,
        head_content_type=head_content_type,
        head_content_length=head_content_length,
        range_status=range_status,
        range_content_type=range_content_type,
        range_content_length=range_content_length,
        range_content_range=range_content_range,
        range_bytes_read=range_bytes_read,
        audio_stream_status=audio_stream_status,
        audio_stream_content_range=audio_stream_content_range,
        error=error,
        skipped_reason=None,
    )


async def _probe_all(
    *,
    base_url: str,
    secret_key: str | None,
    publishable_key: str | None,
    bucket_public_map: dict[str, bool],
    storage_objects: dict[tuple[str, str], StorageObject],
    references: list[DBReference],
    timeout: float,
    concurrency: int,
) -> dict[tuple[str, str], ProbeResult]:
    targets: set[tuple[str, str]] = set(storage_objects.keys())
    for ref in references:
        if ref.pair:
            targets.add(ref.pair)

    semaphore = asyncio.Semaphore(max(1, concurrency))
    results: dict[tuple[str, str], ProbeResult] = {}
    limits = httpx.Limits(max_connections=max(1, concurrency), max_keepalive_connections=max(1, concurrency))

    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True, limits=limits) as client:
        tasks: list[asyncio.Task[ProbeResult]] = []

        async def run(bucket: str, storage_path: str) -> ProbeResult:
            bucket_public = bool(bucket_public_map.get(bucket, False))
            if bucket_public:
                headers: dict[str, str] = {}
                if publishable_key:
                    headers["apikey"] = publishable_key
                audio_headers = None
                range_headers = {**headers, "Range": "bytes=0-1"}
            else:
                if not secret_key:
                    return ProbeResult(
                        bucket=bucket,
                        storage_path=storage_path,
                        url=_authenticated_object_url(base_url, bucket, storage_path),
                        mode="authenticated",
                        head_status=None,
                        head_content_type=None,
                        head_content_length=None,
                        range_status=None,
                        range_content_type=None,
                        range_content_length=None,
                        range_content_range=None,
                        range_bytes_read=None,
                        audio_stream_status=None,
                        audio_stream_content_range=None,
                        error=None,
                        skipped_reason="missing_secret_key_for_private_bucket",
                    )
                headers = {
                    "apikey": secret_key,
                    "Authorization": f"Bearer {secret_key}",
                }
                audio_headers = {**headers, "Range": "bytes=0-100"}
                range_headers = {**headers, "Range": "bytes=0-1"}

            if not _guess_is_audio(
                storage_objects.get((bucket, storage_path), StorageObject(
                    bucket=bucket,
                    storage_path=storage_path,
                    size_bytes=None,
                    content_type=None,
                    created_at=None,
                    updated_at=None,
                    public=bucket_public,
                    metadata_http_status=None,
                    object_id=None,
                )).content_type,
                storage_path,
            ):
                audio_headers = None

            async with semaphore:
                return await _probe_object(
                    client=client,
                    base_url=base_url,
                    bucket_public=bucket_public,
                    bucket=bucket,
                    storage_path=storage_path,
                    timeout_headers=headers,
                    range_headers=range_headers,
                    audio_headers=audio_headers,
                )

        for bucket, storage_path in sorted(targets):
            tasks.append(asyncio.create_task(run(bucket, storage_path)))

        for result in await asyncio.gather(*tasks):
            results[result.pair] = result

    return results


def _probe_summary(probe_results: dict[tuple[str, str], ProbeResult]) -> dict[str, int]:
    counts = Counter()
    for result in probe_results.values():
        if result.skipped_reason:
            counts[f"skipped:{result.skipped_reason}"] += 1
        if result.head_status is not None:
            counts[f"head:{result.head_status}"] += 1
        if result.range_status is not None:
            counts[f"range:{result.range_status}"] += 1
        if result.audio_stream_status is not None:
            counts[f"audio_range:{result.audio_stream_status}"] += 1
    return dict(sorted(counts.items()))


def _dedupe_append(target: list[dict[str, Any]], seen: set[tuple[Any, ...]], row: dict[str, Any], *parts: Any) -> None:
    key = tuple(parts)
    if key in seen:
        return
    seen.add(key)
    target.append(row)


def _collect_report(
    *,
    args: argparse.Namespace,
    table_presence: dict[str, bool],
    readonly_confirmed: bool,
    media_objects: list[dict[str, Any]],
    media_assets: list[dict[str, Any]],
    lesson_media_rows: list[dict[str, Any]],
    courses_rows: list[dict[str, Any]],
    references: list[DBReference],
    relation_issues: list[dict[str, Any]],
    storage_objects: list[StorageObject],
    bucket_public_map: dict[str, bool],
    probe_results: dict[tuple[str, str], ProbeResult],
) -> dict[str, Any]:
    storage_map = {obj.pair: obj for obj in storage_objects}
    refs_by_pair: dict[tuple[str, str], list[DBReference]] = defaultdict(list)
    for ref in references:
        if ref.pair:
            refs_by_pair[ref.pair].append(ref)

    referenced_pairs = set(refs_by_pair)
    storage_pairs = set(storage_map)
    missing_pairs = referenced_pairs - storage_pairs
    orphaned_pairs = storage_pairs - referenced_pairs

    broken_media: list[dict[str, Any]] = []
    suspicious_metadata: list[dict[str, Any]] = []
    storage_errors: list[dict[str, Any]] = []
    unsupported_media: list[dict[str, Any]] = []
    orphaned_storage_files: list[dict[str, Any]] = []
    db_missing_rows: list[dict[str, Any]] = []

    broken_seen: set[tuple[Any, ...]] = set()
    suspicious_seen: set[tuple[Any, ...]] = set()
    storage_error_seen: set[tuple[Any, ...]] = set()
    unsupported_seen: set[tuple[Any, ...]] = set()
    orphaned_seen: set[tuple[Any, ...]] = set()
    missing_seen: set[tuple[Any, ...]] = set()

    size_flags = Counter()
    bucket_flags = Counter()
    unsupported_reason_counts = Counter()
    relation_reason_counts = Counter(issue["reason"] for issue in relation_issues)

    for pair in sorted(orphaned_pairs):
        obj = storage_map[pair]
        _dedupe_append(
            orphaned_storage_files,
            orphaned_seen,
            {
                "storage_path": obj.storage_path,
                "bucket": obj.bucket,
                "size_bytes": obj.size_bytes,
                "content_type": obj.content_type,
                "created_at": obj.created_at,
            },
            obj.bucket,
            obj.storage_path,
        )

    for pair in sorted(missing_pairs):
        for ref in refs_by_pair[pair]:
            row = {
                "media_id": ref.media_id,
                "expected_storage_path": ref.storage_path,
                "bucket": ref.bucket,
                "size_bytes": ref.byte_size,
                "source_table": ref.source_table,
                "reference_type": ref.reference_type,
            }
            _dedupe_append(
                db_missing_rows,
                missing_seen,
                row,
                ref.media_id,
                ref.bucket,
                ref.storage_path,
                ref.source_table,
                ref.reference_type,
            )

    for issue in relation_issues:
        if issue["severity"] != "error":
            continue
        _dedupe_append(
            broken_media,
            broken_seen,
            {
                "media_id": issue.get("media_id") or issue.get("media_asset_id") or issue.get("lesson_media_id"),
                "storage_path": None,
                "bucket": None,
                "reason": issue["details"],
                "source_table": "relation",
            },
            issue.get("reason"),
            issue.get("lesson_media_id"),
            issue.get("media_asset_id"),
            issue.get("media_id"),
        )

    for ref in references:
        pair = ref.pair
        related_refs = refs_by_pair.get(pair or ("", ""), [ref]) if pair else [ref]
        related_media_ids = sorted({item.media_id for item in related_refs})
        storage_obj = storage_map.get(pair) if pair else None
        probe = probe_results.get(pair) if pair else None

        storage_exists = storage_obj is not None
        successful_http = bool(
            probe
            and (
                (probe.head_status is not None and probe.head_status < 400)
                or (probe.range_status is not None and probe.range_status < 400)
            )
        )
        actual_mime = _normalize_mime(
            (storage_obj.content_type if storage_obj else None)
            or (probe.head_content_type if successful_http and probe else None)
            or (probe.range_content_type if successful_http and probe else None)
        )
        expected_mime = _expected_mime(ref.storage_path, ref.original_name)
        classification, classification_reason = _classify_media(
            actual_mime or ref.content_type,
            ref.storage_path,
            ref.original_name,
        )

        if classification == "UNSUPPORTED_TYPE" and (storage_exists or successful_http):
            unsupported_reason_counts[classification_reason] += 1
            _dedupe_append(
                unsupported_media,
                unsupported_seen,
                {
                    "media_id": ref.media_id,
                    "content_type": actual_mime or ref.content_type,
                    "reason": classification_reason,
                    "bucket": ref.bucket,
                    "storage_path": ref.storage_path,
                    "source_table": ref.source_table,
                    "reference_type": ref.reference_type,
                    "related_media_ids": related_media_ids,
                },
                ref.media_id,
                ref.source_table,
                ref.reference_type,
                ref.bucket,
                ref.storage_path,
                classification_reason,
            )

        if expected_mime and actual_mime and expected_mime != actual_mime and (storage_exists or successful_http):
            _dedupe_append(
                suspicious_metadata,
                suspicious_seen,
                {
                    "media_id": ref.media_id,
                    "expected_mime": expected_mime,
                    "actual_mime": actual_mime,
                    "bucket": ref.bucket,
                    "storage_path": ref.storage_path,
                    "source_table": ref.source_table,
                    "reference_type": ref.reference_type,
                    "related_media_ids": related_media_ids,
                },
                ref.media_id,
                ref.bucket,
                ref.storage_path,
                expected_mime,
                actual_mime,
            )

        if ref.bucket is None:
            bucket_flags["missing_bucket"] += 1
            _dedupe_append(
                broken_media,
                broken_seen,
                {
                    "media_id": ref.media_id,
                    "storage_path": ref.storage_path,
                    "bucket": ref.bucket,
                    "reason": "storage_bucket missing",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                ref.source_table,
                ref.reference_type,
                "missing_bucket",
            )

        if ref.storage_path is None:
            _dedupe_append(
                broken_media,
                broken_seen,
                {
                    "media_id": ref.media_id,
                    "storage_path": ref.storage_path,
                    "bucket": ref.bucket,
                    "reason": "storage_path missing",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                ref.source_table,
                ref.reference_type,
                "missing_storage_path",
            )

        if ref.path_bucket_prefix and ref.bucket and ref.path_bucket_prefix != ref.bucket:
            bucket_flags["path_prefix_bucket_mismatch"] += 1
            _dedupe_append(
                broken_media,
                broken_seen,
                {
                    "media_id": ref.media_id,
                    "storage_path": ref.storage_path,
                    "bucket": ref.bucket,
                    "reason": f"storage_path points at bucket prefix {ref.path_bucket_prefix} but row bucket is {ref.bucket}",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                ref.source_table,
                ref.reference_type,
                "path_prefix_bucket_mismatch",
            )

        if pair is None:
            continue

        if pair in missing_pairs:
            _dedupe_append(
                broken_media,
                broken_seen,
                {
                    "media_id": ref.media_id,
                    "storage_path": ref.storage_path,
                    "bucket": ref.bucket,
                    "reason": "DB reference missing in storage.objects",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                ref.source_table,
                ref.reference_type,
                "missing_in_storage",
            )

        size_candidates = [storage_obj.size_bytes if storage_obj else None, ref.byte_size]
        for size_value in size_candidates:
            if size_value is None:
                continue
            if size_value == 0:
                size_flags["zero_byte"] += 1
                _dedupe_append(
                    broken_media,
                    broken_seen,
                    {
                        "media_id": ref.media_id,
                        "storage_path": ref.storage_path,
                        "bucket": ref.bucket,
                        "reason": "0 byte file",
                        "source_table": ref.source_table,
                    },
                    ref.media_id,
                    ref.source_table,
                    ref.reference_type,
                    "zero_byte",
                )
            elif size_value < 100:
                size_flags["tiny_file"] += 1
                _dedupe_append(
                    broken_media,
                    broken_seen,
                    {
                        "media_id": ref.media_id,
                        "storage_path": ref.storage_path,
                        "bucket": ref.bucket,
                        "reason": f"suspiciously small file ({size_value} bytes)",
                        "source_table": ref.source_table,
                    },
                    ref.media_id,
                    ref.source_table,
                    ref.reference_type,
                    "tiny_file",
                )

        if ref.byte_size is None and (
            ref.source_table == "app.media_objects"
            or (ref.source_table == "app.media_assets" and ref.reference_type == "original")
        ):
            size_flags["missing_db_size"] += 1

        if probe is None:
            continue

        if probe.skipped_reason:
            _dedupe_append(
                storage_errors,
                storage_error_seen,
                {
                    "media_id": ref.media_id,
                    "url": probe.url,
                    "status_code": None,
                    "bucket": ref.bucket,
                    "storage_path": ref.storage_path,
                    "reason": probe.skipped_reason,
                    "source_table": ref.source_table,
                },
                ref.media_id,
                probe.url,
                probe.skipped_reason,
            )

        if probe.head_status in {403, 404}:
            _dedupe_append(
                storage_errors,
                storage_error_seen,
                {
                    "media_id": ref.media_id,
                    "url": probe.url,
                    "status_code": probe.head_status,
                    "bucket": ref.bucket,
                    "storage_path": ref.storage_path,
                    "reason": "HEAD probe failed",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                probe.url,
                "head",
                probe.head_status,
            )

        if probe.range_status in {403, 404}:
            _dedupe_append(
                storage_errors,
                storage_error_seen,
                {
                    "media_id": ref.media_id,
                    "url": probe.url,
                    "status_code": probe.range_status,
                    "bucket": ref.bucket,
                    "storage_path": ref.storage_path,
                    "reason": "Range probe failed",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                probe.url,
                "range",
                probe.range_status,
            )

        if probe.head_status is not None and probe.head_status >= 400 and probe.head_status not in {403, 404}:
            _dedupe_append(
                storage_errors,
                storage_error_seen,
                {
                    "media_id": ref.media_id,
                    "url": probe.url,
                    "status_code": probe.head_status,
                    "bucket": ref.bucket,
                    "storage_path": ref.storage_path,
                    "reason": probe.error or "HEAD probe returned unexpected status",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                probe.url,
                "head",
                probe.head_status,
            )

        if probe.range_status is not None and probe.range_status >= 400 and probe.range_status not in {403, 404}:
            _dedupe_append(
                storage_errors,
                storage_error_seen,
                {
                    "media_id": ref.media_id,
                    "url": probe.url,
                    "status_code": probe.range_status,
                    "bucket": ref.bucket,
                    "storage_path": ref.storage_path,
                    "reason": probe.error or "Range probe returned unexpected status",
                    "source_table": ref.source_table,
                },
                ref.media_id,
                probe.url,
                "range",
                probe.range_status,
            )

        if storage_exists and _guess_is_audio(actual_mime, ref.storage_path, ref.original_name):
            if probe.audio_stream_status is not None and probe.audio_stream_status != 206:
                _dedupe_append(
                    broken_media,
                    broken_seen,
                    {
                        "media_id": ref.media_id,
                        "storage_path": ref.storage_path,
                        "bucket": ref.bucket,
                        "reason": f"STREAMING FAILURE: audio partial range returned {probe.audio_stream_status} instead of 206",
                        "source_table": ref.source_table,
                    },
                    ref.media_id,
                    ref.source_table,
                    ref.reference_type,
                    "audio_stream_failure",
                )

    for pair in sorted(orphaned_pairs):
        obj = storage_map[pair]
        probe = probe_results.get(pair)
        actual_mime = _normalize_mime(
            obj.content_type or (probe.head_content_type if probe else None) or (probe.range_content_type if probe else None)
        )
        expected_mime = _expected_mime(obj.storage_path)
        classification, classification_reason = _classify_media(actual_mime, obj.storage_path)

        if expected_mime and actual_mime and expected_mime != actual_mime:
            _dedupe_append(
                suspicious_metadata,
                suspicious_seen,
                {
                    "media_id": None,
                    "expected_mime": expected_mime,
                    "actual_mime": actual_mime,
                    "bucket": obj.bucket,
                    "storage_path": obj.storage_path,
                    "source_table": "storage.objects",
                    "reference_type": "orphaned_storage",
                    "related_media_ids": [],
                },
                "orphan",
                obj.bucket,
                obj.storage_path,
                expected_mime,
                actual_mime,
            )

        if classification == "UNSUPPORTED_TYPE":
            unsupported_reason_counts[classification_reason] += 1
            _dedupe_append(
                unsupported_media,
                unsupported_seen,
                {
                    "media_id": None,
                    "content_type": actual_mime,
                    "reason": classification_reason,
                    "bucket": obj.bucket,
                    "storage_path": obj.storage_path,
                    "source_table": "storage.objects",
                    "reference_type": "orphaned_storage",
                    "related_media_ids": [],
                },
                "orphan",
                obj.bucket,
                obj.storage_path,
                classification_reason,
            )

    orphaned_storage_bytes = sum(max(0, obj.size_bytes or 0) for obj in storage_objects if obj.pair in orphaned_pairs)
    missing_reference_bytes = sum(max(0, row.get("size_bytes") or 0) for row in db_missing_rows)

    summary = {
        "total_media_objects": len(media_objects),
        "total_media_assets": len(media_assets),
        "total_lesson_media_rows": len(lesson_media_rows),
        "total_storage_objects": len(storage_objects),
        "total_db_reference_rows": len(references),
        "total_db_reference_pairs": len(referenced_pairs),
        "missing_files": len(missing_pairs),
        "missing_reference_rows": len(db_missing_rows),
        "mime_mismatches": len(suspicious_metadata),
        "zero_byte_files": size_flags.get("zero_byte", 0),
        "small_files_under_100_bytes": size_flags.get("tiny_file", 0),
        "missing_byte_size_rows": size_flags.get("missing_db_size", 0),
        "invalid_buckets": sum(bucket_flags.values()),
        "unsupported_formats": len(unsupported_media),
        "orphaned_files": len(orphaned_storage_files),
        "db_references_missing_in_storage": len(db_missing_rows),
        "orphaned_storage_gb": _format_gb(orphaned_storage_bytes),
        "db_missing_storage_gb": _format_gb(missing_reference_bytes),
        "total_garbage_gb": _format_gb(orphaned_storage_bytes + missing_reference_bytes),
        "orphaned_storage_pct": round((len(orphaned_storage_files) / len(storage_objects) * 100), 2)
        if storage_objects
        else 0.0,
        "valid_storage_pct": round(((len(storage_objects) - len(orphaned_storage_files)) / len(storage_objects) * 100), 2)
        if storage_objects
        else 0.0,
        "not_ready_media_assets": sum(1 for row in media_assets if (row.get("state") or "") != "ready"),
        "readonly_confirmed": readonly_confirmed,
        "probe_summary": _probe_summary(probe_results),
    }

    why_unsupported: list[dict[str, Any]] = []
    for reason, count in unsupported_reason_counts.most_common():
        why_unsupported.append({"reason": reason, "count": count})

    why_unsupported.append(
        {
            "reason": "Private buckets are validated with authenticated HEAD/GET requests. Signed URL POST generation was intentionally avoided to preserve read-only semantics.",
            "count": None,
        }
    )
    why_unsupported.append(
        {
            "reason": "lesson_media.media_asset_id being null is often a legacy/object-backed row, not automatically a corruption case.",
            "count": relation_reason_counts.get("null_media_asset_reference", 0),
        }
    )

    report = {
        "generated_at": datetime.now(UTC).isoformat(),
        "command": {
            "prod_readonly": bool(args.prod_readonly),
            "buckets": [bucket.strip() for bucket in args.buckets.split(",") if bucket.strip()],
            "http_timeout_seconds": args.http_timeout,
            "http_concurrency": args.http_concurrency,
        },
        "environment": {
            "supabase_url": args.supabase_url,
            "private_probe_mode": "authenticated" if args.supabase_secret_key else "skipped_no_secret_key",
        },
        "schema": {
            "tables_present": table_presence,
            "bucket_public_map": dict(sorted(bucket_public_map.items())),
        },
        "summary": summary,
        "why_files_appear_unsupported": why_unsupported,
        "broken_media": broken_media,
        "suspicious_metadata": suspicious_metadata,
        "storage_errors": storage_errors,
        "unsupported_media": unsupported_media,
        "orphaned_storage_files": orphaned_storage_files,
        "db_references_missing_in_storage": db_missing_rows,
        "relation_issues": relation_issues,
        "all_db_references": [asdict(ref) for ref in references],
        "all_storage_objects": [asdict(obj) for obj in storage_objects],
    }
    return report


def _md_cell(value: Any) -> str:
    text = "" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", " ")


def _markdown_table(columns: Sequence[str], rows: Sequence[dict[str, Any]]) -> str:
    if not rows:
        return "_None_\n"
    header = "| " + " | ".join(columns) + " |"
    divider = "| " + " | ".join("---" for _ in columns) + " |"
    body = [
        "| " + " | ".join(_md_cell(row.get(column)) for column in columns) + " |"
        for row in rows
    ]
    return "\n".join([header, divider, *body]) + "\n"


def _format_markdown(report: dict[str, Any]) -> str:
    summary = report["summary"]
    relation_counts = Counter(issue["reason"] for issue in report["relation_issues"])

    lines = [
        "# Media Audit Report",
        "",
        f"Generated at: {report['generated_at']}",
        "",
        "Read-only audit scope:",
        "- SELECT queries only against Postgres.",
        "- HTTP HEAD and GET probes only against Supabase Storage.",
        "- No DB writes, no storage writes, no signed-url POSTs.",
        "",
        "## SUMMARY",
        "",
        f"- total media objects: {summary['total_media_objects']}",
        f"- total media assets: {summary['total_media_assets']}",
        f"- total lesson media rows: {summary['total_lesson_media_rows']}",
        f"- total storage objects: {summary['total_storage_objects']}",
        f"- missing files: {summary['missing_files']} unique objects / {summary['missing_reference_rows']} DB rows",
        f"- mime mismatches: {summary['mime_mismatches']}",
        f"- 0 byte files: {summary['zero_byte_files']}",
        f"- tiny files (<100 bytes): {summary['small_files_under_100_bytes']}",
        f"- missing byte_size rows: {summary['missing_byte_size_rows']}",
        f"- invalid buckets: {summary['invalid_buckets']}",
        f"- unsupported formats: {summary['unsupported_formats']}",
        f"- orphaned files (storage without DB): {summary['orphaned_files']}",
        f"- DB references missing in storage: {summary['db_references_missing_in_storage']}",
        f"- orphaned storage GB: {summary['orphaned_storage_gb']}",
        f"- DB-missing storage GB: {summary['db_missing_storage_gb']}",
        f"- total GB of garbage: {summary['total_garbage_gb']}",
        f"- orphaned vs valid storage: {summary['orphaned_storage_pct']}% orphaned / {summary['valid_storage_pct']}% referenced",
        f"- not-ready media_assets: {summary['not_ready_media_assets']}",
        "",
        "## WHY FILES APPEAR \"UNSUPPORTED\"",
        "",
    ]

    for item in report["why_files_appear_unsupported"]:
        count = item.get("count")
        if count is None:
            lines.append(f"- {item['reason']}")
        else:
            lines.append(f"- {item['reason']} ({count})")

    lines.extend(
        [
            "",
            "## RELATION DIAGNOSTICS",
            "",
            f"- missing media_asset relations: {relation_counts.get('missing_media_asset_relation', 0)}",
            f"- missing media_object relations: {relation_counts.get('missing_media_object_relation', 0)}",
            f"- lesson_media.media_asset_id null: {relation_counts.get('null_media_asset_reference', 0)}",
            f"- missing course cover relations: {relation_counts.get('missing_course_cover_media_relation', 0)}",
            f"- unresolvable lesson_media rows: {relation_counts.get('unresolvable_lesson_media', 0)}",
            "",
            "## BROKEN MEDIA",
            "",
            _markdown_table(
                ["media_id", "storage_path", "bucket", "reason", "source_table"],
                report["broken_media"],
            ),
            "",
            "## SUSPICIOUS METADATA",
            "",
            _markdown_table(
                ["media_id", "expected_mime", "actual_mime", "bucket", "storage_path", "source_table"],
                report["suspicious_metadata"],
            ),
            "",
            "## STORAGE ERRORS",
            "",
            _markdown_table(
                ["media_id", "url", "status_code", "bucket", "storage_path", "reason", "source_table"],
                report["storage_errors"],
            ),
            "",
            "## UNSUPPORTED MEDIA",
            "",
            _markdown_table(
                ["media_id", "content_type", "reason", "bucket", "storage_path", "source_table"],
                report["unsupported_media"],
            ),
            "",
            "## ORPHANED STORAGE FILES",
            "",
            _markdown_table(
                ["storage_path", "bucket", "size_bytes", "content_type", "created_at"],
                report["orphaned_storage_files"],
            ),
            "",
            "## DB REFERENCES MISSING IN STORAGE",
            "",
            _markdown_table(
                ["media_id", "expected_storage_path", "bucket", "size_bytes", "source_table", "reference_type"],
                report["db_references_missing_in_storage"],
            ),
        ]
    )
    return "\n".join(lines).strip() + "\n"


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main(argv: Sequence[str] | None = None) -> int:
    _load_env()
    args = parse_args(argv)

    database_url = _ensure_db_url(args.database_url)
    if not database_url:
        print("Missing database URL. Set DATABASE_URL or SUPABASE_DB_URL, or pass --database-url.", file=sys.stderr)
        return 1
    if not args.supabase_url:
        print("Missing SUPABASE_URL. Set SUPABASE_URL or pass --supabase-url.", file=sys.stderr)
        return 1

    buckets = tuple(bucket.strip() for bucket in args.buckets.split(",") if bucket.strip())
    if not buckets:
        print("At least one bucket is required.", file=sys.stderr)
        return 1

    with _connect(database_url) as conn:
        table_presence = _fetch_table_presence(conn)
        readonly_confirmed = _readonly_confirmed(conn)
        if args.prod_readonly and not readonly_confirmed:
            print("Refusing to continue: default_transaction_read_only is not on.", file=sys.stderr)
            return 1

        media_objects = _fetch_media_objects(conn, table_presence)
        media_assets = _fetch_media_assets(conn, table_presence)
        lesson_media_rows = _fetch_lesson_media(conn, table_presence)
        courses_rows = _fetch_courses(conn, table_presence)
        storage_objects, bucket_public_map = _fetch_storage_objects(conn, table_presence, buckets)

    references = _build_references(media_objects, media_assets, lesson_media_rows)
    relation_issues = _build_relation_issues(lesson_media_rows, courses_rows)
    storage_map = {obj.pair: obj for obj in storage_objects}

    probe_results = asyncio.run(
        _probe_all(
            base_url=args.supabase_url,
            secret_key=args.supabase_secret_key,
            publishable_key=args.supabase_publishable_key,
            bucket_public_map=bucket_public_map,
            storage_objects=storage_map,
            references=references,
            timeout=args.http_timeout,
            concurrency=args.http_concurrency,
        )
    )

    report = _collect_report(
        args=args,
        table_presence=table_presence,
        readonly_confirmed=readonly_confirmed,
        media_objects=media_objects,
        media_assets=media_assets,
        lesson_media_rows=lesson_media_rows,
        courses_rows=courses_rows,
        references=references,
        relation_issues=relation_issues,
        storage_objects=storage_objects,
        bucket_public_map=bucket_public_map,
        probe_results=probe_results,
    )

    json_path = Path(args.json_out)
    md_path = Path(args.md_out)
    _write_text(json_path, json.dumps(report, indent=2, sort_keys=True))
    _write_text(md_path, _format_markdown(report))

    print(f"Wrote JSON report: {json_path}")
    print(f"Wrote Markdown report: {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
