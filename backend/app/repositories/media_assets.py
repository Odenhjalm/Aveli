from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any, Iterable

from psycopg import errors
from psycopg.rows import dict_row

from ..db import get_conn, pool

logger = logging.getLogger(__name__)


class MediaAssetReadyAuthorityError(PermissionError):
    """Raised when non-worker code attempts to mark a media asset ready."""


def _test_visibility_clause(alias: str) -> str:
    return f"app.is_test_row_visible({alias}.is_test, {alias}.test_session_id)"


async def create_media_asset(
    *,
    owner_id: str | None,
    course_id: str | None,
    lesson_id: str | None,
    media_type: str,
    purpose: str,
    ingest_format: str,
    original_object_path: str,
    original_content_type: str | None,
    original_filename: str | None,
    original_size_bytes: int | None,
    storage_bucket: str,
    state: str,
) -> dict[str, Any] | None:
    normalized_state = str(state or "").strip().lower()
    if normalized_state == "ready":
        raise MediaAssetReadyAuthorityError(
            "Only the processing worker may set media_asset.state = 'ready'"
        )

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
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
                    state,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, now())
                RETURNING id, owner_id, course_id, lesson_id, media_type, purpose, ingest_format,
                          original_object_path, original_content_type, original_filename,
                          original_size_bytes, storage_bucket, state, created_at, updated_at
                """,
                (
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
                    normalized_state,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def delete_media_asset(media_id: str) -> None:
    async with get_conn() as cur:
        await cur.execute(
            "DELETE FROM app.media_assets WHERE id = %s",
            (media_id,),
        )


async def get_media_asset(media_id: str) -> dict[str, Any] | None:
    query = f"""
            SELECT
              id,
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
              created_at,
              updated_at
            FROM app.media_assets
            WHERE id = %s
              AND {_test_visibility_clause("app.media_assets")}
            """
    async with get_conn() as cur:
        await cur.execute(query, (media_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_media_assets(media_ids: Iterable[str]) -> dict[str, dict[str, Any]]:
    normalized_ids = [str(media_id).strip() for media_id in media_ids if str(media_id).strip()]
    if not normalized_ids:
        return {}

    query = f"""
            SELECT
              id,
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
              created_at,
              updated_at
            FROM app.media_assets
            WHERE id = ANY(%s::uuid[])
              AND {_test_visibility_clause("app.media_assets")}
            """
    async with get_conn() as cur:
        await cur.execute(query, (normalized_ids,))
        rows = await cur.fetchall()
    return {
        str(row["id"]): dict(row)
        for row in rows
        if row and row.get("id")
    }


async def get_media_asset_access(media_id: str) -> dict[str, Any] | None:
    query = f"""
            SELECT
              ma.id,
              ma.course_id,
              ma.lesson_id,
              ma.media_type,
              ma.purpose,
              ma.storage_bucket,
              ma.original_object_path,
              ma.original_content_type,
              ma.original_filename,
              ma.original_size_bytes,
              ma.streaming_object_path,
              ma.streaming_storage_bucket,
              ma.streaming_format,
              ma.state,
              l.is_intro,
              c.id AS course_id,
              c.created_by,
              c.is_free_intro,
              c.is_published
            FROM app.media_assets ma
            LEFT JOIN app.lessons l ON l.id = ma.lesson_id
            LEFT JOIN app.courses c ON c.id = coalesce(ma.course_id, l.course_id)
            WHERE ma.id = %s
              AND {_test_visibility_clause("ma")}
            """
    async with get_conn() as cur:
        await cur.execute(query, (media_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def list_ready_course_cover_assets_for_object(
    *,
    course_id: str,
    storage_bucket: str,
    storage_path: str,
) -> list[dict[str, Any]]:
    query = f"""
            SELECT
              id,
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
              created_at,
              updated_at
            FROM app.media_assets ma
            WHERE ma.course_id = %s
              AND lower(coalesce(ma.media_type, '')) = 'image'
              AND lower(coalesce(ma.purpose, '')) = 'course_cover'
              AND lower(coalesce(ma.state, '')) = 'ready'
              AND coalesce(ma.streaming_storage_bucket, ma.storage_bucket) = %s
              AND coalesce(ma.streaming_object_path, ma.original_object_path) = %s
              AND {_test_visibility_clause("ma")}
            ORDER BY ma.created_at ASC, ma.id ASC
            """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (course_id, storage_bucket, storage_path),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def create_ready_public_course_cover_asset(
    *,
    owner_id: str | None,
    course_id: str,
    storage_bucket: str,
    storage_path: str,
    content_type: str | None,
    filename: str | None,
    size_bytes: int | None,
    ingest_format: str,
    codec: str | None = None,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
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
                    %s,
                    %s,
                    null,
                    'image',
                    'course_cover',
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
                    %s,
                    'ready',
                    null,
                    0,
                    null,
                    null,
                    now()
                )
                RETURNING
                  id,
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
                  created_at,
                  updated_at
                """,
                (
                    owner_id,
                    course_id,
                    ingest_format,
                    storage_path,
                    content_type,
                    filename,
                    size_bytes,
                    storage_bucket,
                    storage_path,
                    storage_bucket,
                    ingest_format,
                    codec,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def fetch_and_lock_pending_media_assets(
    *,
    limit: int = 5,
    max_attempts: int | None = None,
) -> Iterable[dict[str, Any]]:
    async with get_conn() as cur:
        await cur.execute(
            """
            WITH candidates AS (
              SELECT id
              FROM app.media_assets
              WHERE state IN ('uploaded', 'failed')
                AND (next_retry_at IS NULL OR next_retry_at <= now())
                AND (%s IS NULL OR COALESCE(processing_attempts, 0) < %s)
                AND EXISTS (
                  SELECT 1
                  FROM storage.objects o
                  WHERE o.bucket_id = app.media_assets.storage_bucket
                    AND o.name = app.media_assets.original_object_path
                )
              ORDER BY created_at ASC
              LIMIT %s
              FOR UPDATE SKIP LOCKED
            )
            UPDATE app.media_assets AS ma
            SET state = 'processing',
                processing_locked_at = now(),
                updated_at = now()
            FROM candidates
            WHERE ma.id = candidates.id
            RETURNING
              ma.id,
              ma.owner_id,
              ma.course_id,
              ma.lesson_id,
              ma.media_type,
              ma.purpose,
              ma.ingest_format,
              ma.original_object_path,
              ma.original_content_type,
              ma.original_filename,
              ma.original_size_bytes,
              ma.storage_bucket,
              ma.processing_attempts
            """,
            (max_attempts, max_attempts, limit),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_pending_media_assets_missing_source(
    *,
    limit: int = 5,
    max_attempts: int | None = None,
) -> list[dict[str, Any]]:
    try:
        async with get_conn() as cur:
            await cur.execute(
                """
                SELECT
                  id,
                  course_id,
                  lesson_id,
                  media_type,
                  purpose,
                  original_object_path,
                  storage_bucket,
                  state,
                  processing_attempts
                FROM app.media_assets
                WHERE state IN ('uploaded', 'failed')
                  AND (next_retry_at IS NULL OR next_retry_at <= now())
                  AND (%s IS NULL OR COALESCE(processing_attempts, 0) < %s)
                  AND NOT EXISTS (
                    SELECT 1
                    FROM storage.objects o
                    WHERE o.bucket_id = app.media_assets.storage_bucket
                      AND o.name = app.media_assets.original_object_path
                  )
                ORDER BY created_at ASC
                LIMIT %s
                """,
                (max_attempts, max_attempts, limit),
            )
            rows = await cur.fetchall()
    except errors.UndefinedTable:
        return []
    return [dict(row) for row in rows]


async def release_processing_media_assets(*, stale_after_seconds: int = 1800) -> int:
    async with get_conn() as cur:
        await cur.execute(
            """
            UPDATE app.media_assets
            SET state = 'uploaded',
                processing_locked_at = null,
                updated_at = now(),
                next_retry_at = least(coalesce(next_retry_at, now()), now())
            WHERE state = 'processing'
              AND processing_locked_at < now() - (%s || ' seconds')::interval
            RETURNING id
            """,
            (stale_after_seconds,),
        )
        rows = await cur.fetchall()
    return len(rows)


async def mark_media_asset_uploaded(*, media_id: str) -> bool:
    async with get_conn() as cur:
        await cur.execute(
            """
            UPDATE app.media_assets
            SET state = 'uploaded',
                error_message = null,
                next_retry_at = null,
                processing_locked_at = null,
                updated_at = now()
            WHERE id = %s
            """,
            (media_id,),
        )
        return cur.rowcount > 0


async def mark_media_asset_ready_passthrough(
    *,
    media_id: str,
    streaming_object_path: str,
    streaming_format: str,
    storage_bucket: str | None = None,
    original_content_type: str | None = None,
    original_size_bytes: int | None = None,
    codec: str | None = None,
) -> bool:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.media_assets
                SET state = 'ready',
                    streaming_object_path = %s,
                    streaming_storage_bucket = coalesce(%s, streaming_storage_bucket, storage_bucket),
                    streaming_format = %s,
                    original_content_type = coalesce(%s, original_content_type),
                    original_size_bytes = coalesce(%s, original_size_bytes),
                    codec = coalesce(%s, codec),
                    error_message = null,
                    next_retry_at = null,
                    processing_locked_at = null,
                    updated_at = now()
                WHERE id = %s
                """,
                (
                    streaming_object_path,
                    storage_bucket,
                    streaming_format,
                    original_content_type,
                    original_size_bytes,
                    codec,
                    media_id,
                ),
            )
            updated = cur.rowcount > 0
            await conn.commit()
            return updated


async def mark_media_asset_ready(
    *,
    media_id: str,
    streaming_object_path: str,
    streaming_format: str,
    duration_seconds: int | None,
    codec: str | None,
    streaming_storage_bucket: str | None = None,
) -> bool:
    raise MediaAssetReadyAuthorityError(
        "Only the processing worker may set media_asset.state = 'ready'"
    )


async def mark_media_asset_ready_from_worker(
    *,
    media_id: str,
    streaming_object_path: str,
    streaming_format: str,
    duration_seconds: int | None,
    codec: str | None,
    streaming_storage_bucket: str | None = None,
) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.media_assets
                SET state = 'ready',
                    streaming_object_path = %s,
                    streaming_storage_bucket = coalesce(%s, streaming_storage_bucket, storage_bucket),
                    streaming_format = %s,
                    duration_seconds = %s,
                    codec = %s,
                    error_message = null,
                    next_retry_at = null,
                    processing_locked_at = null,
                    updated_at = now()
                WHERE id = %s
                """,
                (
                    streaming_object_path,
                    streaming_storage_bucket,
                    streaming_format,
                    duration_seconds,
                    codec,
                    media_id,
                ),
            )
            updated = cur.rowcount > 0
            await conn.commit()
            return updated


async def mark_course_cover_ready(
    *,
    media_id: str,
    streaming_object_path: str,
    streaming_format: str,
    streaming_storage_bucket: str,
    public_url: str,
    codec: str | None,
) -> dict[str, Any]:
    raise MediaAssetReadyAuthorityError(
        "Only the processing worker may set media_asset.state = 'ready'"
    )


async def mark_course_cover_ready_from_worker(
    *,
    media_id: str,
    streaming_object_path: str,
    streaming_format: str,
    streaming_storage_bucket: str,
    public_url: str | None = None,
    codec: str | None,
) -> dict[str, Any]:
    if str(public_url or "").strip():
        logger.warning(
            "COURSE_COVER_LEGACY_URL_WRITE_IGNORED media_id=%s attempted_cover_url=%s",
            media_id,
            public_url,
        )
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH updated AS (
                  UPDATE app.media_assets
                  SET state = 'ready',
                      streaming_object_path = %s,
                      streaming_storage_bucket = %s,
                      streaming_format = %s,
                      duration_seconds = null,
                      codec = %s,
                      error_message = null,
                      next_retry_at = null,
                      processing_locked_at = null,
                      updated_at = now()
                  WHERE id = %s
                  RETURNING id, course_id, created_at
                ),
                previous AS (
                  SELECT
                    c.id AS course_id,
                    c.cover_media_id::text AS previous_cover_media_id
                  FROM app.courses c
                  WHERE c.id = (SELECT course_id FROM updated)
                ),
                latest AS (
                  SELECT id::text AS latest_cover_media_id
                  FROM app.media_assets
                  WHERE course_id = (SELECT course_id FROM updated)
                    AND purpose = 'course_cover'
                  ORDER BY created_at DESC
                  LIMIT 1
                ),
                applied AS (
                  UPDATE app.courses
                  SET cover_media_id = updated.id,
                      updated_at = now()
                  FROM updated, latest
                  WHERE app.courses.id = updated.course_id
                    AND updated.id::text = latest.latest_cover_media_id
                  RETURNING app.courses.id
                )
                SELECT
                  (SELECT course_id FROM updated)::text AS course_id,
                  (SELECT previous_cover_media_id FROM previous) AS previous_cover_media_id,
                  (SELECT latest_cover_media_id FROM latest) AS latest_cover_media_id,
                  EXISTS(SELECT 1 FROM updated) AS updated,
                  EXISTS(SELECT 1 FROM applied) AS cover_applied
                """,
                (
                    streaming_object_path,
                    streaming_storage_bucket,
                    streaming_format,
                    codec,
                    media_id,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            course_id = str(row["course_id"]) if row and row.get("course_id") else None
            updated = bool(row and row.get("updated"))
            applied = bool(row and row.get("cover_applied"))
            return {
                "course_id": course_id,
                "previous_cover_media_id": (
                    str(row["previous_cover_media_id"])
                    if row and row.get("previous_cover_media_id")
                    else None
                ),
                "latest_cover_media_id": (
                    str(row["latest_cover_media_id"])
                    if row and row.get("latest_cover_media_id")
                    else None
                ),
                "updated": updated,
                "cover_applied": applied,
            }


async def mark_media_asset_failed(
    *,
    media_id: str,
    error_message: str,
    next_retry_at: datetime | None = None,
) -> None:
    async with get_conn() as cur:
        await cur.execute(
            """
            UPDATE app.media_assets
            SET state = 'failed',
                error_message = %s,
                next_retry_at = %s,
                processing_locked_at = null,
                updated_at = now()
            WHERE id = %s
            """,
            (
                error_message,
                next_retry_at,
                media_id,
            ),
        )


async def defer_media_asset_processing(
    *,
    media_id: str,
    next_retry_at: datetime | None = None,
) -> None:
    async with get_conn() as cur:
        await cur.execute(
            """
            UPDATE app.media_assets
            SET state = 'uploaded',
                processing_locked_at = null,
                next_retry_at = %s,
                updated_at = now()
            WHERE id = %s
            """,
            (next_retry_at, media_id),
        )


async def increment_processing_attempts(*, media_id: str) -> None:
    async with get_conn() as cur:
        await cur.execute(
            """
            UPDATE app.media_assets
            SET processing_attempts = processing_attempts + 1,
                updated_at = now()
            WHERE id = %s
            """,
            (media_id,),
        )


def compute_backoff(attempt: int, *, base_seconds: float = 2.0, max_seconds: float = 300.0) -> timedelta:
    delay = min(base_seconds * (2 ** max(0, attempt - 1)), max_seconds)
    return timedelta(seconds=delay)
