from __future__ import annotations

from datetime import timedelta
from typing import Any
from collections.abc import Sequence

from psycopg.rows import dict_row

from ..db import pool
from ..config import settings

_FAILURE_LIMIT_MAX = 100
_ORPHAN_LIMIT_MAX = 200
_QUEUE_SUPPORT_REQUIRED_COLUMNS = frozenset(
    {
        "created_at",
        "updated_at",
        "error_message",
        "processing_attempts",
        "processing_locked_at",
        "next_retry_at",
    }
)
_CONTROL_PLANE_PURPOSES = ("lesson_audio", "lesson_media", "home_player_audio")
_OBSERVABILITY_DEFAULTS: dict[str, Any] = {
    "course_id": None,
    "lesson_id": None,
    "original_content_type": None,
    "original_size_bytes": None,
    "original_filename": None,
    "codec": None,
    "duration_seconds": None,
    "error_message": None,
    "processing_attempts": 0,
    "processing_locked_at": None,
    "next_retry_at": None,
    "created_at": None,
    "updated_at": None,
    "streaming_storage_bucket": None,
    "streaming_object_path": None,
    "streaming_format": None,
    "home_player_upload_id": None,
    "home_player_upload_title": None,
    "home_player_upload_active": None,
}
_media_processing_queue_supported_cache: bool | None = None
_home_player_uploads_supported_cache: bool | None = None


def _decorate_media_asset_row(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if row is None:
        return None
    normalized = dict(row)
    normalized.setdefault("storage_bucket", settings.media_source_bucket)
    for key, value in _OBSERVABILITY_DEFAULTS.items():
        normalized.setdefault(key, value)
    return normalized


def _clamp_limit(limit: int | None, *, default: int, maximum: int) -> int:
    return max(1, min(int(limit or default), maximum))


async def _table_columns(schema: str, table: str) -> set[str]:
    query = """
        select column_name
        from information_schema.columns
        where table_schema = %s
          and table_name = %s
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (schema, table))
            rows = await cur.fetchall()
    return {str(row[0]) for row in rows}


async def _relation_exists(qualified_name: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("select to_regclass(%s) is not null", (qualified_name,))
            row = await cur.fetchone()
    return bool(row[0]) if row else False


async def get_media_asset(media_asset_id: str) -> dict[str, Any] | None:
    query = """
        select
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_format,
            state::text as state
        from app.media_assets
        where id = %s
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (media_asset_id,))
            row = await cur.fetchone()
    return _decorate_media_asset_row(dict(row) if row else None)


async def get_media_assets(media_asset_ids: Sequence[str]) -> dict[str, dict[str, Any]]:
    ids = [str(media_asset_id).strip() for media_asset_id in media_asset_ids if str(media_asset_id).strip()]
    if not ids:
        return {}

    query = """
        select
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_format,
            state::text as state
        from app.media_assets
        where id = any(%s::uuid[])
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (ids,))
            rows = await cur.fetchall()
    return {
        str(row["id"]): _decorate_media_asset_row(dict(row)) or {}
        for row in rows
    }


async def create_media_asset(
    *,
    media_asset_id: str,
    media_type: str,
    purpose: str,
    original_object_path: str,
    ingest_format: str,
    state: str,
    playback_format: str | None = None,
) -> dict[str, Any]:
    query = """
        insert into app.media_assets (
            id,
            media_type,
            purpose,
            original_object_path,
            ingest_format,
            playback_format,
            state
        )
        values (
            %s::uuid,
            %s::app.media_type,
            %s::app.media_purpose,
            %s,
            %s,
            %s,
            %s::app.media_state
        )
        returning
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_format,
            state::text as state
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    media_asset_id,
                    media_type,
                    purpose,
                    original_object_path,
                    ingest_format,
                    playback_format,
                    state,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        raise RuntimeError("created media_asset was not returned")
    return _decorate_media_asset_row(dict(row)) or {}


async def update_media_asset_state(
    media_asset_id: str,
    *,
    state: str,
    playback_format: str | None = None,
) -> dict[str, Any] | None:
    query = """
        update app.media_assets
        set
            state = %s::app.media_state,
            playback_format = %s
        where id = %s::uuid
        returning
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_format,
            state::text as state
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (state, playback_format, media_asset_id))
            row = await cur.fetchone()
            await conn.commit()
    return _decorate_media_asset_row(dict(row) if row else None)


async def delete_media_asset(media_asset_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "delete from app.media_assets where id = %s::uuid",
                (media_asset_id,),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
    return deleted


async def get_media_asset_access(media_asset_id: str) -> dict[str, Any] | None:
    row = await get_media_asset(media_asset_id)
    if not row:
        return None
    row.setdefault("storage_bucket", settings.media_source_bucket)
    return row


async def media_processing_queue_supported() -> bool:
    global _media_processing_queue_supported_cache
    if _media_processing_queue_supported_cache is None:
        columns = await _table_columns("app", "media_assets")
        _media_processing_queue_supported_cache = _QUEUE_SUPPORT_REQUIRED_COLUMNS.issubset(columns)
    return _media_processing_queue_supported_cache


async def home_player_uploads_supported() -> bool:
    global _home_player_uploads_supported_cache
    if _home_player_uploads_supported_cache is None:
        _home_player_uploads_supported_cache = await _relation_exists("app.home_player_uploads")
    return _home_player_uploads_supported_cache


async def list_media_failures(
    *,
    limit: int | None = None,
    media_id: str | None = None,
) -> list[dict[str, Any]]:
    bounded_limit = _clamp_limit(limit, default=25, maximum=_FAILURE_LIMIT_MAX)
    params: list[Any] = ["failed", bounded_limit]
    where = "where state::text = %s"
    if media_id:
        where += " and id = %s::uuid"
        params.insert(1, media_id)

    query = f"""
        select
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_format,
            state::text as state
        from app.media_assets
        {where}
        order by id asc
        limit %s
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, tuple(params))
            rows = await cur.fetchall()
    return [_decorate_media_asset_row(dict(row)) or {} for row in rows]


