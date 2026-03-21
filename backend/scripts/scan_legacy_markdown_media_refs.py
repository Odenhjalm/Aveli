#!/usr/bin/env python3
"""Import legacy raw Markdown lesson images into the media control plane.

This script scans `app.lessons.content_markdown` for raw Markdown image refs
like `![](https://...)`, maps them to public storage objects, and rewrites the
lesson content to canonical lesson media tokens:

* `![](https://.../public-media/lessons/<lesson_id>/images/example.png)`
  -> `!image(<lesson_media_id>)`

Safety guarantees:

* Dry-run is the default. Use `--apply` to persist changes.
* Every lesson is processed inside its own transaction.
* Failures roll back only the current lesson.
* Existing files in storage are never modified or deleted.
* Existing `media_assets` are reused by `(storage_bucket, storage_path)`.
* Existing `lesson_media` rows are reused per lesson when they already point to
  the same stored image.
* `--mode full_repair` preserves the original all-or-nothing lesson semantics.
* `--mode partial_salvage` converts only refs that already resolve through
  canonical `media_assets`, leaves true missing refs untouched, and never rolls
  back an entire lesson due to mixed state.

Supported legacy URL variants:

* `public-media/lessons/<lesson_id>/images/...`
* `public-media/<uuid>/<lesson_id>/image/...`
* duplicated prefixes like `public-media/public-media/...`
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import sys
import textwrap
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.parse import unquote, urlparse

if TYPE_CHECKING:
    import psycopg


_PUBLIC_BUCKET = "public-media"
_MARKDOWN_IMAGE_PATTERN = re.compile(
    r"""!\[[^\]]*]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)""",
    re.IGNORECASE,
)
_URL_PATH_PREFIXES = (
    "api/files/",
    "storage/v1/object/public/",
    "object/public/",
    "storage/v1/object/sign/",
    "object/sign/",
    "storage/v1/object/authenticated/",
    "object/authenticated/",
)
_MIME_ALIASES = {
    "image/jpg": "image/jpeg",
}


@dataclass(frozen=True)
class LessonRow:
    lesson_id: str
    title: str | None
    content_markdown: str
    course_id: str
    owner_id: str | None


@dataclass(frozen=True)
class LegacyMarkdownImageRef:
    raw_markdown: str
    raw_url: str
    start: int
    end: int


@dataclass(frozen=True)
class StorageObjectRef:
    bucket: str
    storage_path: str
    content_type: str
    size_bytes: int | None
    original_filename: str


@dataclass(frozen=True)
class ImportRecord:
    lesson_id: str
    title: str | None
    raw_url: str
    storage_bucket: str | None
    storage_path: str | None
    media_asset_id: str | None
    lesson_media_id: str | None
    media_asset_action: str | None
    lesson_media_action: str | None
    replacement: str | None
    status: str
    classification: str | None = None
    normalized_storage_bucket: str | None = None
    normalized_storage_path: str | None = None
    error: str | None = None


@dataclass(frozen=True)
class LessonImportResult:
    lesson_id: str
    title: str | None
    status: str
    legacy_ref_count: int
    converted_ref_count: int
    created_media_assets: int
    reused_media_assets: int
    updated_media_assets: int
    created_lesson_media: int
    reused_lesson_media: int
    records: tuple[ImportRecord, ...]
    error: str | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Examples:
              python scripts/scan_legacy_markdown_media_refs.py --dry-run
              python scripts/scan_legacy_markdown_media_refs.py --apply \
                --db-url "$SUPABASE_DB_URL"
            """
        ),
    )
    parser.add_argument(
        "--db-url",
        default=os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL"),
        help="Postgres connection url (default: SUPABASE_DB_URL or DATABASE_URL)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without writing to the database (default)",
    )
    mode.add_argument(
        "--apply",
        action="store_true",
        help="Persist media rows and lesson markdown updates",
    )
    parser.add_argument(
        "--format",
        choices=("tsv", "json"),
        default="tsv",
        help="Output format (default: tsv).",
    )
    parser.add_argument(
        "--mode",
        choices=("full_repair", "partial_salvage"),
        default="full_repair",
        help=(
            "Repair strategy. "
            "`full_repair` preserves the original lesson-atomic importer; "
            "`partial_salvage` converts only refs already backed by canonical media_assets."
        ),
    )
    return parser.parse_args()


def _ensure_db_url(url: str | None) -> str:
    if not url:
        raise SystemExit("Missing database url (--db-url or SUPABASE_DB_URL / DATABASE_URL)")
    if "sslmode=" in url:
        return url
    parsed = urlparse(url)
    hostname = (parsed.hostname or "").strip().lower()
    if hostname in {"localhost", "127.0.0.1", "::1"}:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}sslmode=require"


def _import_psycopg():
    try:
        import psycopg
    except ModuleNotFoundError as exc:  # pragma: no cover - environment-specific
        raise SystemExit(
            "Missing dependency: psycopg. Install backend dependencies before running this script."
        ) from exc
    return psycopg


def _normalize_mime(value: str | None) -> str | None:
    raw = str(value or "").strip().lower()
    if not raw:
        return None
    raw = raw.split(";", 1)[0].strip()
    return _MIME_ALIASES.get(raw, raw)