async def get_media_processing_worker_summary(
    *,
    stale_after_seconds: int,
) -> dict[str, Any]:
    del stale_after_seconds
    query = """
        select
            count(*) filter (where state::text = 'pending_upload') as pending_upload,
            count(*) filter (where state::text = 'uploaded') as uploaded,
            count(*) filter (where state::text = 'processing') as processing,
            count(*) filter (where state::text = 'failed') as failed,
            count(*) filter (where state::text = 'ready') as ready
        from app.media_assets
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query)
            row = await cur.fetchone()
    summary = dict(row) if row else {}
    summary.setdefault("stale_processing_locks", 0)
    summary.setdefault("oldest_unfinished_created_at", None)
    summary["queue_contract_supported"] = await media_processing_queue_supported()
    return summary


async def list_orphaned_control_plane_assets(
    *,
    limit: int | None = None,
) -> list[dict[str, Any]]:
    bounded_limit = _clamp_limit(limit, default=100, maximum=_ORPHAN_LIMIT_MAX)
    query = """
        with lesson_media_links as (
            select media_asset_id, count(*)::int as lesson_media_count
            from app.lesson_media
            where media_asset_id is not null
            group by media_asset_id
        ),
        runtime_media_links as (
            select media_asset_id, count(*)::int as runtime_media_count
            from app.runtime_media
            where media_asset_id is not null
            group by media_asset_id
        )
        select
            ma.id,
            ma.media_type::text as media_type,
            ma.purpose::text as purpose,
            ma.original_object_path,
            ma.ingest_format,
            ma.playback_format,
            ma.state::text as state,
            coalesce(lml.lesson_media_count, 0) as lesson_media_count,
            coalesce(rml.runtime_media_count, 0) as runtime_media_count,
            0::int as home_player_upload_count
        from app.media_assets as ma
        left join lesson_media_links as lml on lml.media_asset_id = ma.id
        left join runtime_media_links as rml on rml.media_asset_id = ma.id
        where ma.purpose::text = any(%s::text[])
          and coalesce(lml.lesson_media_count, 0) = 0
          and coalesce(rml.runtime_media_count, 0) = 0
        order by ma.id asc
        limit %s
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (list(_CONTROL_PLANE_PURPOSES), bounded_limit))
            rows = await cur.fetchall()
    return [_decorate_media_asset_row(dict(row)) or {} for row in rows]


def compute_backoff(attempt: int, *, max_seconds: int) -> timedelta:
    capped_attempt = max(1, int(attempt))
    seconds = min(max(1, int(max_seconds)), 2 ** (capped_attempt - 1))
    return timedelta(seconds=seconds)


async def release_processing_media_assets(*, stale_after_seconds: int) -> int:
    del stale_after_seconds
    if not await media_processing_queue_supported():
        return 0
    raise RuntimeError("media processing queue contract is unsupported in the current local baseline")


async def fetch_and_lock_pending_media_assets(
    *,
    limit: int,
    max_attempts: int,
) -> list[dict[str, Any]]:
    del limit, max_attempts
    if not await media_processing_queue_supported():
        return []
    raise RuntimeError("media processing queue contract is unsupported in the current local baseline")


async def list_pending_media_assets_missing_source(
    *,
    limit: int,
    max_attempts: int,
) -> list[dict[str, Any]]:
    del limit, max_attempts
    if not await media_processing_queue_supported():
        return []
    raise RuntimeError("media processing queue contract is unsupported in the current local baseline")


async def defer_media_asset_processing(
    *,
    media_id: str,
    next_retry_at: Any | None = None,
) -> None:
    del media_id, next_retry_at
    raise RuntimeError("media processing queue contract is unsupported in the current local baseline")


async def mark_media_asset_failed(
    *,
    media_id: str,
    error_message: str,
    next_retry_at: Any | None = None,
) -> None:
    del media_id, error_message, next_retry_at
    raise RuntimeError("media processing queue contract is unsupported in the current local baseline")


async def increment_processing_attempts(*, media_id: str) -> None:
    del media_id
    raise RuntimeError("media processing queue contract is unsupported in the current local baseline")