def _coerce_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def extract_legacy_markdown_image_refs(
    markdown: str,
) -> tuple[LegacyMarkdownImageRef, ...]:
    refs: list[LegacyMarkdownImageRef] = []
    for match in _MARKDOWN_IMAGE_PATTERN.finditer(markdown or ""):
        raw_url = (match.group(1) or "").strip()
        raw_markdown = (match.group(0) or "").strip()
        if not raw_url or not raw_markdown:
            continue
        refs.append(
            LegacyMarkdownImageRef(
                raw_markdown=raw_markdown,
                raw_url=raw_url,
                start=match.start(),
                end=match.end(),
            )
        )
    return tuple(refs)


def derive_public_storage_path_candidates(raw_url: str) -> tuple[str, ...]:
    raw = str(raw_url or "").strip()
    if not raw:
        return ()

    parsed = urlparse(raw)
    candidate = parsed.path if parsed.scheme in {"http", "https"} or parsed.netloc else raw
    candidate = unquote(candidate).replace("\\", "/").lstrip("/")
    candidate = re.sub(r"/{2,}", "/", candidate)
    for prefix in _URL_PATH_PREFIXES:
        if candidate.startswith(prefix):
            candidate = candidate[len(prefix) :].lstrip("/")
            break

    bucket_prefix = f"{_PUBLIC_BUCKET}/"
    if not candidate.startswith(bucket_prefix):
        return ()

    key = candidate[len(bucket_prefix) :].lstrip("/")
    if not key:
        return ()

    variants: list[str] = []
    current = key
    while current:
        variants.append(current)
        if not current.startswith(bucket_prefix):
            break
        current = current[len(bucket_prefix) :].lstrip("/")

    ordered: list[str] = []
    for variant in reversed(variants):
        if variant not in ordered:
            ordered.append(variant)
    return tuple(ordered)


def rewrite_markdown_with_image_tokens(
    markdown: str,
    replacements: list[tuple[LegacyMarkdownImageRef, str]],
) -> str:
    if not replacements:
        return markdown

    parts: list[str] = []
    cursor = 0
    for ref, replacement in sorted(replacements, key=lambda item: item[0].start):
        parts.append(markdown[cursor : ref.start])
        parts.append(replacement)
        cursor = ref.end
    parts.append(markdown[cursor:])
    return "".join(parts)


def _storage_equivalent_keys(bucket: str, storage_path: str) -> tuple[str, ...]:
    normalized_bucket = str(bucket or "").strip().strip("/")
    normalized_path = str(storage_path or "").strip().lstrip("/")
    if not normalized_bucket or not normalized_path:
        return ()

    prefix = f"{normalized_bucket}/"
    keys: list[str] = []

    def _add(value: str) -> None:
        candidate = value.strip().lstrip("/")
        if candidate and candidate not in keys:
            keys.append(candidate)

    _add(normalized_path)
    current = normalized_path
    while current.startswith(prefix):
        current = current[len(prefix) :].lstrip("/")
        _add(current)
    if not normalized_path.startswith(prefix):
        _add(f"{normalized_bucket}/{normalized_path}")
    return tuple(keys)


def _format_field(value: str | None, *, empty: str = "") -> str:
    compact = " ".join((value or "").split())
    return compact or empty


def _fetch_lessons(conn: "psycopg.Connection") -> list[LessonRow]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT
              l.id::text AS lesson_id,
              l.title,
              COALESCE(l.content_markdown, '') AS content_markdown,
              l.course_id::text AS course_id,
              c.created_by::text AS owner_id
            FROM app.lessons l
            JOIN app.courses c ON c.id = l.course_id
            WHERE COALESCE(l.content_markdown, '') <> ''
            ORDER BY l.id
            """
        )
        return [
            LessonRow(
                lesson_id=str(row["lesson_id"]),
                title=row["title"],
                content_markdown=row["content_markdown"],
                course_id=str(row["course_id"]),
                owner_id=str(row["owner_id"]) if row.get("owner_id") else None,
            )
            for row in cur.fetchall()
        ]


def _load_storage_object_candidates(
    cur: Any,
    *,
    bucket: str,
    candidate_paths: tuple[str, ...],
    cache: dict[tuple[str, str], dict[str, Any] | None],
) -> None:
    unresolved = [
        candidate_path
        for candidate_path in candidate_paths
        if (bucket, candidate_path) not in cache
    ]
    if not unresolved:
        return

    cur.execute(
        """
        SELECT
          o.bucket_id,
          o.name,
          o.metadata
        FROM storage.objects o
        WHERE o.bucket_id = %s
          AND o.name = ANY(%s::text[])
        """,
        (bucket, list(unresolved)),
    )
    rows = cur.fetchall()
    found: dict[str, dict[str, Any]] = {str(row["name"]): dict(row) for row in rows}
    for candidate_path in unresolved:
        cache[(bucket, candidate_path)] = found.get(candidate_path)


def _resolve_storage_object(
    cur: Any,
    *,
    raw_url: str,
    cache: dict[tuple[str, str], dict[str, Any] | None],
) -> StorageObjectRef:
    candidate_paths = derive_public_storage_path_candidates(raw_url)
    if not candidate_paths:
        raise ValueError("legacy_image_url_not_in_public_media")

    _load_storage_object_candidates(
        cur,
        bucket=_PUBLIC_BUCKET,
        candidate_paths=candidate_paths,
        cache=cache,
    )

    chosen_row: dict[str, Any] | None = None
    chosen_path: str | None = None
    for candidate_path in candidate_paths:
        cached = cache.get((_PUBLIC_BUCKET, candidate_path))
        if cached is None:
            continue
        chosen_row = cached
        chosen_path = candidate_path
        break

    if chosen_row is None or chosen_path is None:
        raise ValueError("storage_object_missing")

    metadata = chosen_row.get("metadata") or {}
    content_type = _normalize_mime(metadata.get("mimetype"))
    if content_type is None:
        guessed_type, _ = mimetypes.guess_type(chosen_path)
        content_type = _normalize_mime(guessed_type)
    if content_type is None or not content_type.startswith("image/"):
        raise ValueError("storage_object_not_image")

    return StorageObjectRef(
        bucket=_PUBLIC_BUCKET,
        storage_path=chosen_path,
        content_type=content_type,
        size_bytes=_coerce_int(metadata.get("size") or metadata.get("contentLength")),
        original_filename=Path(chosen_path).name,
    )


def _fetch_existing_lesson_media(cur: Any, lesson_id: str) -> list[dict[str, Any]]:
    cur.execute(
        """
        SELECT
          lm.id::text AS lesson_media_id,
          lower(coalesce(lm.kind, '')) AS kind,
          lm.media_id::text AS media_id,
          lm.media_asset_id::text AS media_asset_id,
          lm.storage_path AS lesson_storage_path,
          lm.storage_bucket AS lesson_storage_bucket,
          lm.position,
          CASE
            WHEN ma.id IS NOT NULL AND ma.state = 'ready'
              THEN coalesce(ma.streaming_object_path, ma.original_object_path, mo.storage_path, lm.storage_path)
            WHEN ma.id IS NOT NULL AND lower(coalesce(ma.media_type, '')) = 'audio'
              THEN coalesce(mo.storage_path, lm.storage_path)
            ELSE coalesce(mo.storage_path, lm.storage_path, ma.original_object_path)
          END AS effective_storage_path,
          CASE
            WHEN ma.id IS NOT NULL AND ma.state = 'ready'
              THEN coalesce(ma.streaming_storage_bucket, ma.storage_bucket, mo.storage_bucket, lm.storage_bucket, 'lesson-media')
            WHEN ma.id IS NOT NULL AND lower(coalesce(ma.media_type, '')) = 'audio'
              THEN coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media')
            ELSE coalesce(mo.storage_bucket, lm.storage_bucket, ma.storage_bucket, 'lesson-media')
          END AS effective_storage_bucket
        FROM app.lesson_media lm
        LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
        LEFT JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        WHERE lm.lesson_id = %s
        ORDER BY lm.position ASC, lm.id ASC
        """,
        (lesson_id,),
    )
    return [dict(row) for row in cur.fetchall()]


def _match_existing_lesson_media(
    existing_rows: list[dict[str, Any]],
    *,
    media_asset_id: str | None = None,
    bucket: str,
    storage_path: str,
) -> dict[str, Any] | None:
    candidate_keys = set(_storage_equivalent_keys(bucket, storage_path))
    normalized_media_asset_id = str(media_asset_id or "").strip()
    if not candidate_keys and not normalized_media_asset_id:
        return None

    for row in existing_rows:
        if str(row.get("kind") or "").strip().lower() != "image":
            continue
        if normalized_media_asset_id and str(row.get("media_asset_id") or "").strip() == normalized_media_asset_id:
            return row
        row_bucket = str(
            row.get("effective_storage_bucket")
            or row.get("lesson_storage_bucket")
            or ""
        ).strip()
        row_path = str(
            row.get("effective_storage_path")
            or row.get("lesson_storage_path")
            or ""
        ).strip()
        if row_bucket != bucket or not row_path:
            continue
        row_keys = set(_storage_equivalent_keys(row_bucket, row_path))
        if candidate_keys.intersection(row_keys):
            return row
    return None


def _select_media_asset(
    cur: Any,
    *,
    bucket: str,
    storage_path: str,
    for_update: bool = True,
) -> dict[str, Any] | None:
    candidate_keys = _storage_equivalent_keys(bucket, storage_path)
    if not candidate_keys:
        return None

    lock_clause = " FOR UPDATE" if for_update else ""
    cur.execute(
        f"""
        SELECT
          id::text AS id,
          owner_id::text AS owner_id,
          course_id::text AS course_id,
          lesson_id::text AS lesson_id,
          lower(coalesce(media_type, '')) AS media_type,
          lower(coalesce(purpose, '')) AS purpose,
          lower(coalesce(state, '')) AS state,
          storage_bucket,
          original_object_path,
          original_content_type,
          original_filename,
          original_size_bytes,
          streaming_object_path,
          streaming_storage_bucket,
          streaming_format,
          ingest_format,
          created_at
        FROM app.media_assets
        WHERE (
            storage_bucket = %s
            AND original_object_path = ANY(%s::text[])
          )
           OR (
            coalesce(streaming_storage_bucket, storage_bucket) = %s
            AND coalesce(streaming_object_path, original_object_path) = ANY(%s::text[])
          )
        ORDER BY
          CASE WHEN lower(coalesce(media_type, '')) = 'image' THEN 0 ELSE 1 END,
          CASE WHEN lower(coalesce(state, '')) = 'ready' THEN 0 ELSE 1 END,
          CASE WHEN lower(coalesce(purpose, '')) = 'lesson_media' THEN 0 ELSE 1 END,
          created_at ASC,
          id ASC
        LIMIT 1{lock_clause}
        """,
        (bucket, list(candidate_keys), bucket, list(candidate_keys)),
    )
    row = cur.fetchone()
    return dict(row) if row else None


def _ingest_format(storage_path: str, content_type: str) -> str:
    suffix = Path(storage_path).suffix.lower().lstrip(".")
    if suffix:
        return suffix
    normalized_type = _normalize_mime(content_type) or ""
    if "/" in normalized_type:
        return normalized_type.split("/", 1)[1].split("+", 1)[0]
    return "bin"


def _ensure_media_asset(
    cur: Any,
    *,
    lesson: LessonRow,
    storage_object: StorageObjectRef,
) -> tuple[dict[str, Any], str]:
    existing = _select_media_asset(
        cur,
        bucket=storage_object.bucket,
        storage_path=storage_object.storage_path,
    )
    desired_ingest_format = _ingest_format(
        storage_object.storage_path,
        storage_object.content_type,
    )

    if existing is not None:
        if existing.get("media_type") not in {"", "image"}:
            raise ValueError("existing_media_asset_is_not_image")

        needs_update = any(
            (
                existing.get("state") != "ready",
                str(existing.get("storage_bucket") or "").strip() != storage_object.bucket,
                str(existing.get("original_object_path") or "").strip()
                != storage_object.storage_path,
                str(existing.get("streaming_object_path") or "").strip()
                != storage_object.storage_path,
                str(existing.get("streaming_storage_bucket") or "").strip()
                != storage_object.bucket,
                str(existing.get("streaming_format") or "").strip()
                != desired_ingest_format,
                str(existing.get("ingest_format") or "").strip() != desired_ingest_format,
                _normalize_mime(existing.get("original_content_type"))
                != storage_object.content_type,
                not str(existing.get("original_filename") or "").strip(),
                existing.get("original_size_bytes") is None
                and storage_object.size_bytes is not None,
                existing.get("owner_id") is None and lesson.owner_id is not None,
                existing.get("course_id") is None,
                existing.get("lesson_id") is None,
            )
        )
        if not needs_update:
            return existing, "reused_existing"

        cur.execute(
            """
            UPDATE app.media_assets
            SET
              owner_id = coalesce(owner_id, %s::uuid),
              course_id = coalesce(course_id, %s::uuid),
              lesson_id = coalesce(lesson_id, %s::uuid),
              media_type = 'image',
              ingest_format = %s,
              original_object_path = %s,
              original_content_type = %s,
              original_filename = coalesce(original_filename, %s),
              original_size_bytes = coalesce(original_size_bytes, %s),
              storage_bucket = %s,
              streaming_object_path = %s,
              streaming_storage_bucket = %s,
              streaming_format = %s,
              duration_seconds = null,
              codec = null,
              state = 'ready',
              error_message = null,
              next_retry_at = null,
              processing_locked_at = null,
              updated_at = now()
            WHERE id = %s::uuid
            RETURNING
              id::text AS id,
              owner_id::text AS owner_id,
              course_id::text AS course_id,
              lesson_id::text AS lesson_id,
              lower(coalesce(media_type, '')) AS media_type,
              lower(coalesce(purpose, '')) AS purpose,
              lower(coalesce(state, '')) AS state,
              storage_bucket,
              original_object_path,
              original_content_type,
              original_filename,
              original_size_bytes,
              streaming_object_path,
              streaming_storage_bucket,
              streaming_format,
              ingest_format
            """,
            (
                lesson.owner_id,
                lesson.course_id,
                lesson.lesson_id,
                desired_ingest_format,
                storage_object.storage_path,
                storage_object.content_type,
                storage_object.original_filename,
                storage_object.size_bytes,
                storage_object.bucket,
                storage_object.storage_path,
                storage_object.bucket,
                desired_ingest_format,
                existing["id"],
            ),
        )
        updated = cur.fetchone()
        return dict(updated), "updated_existing"

    cur.execute(
        """
        INSERT INTO app.media_assets (
          owner_id,
          course_id,
          lesson_id,
          media_type,
          purpose,
          ingest_format,
          original_object_path,
          original_content_type,
          original_filename,
          original_size_bytes,
          storage_bucket,
          streaming_object_path,
          streaming_storage_bucket,
          streaming_format,
          duration_seconds,
          codec,
          state,
          error_message,
          processing_attempts,
          processing_locked_at,
          next_retry_at,
          updated_at
        )
        VALUES (
          %s::uuid,
          %s::uuid,
          %s::uuid,
          'image',
          'lesson_media',
          %s,
          %s,
          %s,
          %s,
          %s,
          %s,
          %s,
          %s,
          %s,
          null,
          null,
          'ready',
          null,
          0,
          null,
          null,
          now()
        )
        RETURNING
          id::text AS id,
          owner_id::text AS owner_id,
          course_id::text AS course_id,
          lesson_id::text AS lesson_id,
          lower(coalesce(media_type, '')) AS media_type,
          lower(coalesce(purpose, '')) AS purpose,
          lower(coalesce(state, '')) AS state,
          storage_bucket,
          original_object_path,
          original_content_type,
          original_filename,
          original_size_bytes,
          streaming_object_path,
          streaming_storage_bucket,
          streaming_format,
          ingest_format
        """,
        (
            lesson.owner_id,
            lesson.course_id,
            lesson.lesson_id,
            desired_ingest_format,
            storage_object.storage_path,
            storage_object.content_type,
            storage_object.original_filename,
            storage_object.size_bytes,
            storage_object.bucket,
            storage_object.storage_path,
            storage_object.bucket,
            desired_ingest_format,
        ),
    )
    created = cur.fetchone()
    return dict(created), "created_new"


def _update_existing_lesson_media(
    cur: Any,
    *,
    row: dict[str, Any],
    media_asset_id: str,
    storage_object: StorageObjectRef,
) -> tuple[dict[str, Any], str]:
    needs_update = any(
        (
            str(row.get("kind") or "").strip().lower() != "image",
            str(row.get("lesson_storage_path") or "").strip() != storage_object.storage_path,
            str(row.get("lesson_storage_bucket") or "").strip() != storage_object.bucket,
            str(row.get("media_asset_id") or "").strip() != media_asset_id,
        )
    )
    if not needs_update:
        return row, "reused_existing"

    cur.execute(
        """
        UPDATE app.lesson_media
        SET
          kind = 'image',
          storage_path = %s,
          storage_bucket = %s,
          media_asset_id = %s::uuid
        WHERE id = %s::uuid
        RETURNING
          id::text AS lesson_media_id,
          lower(coalesce(kind, '')) AS kind,
          media_id::text AS media_id,
          media_asset_id::text AS media_asset_id,
          storage_path AS lesson_storage_path,
          storage_bucket AS lesson_storage_bucket,
          position,
          storage_path AS effective_storage_path,
          storage_bucket AS effective_storage_bucket
        """,
        (
            storage_object.storage_path,
            storage_object.bucket,
            media_asset_id,
            row["lesson_media_id"],
        ),
    )
    updated = cur.fetchone()
    return dict(updated), "updated_existing"


def _next_lesson_media_position(cur: Any, lesson_id: str) -> int:
    cur.execute(
        """
        SELECT COALESCE(MAX(position), -1) + 1 AS next_position
        FROM app.lesson_media
        WHERE lesson_id = %s::uuid
        """,
        (lesson_id,),
    )
    row = cur.fetchone()
    return int(row["next_position"]) if row and row.get("next_position") is not None else 0


def _create_lesson_media(
    cur: Any,
    *,
    lesson_id: str,
    media_asset_id: str,
    storage_object: StorageObjectRef,
) -> dict[str, Any]:
    next_position = _next_lesson_media_position(cur, lesson_id)
    cur.execute(
        """
        INSERT INTO app.lesson_media (
          lesson_id,
          kind,
          media_id,
          storage_path,
          storage_bucket,
          duration_seconds,
          position,
          media_asset_id
        )
        VALUES (
          %s::uuid,
          'image',
          null,
          %s,
          %s,
          null,
          %s,
          %s::uuid
        )
        RETURNING
          id::text AS lesson_media_id,
          'image' AS kind,
          null::text AS media_id,
          %s::text AS media_asset_id,
          %s::text AS lesson_storage_path,
          %s::text AS lesson_storage_bucket,
          %s::int AS position,
          %s::text AS effective_storage_path,
          %s::text AS effective_storage_bucket
        """,
        (
            lesson_id,
            storage_object.storage_path,
            storage_object.bucket,
            next_position,
            media_asset_id,
            media_asset_id,
            storage_object.storage_path,
            storage_object.bucket,
            next_position,
            storage_object.storage_path,
            storage_object.bucket,
        ),
    )
    row = cur.fetchone()
    return dict(row)


def _upsert_runtime_media_for_lesson_media(cur: Any, lesson_media_id: str) -> None:
    cur.execute(
        "SELECT app.upsert_runtime_media_for_lesson_media(%s::uuid)",
        (lesson_media_id,),
    )


def _import_lesson_images(
    cur: Any,
    *,
    lesson: LessonRow,
    refs: tuple[LegacyMarkdownImageRef, ...],
    storage_cache: dict[tuple[str, str], dict[str, Any] | None],
) -> LessonImportResult:
    existing_lesson_media = _fetch_existing_lesson_media(cur, lesson.lesson_id)
    replacement_map: dict[tuple[str, str], tuple[str, str, str, str]] = {}
    replacements: list[tuple[LegacyMarkdownImageRef, str]] = []
    records: list[ImportRecord] = []
    created_media_assets = 0
    reused_media_assets = 0
    updated_media_assets = 0
    created_lesson_media = 0
    reused_lesson_media = 0

    for ref in refs:
        storage_object = _resolve_storage_object(
            cur,
            raw_url=ref.raw_url,
            cache=storage_cache,
        )
        pair = (storage_object.bucket, storage_object.storage_path)
        resolved = replacement_map.get(pair)
        if resolved is None:
            media_asset, media_asset_action = _ensure_media_asset(
                cur,
                lesson=lesson,
                storage_object=storage_object,
            )
            existing_row = _match_existing_lesson_media(
                existing_lesson_media,
                bucket=storage_object.bucket,
                storage_path=storage_object.storage_path,
            )
            if existing_row is not None:
                lesson_media_row, lesson_media_action = _update_existing_lesson_media(
                    cur,
                    row=existing_row,
                    media_asset_id=media_asset["id"],
                    storage_object=storage_object,
                )
            else:
                lesson_media_row = _create_lesson_media(
                    cur,
                    lesson_id=lesson.lesson_id,
                    media_asset_id=media_asset["id"],
                    storage_object=storage_object,
                )
                existing_lesson_media.append(lesson_media_row)
                lesson_media_action = "created_new"

            if media_asset_action == "created_new":
                created_media_assets += 1
            elif media_asset_action == "updated_existing":
                updated_media_assets += 1
            else:
                reused_media_assets += 1

            if lesson_media_action == "created_new":
                created_lesson_media += 1
            else:
                reused_lesson_media += 1

            resolved = (
                media_asset["id"],
                media_asset_action,
                lesson_media_row["lesson_media_id"],
                lesson_media_action,
            )
            replacement_map[pair] = resolved

        media_asset_id, media_asset_action, lesson_media_id, lesson_media_action = resolved
        replacement = f"!image({lesson_media_id})"
        replacements.append((ref, replacement))
        records.append(
            ImportRecord(
                lesson_id=lesson.lesson_id,
                title=lesson.title,
                raw_url=ref.raw_url,
                storage_bucket=storage_object.bucket,
                storage_path=storage_object.storage_path,
                media_asset_id=media_asset_id,
                lesson_media_id=lesson_media_id,
                media_asset_action=media_asset_action,
                lesson_media_action=lesson_media_action,
                replacement=replacement,
                status="pending",
            )
        )

    updated_markdown = rewrite_markdown_with_image_tokens(
        lesson.content_markdown,
        replacements,
    )
    remaining_refs = extract_legacy_markdown_image_refs(updated_markdown)
    if remaining_refs:
        raise ValueError("remaining_raw_markdown_image_refs")

    cur.execute(
        """
        UPDATE app.lessons
        SET content_markdown = %s,
            updated_at = now()
        WHERE id = %s::uuid
        """,
        (updated_markdown, lesson.lesson_id),
    )

    return LessonImportResult(
        lesson_id=lesson.lesson_id,
        title=lesson.title,
        status="pending",
        legacy_ref_count=len(refs),
        converted_ref_count=len(records),
        created_media_assets=created_media_assets,
        reused_media_assets=reused_media_assets,
        updated_media_assets=updated_media_assets,
        created_lesson_media=created_lesson_media,
        reused_lesson_media=reused_lesson_media,
        records=tuple(records),
    )


def _import_lesson_images_partial_salvage(
    cur: Any,
    *,
    lesson: LessonRow,
    refs: tuple[LegacyMarkdownImageRef, ...],
    storage_cache: dict[tuple[str, str], dict[str, Any] | None],
) -> LessonImportResult:
    existing_lesson_media = _fetch_existing_lesson_media(cur, lesson.lesson_id)
    replacement_map: dict[tuple[str, str], tuple[str, str, str, str, str, str]] = {}
    replacements: list[tuple[LegacyMarkdownImageRef, str]] = []
    records: list[ImportRecord] = []
    created_media_assets = 0
    reused_media_assets = 0
    updated_media_assets = 0
    created_lesson_media = 0
    reused_lesson_media = 0

    for ref in refs:
        normalized_candidates = derive_public_storage_path_candidates(ref.raw_url)
        try:
            storage_object = _resolve_storage_object(
                cur,
                raw_url=ref.raw_url,
                cache=storage_cache,
            )
        except ValueError as exc:
            records.append(
                ImportRecord(
                    lesson_id=lesson.lesson_id,
                    title=lesson.title,
                    raw_url=ref.raw_url,
                    storage_bucket=None,
                    storage_path=None,
                    media_asset_id=None,
                    lesson_media_id=None,
                    media_asset_action=None,
                    lesson_media_action=None,
                    replacement=None,
                    status="pending",
                    classification="missing",
                    normalized_storage_bucket=_PUBLIC_BUCKET,
                    normalized_storage_path=normalized_candidates[0] if normalized_candidates else None,
                    error=str(exc),
                )
            )
            continue

        resolved = replacement_map.get((storage_object.bucket, storage_object.storage_path))
        if resolved is None:
            media_asset, media_asset_action = _ensure_media_asset(
                cur,
                lesson=lesson,
                storage_object=storage_object,
            )
            media_asset_id = str(media_asset["id"])
            existing_row = _match_existing_lesson_media(
                existing_lesson_media,
                media_asset_id=media_asset_id,
                bucket=storage_object.bucket,
                storage_path=storage_object.storage_path,
            )
            if existing_row is not None:
                lesson_media_row, lesson_media_action = _update_existing_lesson_media(
                    cur,
                    row=existing_row,
                    media_asset_id=media_asset_id,
                    storage_object=storage_object,
                )
                reused_lesson_media += 1
            else:
                lesson_media_row = _create_lesson_media(
                    cur,
                    lesson_id=lesson.lesson_id,
                    media_asset_id=media_asset_id,
                    storage_object=storage_object,
                )
                existing_lesson_media.append(lesson_media_row)
                lesson_media_action = "created_new"
                created_lesson_media += 1

            _upsert_runtime_media_for_lesson_media(
                cur,
                str(lesson_media_row["lesson_media_id"]),
            )
            if media_asset_action == "created_new":
                created_media_assets += 1
            elif media_asset_action == "updated_existing":
                updated_media_assets += 1
            else:
                reused_media_assets += 1
            resolved = (
                media_asset_id,
                media_asset_action,
                str(lesson_media_row["lesson_media_id"]),
                lesson_media_action,
                storage_object.bucket,
                storage_object.storage_path,
            )
            replacement_map[(storage_object.bucket, storage_object.storage_path)] = resolved

        (
            resolved_media_asset_id,
            media_asset_action,
            lesson_media_id,
            lesson_media_action,
            resolved_bucket,
            resolved_path,
        ) = resolved
        replacement = f"!image({lesson_media_id})"
        replacements.append((ref, replacement))
        records.append(
            ImportRecord(
                lesson_id=lesson.lesson_id,
                title=lesson.title,
                raw_url=ref.raw_url,
                storage_bucket=resolved_bucket,
                storage_path=resolved_path,
                media_asset_id=resolved_media_asset_id,
                lesson_media_id=lesson_media_id,
                media_asset_action=media_asset_action,
                lesson_media_action=lesson_media_action,
                replacement=replacement,
                status="pending",
                classification="resolvable",
                normalized_storage_bucket=storage_object.bucket,
                normalized_storage_path=storage_object.storage_path,
            )
        )

    updated_markdown = rewrite_markdown_with_image_tokens(
        lesson.content_markdown,
        replacements,
    )
    remaining_refs = extract_legacy_markdown_image_refs(updated_markdown)
    for remaining_ref in remaining_refs:
        try:
            _resolve_storage_object(
                cur,
                raw_url=remaining_ref.raw_url,
                cache=storage_cache,
            )
        except ValueError as exc:
            if str(exc) in {"storage_object_missing", "legacy_image_url_not_in_public_media"}:
                continue
            raise
        raise ValueError("partial_salvage_left_resolvable_ref")

    if replacements and updated_markdown != lesson.content_markdown:
        cur.execute(
            """
            UPDATE app.lessons
            SET content_markdown = %s,
                updated_at = now()
            WHERE id = %s::uuid
            """,
            (updated_markdown, lesson.lesson_id),
        )

    return LessonImportResult(
        lesson_id=lesson.lesson_id,
        title=lesson.title,
        status="pending",
        legacy_ref_count=len(refs),
        converted_ref_count=len(replacements),
        created_media_assets=created_media_assets,
        reused_media_assets=reused_media_assets,
        updated_media_assets=updated_media_assets,
        created_lesson_media=created_lesson_media,
        reused_lesson_media=reused_lesson_media,
        records=tuple(records),
    )


def _with_status(result: LessonImportResult, *, status: str, error: str | None = None) -> LessonImportResult:
    updated_records = tuple(
        ImportRecord(
            lesson_id=record.lesson_id,
            title=record.title,
            raw_url=record.raw_url,
            storage_bucket=record.storage_bucket,
            storage_path=record.storage_path,
            media_asset_id=record.media_asset_id,
            lesson_media_id=record.lesson_media_id,
            media_asset_action=record.media_asset_action,
            lesson_media_action=record.lesson_media_action,
            replacement=record.replacement,
            status=status,
            classification=record.classification,
            normalized_storage_bucket=record.normalized_storage_bucket,
            normalized_storage_path=record.normalized_storage_path,
            error=error if error is not None else record.error,
        )
        for record in result.records
    )
    return LessonImportResult(
        lesson_id=result.lesson_id,
        title=result.title,
        status=status,
        legacy_ref_count=result.legacy_ref_count,
        converted_ref_count=result.converted_ref_count,
        created_media_assets=result.created_media_assets,
        reused_media_assets=result.reused_media_assets,
        updated_media_assets=result.updated_media_assets,
        created_lesson_media=result.created_lesson_media,
        reused_lesson_media=result.reused_lesson_media,
        records=updated_records,
        error=error,
    )


def _failed_result(
    lesson: LessonRow,
    refs: tuple[LegacyMarkdownImageRef, ...],
    *,
    error: str,
) -> LessonImportResult:
    return LessonImportResult(
        lesson_id=lesson.lesson_id,
        title=lesson.title,
        status="failed",
        legacy_ref_count=len(refs),
        converted_ref_count=0,
        created_media_assets=0,
        reused_media_assets=0,
        updated_media_assets=0,
        created_lesson_media=0,
        reused_lesson_media=0,
        records=tuple(
            ImportRecord(
                lesson_id=lesson.lesson_id,
                title=lesson.title,
                raw_url=ref.raw_url,
                storage_bucket=None,
                storage_path=None,
                media_asset_id=None,
                lesson_media_id=None,
                media_asset_action=None,
                lesson_media_action=None,
                replacement=None,
                status="failed",
                classification=None,
                normalized_storage_bucket=None,
                normalized_storage_path=None,
                error=error,
            )
            for ref in refs
        ),
        error=error,
    )


def process_lessons(
    conn: "psycopg.Connection",
    *,
    apply: bool,
    mode: str,
) -> list[LessonImportResult]:
    storage_cache: dict[tuple[str, str], dict[str, Any] | None] = {}
    results: list[LessonImportResult] = []

    for lesson in _fetch_lessons(conn):
        refs = extract_legacy_markdown_image_refs(lesson.content_markdown)
        if not refs:
            continue

        conn.execute("BEGIN")
        try:
            with conn.cursor() as cur:
                if mode == "partial_salvage":
                    pending = _import_lesson_images_partial_salvage(
                        cur,
                        lesson=lesson,
                        refs=refs,
                        storage_cache=storage_cache,
                    )
                else:
                    pending = _import_lesson_images(
                        cur,
                        lesson=lesson,
                        refs=refs,
                        storage_cache=storage_cache,
                    )
            if apply:
                conn.execute("COMMIT")
                results.append(_with_status(pending, status="applied"))
            else:
                conn.execute("ROLLBACK")
                results.append(_with_status(pending, status="planned"))
        except Exception as exc:
            conn.execute("ROLLBACK")
            results.append(_failed_result(lesson, refs, error=str(exc)))

    return results


def summarize_results(results: list[LessonImportResult]) -> dict[str, int]:
    return {
        "lessons_touched": len(results),
        "lessons_failed": sum(1 for result in results if result.status == "failed"),
        "legacy_refs_found": sum(result.legacy_ref_count for result in results),
        "legacy_refs_converted": sum(result.converted_ref_count for result in results),
        "media_assets_created": sum(result.created_media_assets for result in results),
        "media_assets_reused": sum(result.reused_media_assets for result in results),
        "media_assets_updated": sum(result.updated_media_assets for result in results),
        "lesson_media_created": sum(result.created_lesson_media for result in results),
        "lesson_media_reused": sum(result.reused_lesson_media for result in results),
    }


def summarize_partial_salvage(results: list[LessonImportResult]) -> dict[str, int]:
    records = [record for result in results for record in result.records]
    missing_by_lesson: dict[str, int] = {}
    for record in records:
        if record.classification == "missing":
            missing_by_lesson[record.lesson_id] = missing_by_lesson.get(record.lesson_id, 0) + 1

    return {
        "lessons_processed": len(results),
        "refs_total": sum(result.legacy_ref_count for result in results),
        "resolvable_refs": sum(1 for record in records if record.classification == "resolvable"),
        "missing_refs": sum(1 for record in records if record.classification == "missing"),
        "would_convert": sum(result.converted_ref_count for result in results),
        "would_leave_untouched": sum(1 for record in records if record.classification == "missing"),
        "lessons_fully_cleaned": sum(
            1 for result in results if result.lesson_id not in missing_by_lesson
        ),
        "lessons_still_blocked": len(missing_by_lesson),
        "remaining_raw_refs": sum(1 for record in records if record.classification == "missing"),
    }


def print_tsv(results: list[LessonImportResult]) -> None:
    print(
        "\t".join(
            (
                "lesson_id",
                "title",
                "raw_url",
                "storage_bucket",
                "storage_path",
                "media_asset_id",
                "lesson_media_id",
                "media_asset_action",
                "lesson_media_action",
                "replacement",
                "status",
                "error",
            )
        )
    )
    for result in results:
        for record in result.records:
            print(
                "\t".join(
                    (
                        record.lesson_id,
                        _format_field(record.title, empty="<untitled>"),
                        record.raw_url,
                        record.storage_bucket or "",
                        record.storage_path or "",
                        record.media_asset_id or "",
                        record.lesson_media_id or "",
                        record.media_asset_action or "",
                        record.lesson_media_action or "",
                        record.replacement or "",
                        record.status,
                        record.error or "",
                    )
                )
            )


def print_json(results: list[LessonImportResult], *, mode: str) -> None:
    summary = summarize_results(results)
    payload = {
        "mode": mode,
        "summary": summary,
        "results": [asdict(result) for result in results],
    }
    if mode == "partial_salvage":
        payload["partial_salvage_summary"] = summarize_partial_salvage(results)
    print(json.dumps(payload, ensure_ascii=True, indent=2))


def main() -> None:
    args = parse_args()
    db_url = _ensure_db_url(args.db_url)
    psycopg = _import_psycopg()

    connect_kwargs: dict[str, Any] = {
        "autocommit": True,
        "row_factory": psycopg.rows.dict_row,
    }

    with psycopg.connect(db_url, **connect_kwargs) as conn:
        results = process_lessons(conn, apply=bool(args.apply), mode=args.mode)

    if args.format == "json":
        print_json(results, mode=args.mode)
    else:
        print_tsv(results)

    failed = [result for result in results if result.status == "failed"]
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
