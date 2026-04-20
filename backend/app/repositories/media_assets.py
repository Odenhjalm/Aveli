from __future__ import annotations

from datetime import timedelta
from typing import Any
from collections.abc import Sequence

from psycopg.rows import dict_row

from ..db import pool
from ..config import settings
from ..services import storage_service

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
    "storage_bucket": None,
    "course_id": None,
    "lesson_id": None,
    "original_content_type": None,
    "original_size_bytes": None,
    "original_filename": None,
    "playback_object_path": None,
    "codec": None,
    "duration_seconds": None,
    "error_message": None,
    "processing_attempts": 0,
    "processing_locked_at": None,
    "next_retry_at": None,
    "created_at": None,
    "updated_at": None,
    "home_player_upload_id": None,
    "home_player_upload_title": None,
    "home_player_upload_active": None,
}
_media_processing_queue_supported_cache: bool | None = None
_MEDIA_ASSET_RETURNING_SQL = """
    id,
    media_type::text as media_type,
    purpose::text as purpose,
    original_object_path,
    ingest_format,
    playback_object_path,
    playback_format,
    state::text as state
"""
_MEDIA_TRANSCODE_WORKER_SQL = """
    id,
    media_type::text as media_type,
    purpose::text as purpose,
    original_object_path,
    ingest_format,
    state::text as state,
    processing_attempts
"""


def _decorate_media_asset_row(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if row is None:
        return None
    normalized = dict(row)
    for key, value in _OBSERVABILITY_DEFAULTS.items():
        normalized.setdefault(key, value)
    return normalized


def _required_ready_text(value: Any, field_name: str) -> str:
    text = str(value or "").strip()
    if not text:
        raise RuntimeError(f"canonical worker ready transition requires {field_name}")
    return text


def _require_course_cover_ready_asset(
    *,
    media_id: str,
    asset: dict[str, Any],
    playback_object_path: str,
    playback_format: str,
) -> None:
    media_type = str(asset.get("media_type") or "").strip().lower()
    purpose = str(asset.get("purpose") or "").strip().lower()
    if media_type != "image":
        raise RuntimeError("course cover ready requires image media")
    if purpose != "course_cover":
        raise RuntimeError("course cover ready requires purpose course_cover")
    if not str(media_id or "").strip():
        raise RuntimeError("course cover ready requires media_id")
    _required_ready_text(playback_object_path, "playback_object_path")
    if _required_ready_text(playback_format, "playback_format") != "jpg":
        raise RuntimeError("course cover ready requires playback_format jpg")


def _require_worker_ready_asset(
    *,
    media_id: str,
    asset: dict[str, Any],
    playback_object_path: str,
    playback_format: str,
) -> None:
    media_type = str(asset.get("media_type") or "").strip().lower()
    purpose = str(asset.get("purpose") or "").strip().lower()
    resolved_format = _required_ready_text(
        playback_format,
        "playback_format",
    ).lower()
    _required_ready_text(playback_object_path, "playback_object_path")
    if not str(media_id or "").strip():
        raise RuntimeError("canonical worker ready transition requires media_id")

    if media_type == "audio":
        if resolved_format != "mp3":
            raise RuntimeError("audio ready requires playback_format mp3")
        return

    if media_type == "image" and purpose == "course_cover":
        _require_course_cover_ready_asset(
            media_id=media_id,
            asset=asset,
            playback_object_path=playback_object_path,
            playback_format=resolved_format,
        )
        return

    if media_type == "image" and purpose == "profile_media":
        if resolved_format != "jpg":
            raise RuntimeError("profile media image ready requires playback_format jpg")
        return

    if purpose != "lesson_media":
        raise RuntimeError("unsupported canonical worker ready media purpose")

    if media_type == "image":
        if resolved_format not in {"jpg", "png"}:
            raise RuntimeError("lesson image ready requires playback_format jpg or png")
        return

    if media_type == "video":
        if resolved_format != "mp4":
            raise RuntimeError("lesson video ready requires playback_format mp4")
        return

    if media_type == "document":
        if resolved_format != "pdf":
            raise RuntimeError("lesson document ready requires playback_format pdf")
        return

    raise RuntimeError("unsupported canonical worker ready media type")


def _canonical_storage_bucket_for_access(row: dict[str, Any]) -> str | None:
    playback_object_path = (
        str(row.get("playback_object_path") or "").strip().lstrip("/")
    )
    original_object_path = (
        str(row.get("original_object_path") or "").strip().lstrip("/")
    )
    purpose = str(row.get("purpose") or "").strip().lower()
    media_type = str(row.get("media_type") or "").strip().lower()

    if (
        playback_object_path
        and media_type == "image"
        and purpose in {"course_cover", "profile_media"}
    ):
        return settings.media_public_bucket
    if playback_object_path.startswith("lessons/") or original_object_path.startswith(
        "lessons/"
    ):
        return settings.media_public_bucket
    if playback_object_path or original_object_path:
        return storage_service.canonical_source_bucket_for_media_asset(row)
    return None


def _clamp_limit(limit: int | None, *, default: int, maximum: int) -> int:
    return max(1, min(int(limit or default), maximum))


def _transcode_worker_limit(limit: int) -> int:
    return _clamp_limit(limit, default=1, maximum=100)


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
            playback_object_path,
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


async def get_lesson_media_pipeline_asset(media_asset_id: str) -> dict[str, Any] | None:
    query = f"""
        select
            {_MEDIA_ASSET_RETURNING_SQL}
        from app.media_assets
        where id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (media_asset_id,))
            row = await cur.fetchone()
    return _decorate_media_asset_row(dict(row) if row else None)


async def get_course_cover_pipeline_asset(media_asset_id: str) -> dict[str, Any] | None:
    query = f"""
        select
            {_MEDIA_ASSET_RETURNING_SQL}
        from app.media_assets
        where id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (media_asset_id,))
            row = await cur.fetchone()
    return _decorate_media_asset_row(dict(row) if row else None)


async def get_media_assets(media_asset_ids: Sequence[str]) -> dict[str, dict[str, Any]]:
    ids = [
        str(media_asset_id).strip()
        for media_asset_id in media_asset_ids
        if str(media_asset_id).strip()
    ]
    if not ids:
        return {}

    query = """
        select
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_object_path,
            playback_format,
            state::text as state
        from app.media_assets
        where id = any(%s::uuid[])
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (ids,))
            rows = await cur.fetchall()
    return {str(row["id"]): _decorate_media_asset_row(dict(row)) or {} for row in rows}


async def create_media_asset(
    *,
    media_asset_id: str,
    media_type: str,
    purpose: str,
    original_object_path: str,
    ingest_format: str,
    state: str,
    playback_object_path: str | None = None,
    playback_format: str | None = None,
) -> dict[str, Any]:
    normalized_state = str(state or "").strip().lower()
    if normalized_state != "pending_upload":
        raise RuntimeError(
            "create_media_asset only supports the canonical pending_upload initial state"
        )
    if playback_object_path is not None or playback_format is not None:
        raise RuntimeError(
            "playback metadata is assigned only through canonical worker helpers"
        )
    query = """
        insert into app.media_assets (
            id,
            media_type,
            purpose,
            original_object_path,
            ingest_format,
            playback_object_path,
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
            %s,
            %s::app.media_state
        )
        returning
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_object_path,
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
                    None,
                    None,
                    normalized_state,
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
    playback_object_path: str | None = None,
    playback_format: str | None = None,
) -> dict[str, Any] | None:
    normalized_state = str(state or "").strip().lower()
    if normalized_state != "uploaded":
        raise RuntimeError(
            "update_media_asset_state only supports the canonical uploaded transition"
        )
    if playback_object_path is not None or playback_format is not None:
        raise RuntimeError(
            "playback metadata is assigned only through canonical worker helpers"
        )
    return await mark_media_asset_uploaded(media_id=media_asset_id)


async def _call_canonical_worker_transition(
    media_asset_id: str,
    *,
    target_state: str,
    playback_object_path: str | None = None,
    playback_format: str | None = None,
    error_message: str | None = None,
    next_retry_at: Any | None = None,
) -> dict[str, Any] | None:
    query = """
        select
            result.id as id,
            result.media_type::text as media_type,
            result.purpose::text as purpose,
            result.original_object_path as original_object_path,
            result.ingest_format as ingest_format,
            result.playback_object_path as playback_object_path,
            result.playback_format as playback_format,
            result.state::text as state
        from app.canonical_worker_transition_media_asset(
            %s::uuid,
            %s::app.media_state,
            %s,
            %s,
            %s,
            %s
        ) as result
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    media_asset_id,
                    target_state,
                    playback_object_path,
                    playback_format,
                    error_message,
                    next_retry_at,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    return _decorate_media_asset_row(dict(row) if row else None)


async def mark_media_asset_uploaded(*, media_id: str) -> dict[str, Any] | None:
    media_asset = await get_media_asset(media_id)
    if media_asset is None:
        return None
    current_state = str(media_asset.get("state") or "").strip().lower()
    if current_state == "uploaded":
        return media_asset
    if current_state != "pending_upload":
        return None

    return await _call_canonical_worker_transition(
        media_id,
        target_state="uploaded",
    )


async def mark_lesson_media_pipeline_asset_uploaded(
    *,
    media_id: str,
) -> dict[str, Any] | None:
    media_asset = await get_lesson_media_pipeline_asset(media_id)
    if media_asset is None:
        return None
    current_state = str(media_asset.get("state") or "").strip().lower()
    if current_state == "uploaded":
        return media_asset
    if current_state != "pending_upload":
        return None

    return await _call_canonical_worker_transition(
        media_id,
        target_state="uploaded",
    )


async def mark_media_asset_ready_passthrough(
    *,
    media_id: str,
    playback_object_path: str,
    storage_bucket: str,
    playback_format: str,
    original_content_type: str | None = None,
    original_size_bytes: int | None = None,
) -> dict[str, Any] | None:
    del (
        media_id,
        playback_object_path,
        storage_bucket,
        playback_format,
        original_content_type,
        original_size_bytes,
    )
    raise RuntimeError(
        "mark_media_asset_ready_passthrough is removed from canonical runtime"
    )


async def mark_media_asset_ready_from_worker(
    *,
    media_id: str,
    playback_object_path: str,
    playback_format: str | None = None,
    duration_seconds: int | None = None,
    codec: str | None = None,
    playback_storage_bucket: str | None = None,
) -> dict[str, Any] | None:
    del duration_seconds, codec, playback_storage_bucket
    resolved_playback_object_path = _required_ready_text(
        playback_object_path,
        "playback_object_path",
    )
    resolved_playback_format = _required_ready_text(
        playback_format,
        "playback_format",
    )
    media_asset = await get_media_asset(media_id)
    if media_asset is None:
        return None

    current_state = str(media_asset.get("state") or "").strip().lower()
    if current_state != "processing":
        raise RuntimeError(
            "canonical worker ready transition requires processing state"
        )
    _require_worker_ready_asset(
        media_id=media_id,
        asset=media_asset,
        playback_object_path=resolved_playback_object_path,
        playback_format=resolved_playback_format,
    )
    return await _call_canonical_worker_transition(
        media_id,
        target_state="ready",
        playback_object_path=resolved_playback_object_path,
        playback_format=resolved_playback_format,
    )


async def mark_course_cover_ready_from_worker(
    *,
    media_id: str,
    playback_object_path: str,
    playback_storage_bucket: str | None = None,
    playback_format: str | None = None,
    codec: str | None = None,
) -> dict[str, Any]:
    del playback_storage_bucket, codec
    resolved_playback_object_path = _required_ready_text(
        playback_object_path,
        "playback_object_path",
    )
    resolved_playback_format = _required_ready_text(
        playback_format,
        "playback_format",
    )
    if resolved_playback_format != "jpg":
        raise RuntimeError("course cover ready requires playback_format jpg")
    asset = await get_course_cover_pipeline_asset(media_id)
    if asset is None:
        return {"updated": False}
    _require_course_cover_ready_asset(
        media_id=media_id,
        asset=asset,
        playback_object_path=resolved_playback_object_path,
        playback_format=resolved_playback_format,
    )
    updated = await mark_media_asset_ready_from_worker(
        media_id=media_id,
        playback_object_path=resolved_playback_object_path,
        playback_format=resolved_playback_format,
    )
    return {"updated": updated is not None}


async def get_media_asset_access(media_asset_id: str) -> dict[str, Any] | None:
    row = await get_media_asset(media_asset_id)
    if not row:
        return None
    row["storage_bucket"] = _canonical_storage_bucket_for_access(row)
    return row


async def media_processing_queue_supported() -> bool:
    global _media_processing_queue_supported_cache
    if _media_processing_queue_supported_cache is None:
        columns = await _table_columns("app", "media_assets")
        _media_processing_queue_supported_cache = (
            _QUEUE_SUPPORT_REQUIRED_COLUMNS.issubset(columns)
        )
    return _media_processing_queue_supported_cache


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
            playback_object_path,
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
        ),
        home_player_upload_links as (
            select media_asset_id, count(*)::int as home_player_upload_count
            from app.home_player_uploads
            where media_asset_id is not null
            group by media_asset_id
        )
        select
            ma.id,
            ma.media_type::text as media_type,
            ma.purpose::text as purpose,
            ma.original_object_path,
            ma.ingest_format,
            ma.playback_object_path,
            ma.playback_format,
            ma.state::text as state,
            coalesce(lml.lesson_media_count, 0) as lesson_media_count,
            coalesce(rml.runtime_media_count, 0) as runtime_media_count,
            coalesce(hpul.home_player_upload_count, 0) as home_player_upload_count
        from app.media_assets as ma
        left join lesson_media_links as lml on lml.media_asset_id = ma.id
        left join runtime_media_links as rml on rml.media_asset_id = ma.id
        left join home_player_upload_links as hpul on hpul.media_asset_id = ma.id
        where ma.purpose::text = any(%s::text[])
          and (
            (
              ma.purpose::text in ('lesson_audio', 'lesson_media')
              and coalesce(lml.lesson_media_count, 0) = 0
              and coalesce(rml.runtime_media_count, 0) = 0
            )
            or (
              ma.purpose::text = 'home_player_audio'
              and coalesce(hpul.home_player_upload_count, 0) = 0
            )
          )
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
    if not await media_processing_queue_supported():
        return 0
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select app.canonical_worker_release_stale_media_asset_locks(
                    %s::integer
                ) as released
                """,
                (max(1, int(stale_after_seconds)),),
            )
            row = await cur.fetchone()
            await conn.commit()
    return int(row[0] if row else 0)


async def fetch_and_lock_pending_media_assets(
    *,
    limit: int,
    max_attempts: int,
) -> list[dict[str, Any]]:
    if not await media_processing_queue_supported():
        return []
    bounded_limit = _transcode_worker_limit(limit)
    bounded_attempts = max(1, int(max_attempts))
    locked_rows: list[dict[str, Any]] = []

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select
                    id,
                    state::text as state
                from app.media_assets
                where (
                    media_type = 'audio'::app.media_type
                    or (
                        media_type = 'image'::app.media_type
                        and purpose in (
                            'course_cover'::app.media_purpose,
                            'profile_media'::app.media_purpose,
                            'lesson_media'::app.media_purpose
                        )
                    )
                    or (
                        media_type in (
                            'video'::app.media_type,
                            'document'::app.media_type
                        )
                        and purpose = 'lesson_media'::app.media_purpose
                    )
                )
                  and state in (
                    'uploaded'::app.media_state,
                    'processing'::app.media_state
                  )
                  and coalesce(processing_attempts, 0) < %s::integer
                  and processing_locked_at is null
                  and coalesce(next_retry_at, now()) <= now()
                order by coalesce(next_retry_at, created_at, updated_at, now()) asc, id asc
                limit %s::integer
                for update skip locked
                """,
                (bounded_attempts, bounded_limit),
            )
            candidates = [dict(row) for row in await cur.fetchall()]

            for candidate in candidates:
                media_id = str(candidate.get("id") or "").strip()
                if not media_id:
                    continue
                await cur.execute(
                    """
                    select
                        result.id as id,
                        result.media_type::text as media_type,
                        result.purpose::text as purpose,
                        result.original_object_path as original_object_path,
                        result.ingest_format as ingest_format,
                        result.file_size as file_size,
                        result.content_hash as content_hash,
                        result.content_hash_algorithm as content_hash_algorithm,
                        result.state::text as state,
                        result.processing_attempts as processing_attempts
                    from app.canonical_worker_lock_media_asset_for_processing(
                        %s::uuid
                    ) as result
                    """,
                    (media_id,),
                )
                row = await cur.fetchone()
                if row is not None:
                    locked_rows.append(_decorate_media_asset_row(dict(row)) or {})
            await conn.commit()

    return locked_rows


async def list_pending_media_assets_missing_source(
    *,
    limit: int,
    max_attempts: int,
) -> list[dict[str, Any]]:
    del limit, max_attempts
    if not await media_processing_queue_supported():
        return []
    return []


async def defer_media_asset_processing(
    *,
    media_id: str,
    next_retry_at: Any | None = None,
) -> None:
    if not await media_processing_queue_supported():
        return
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select app.canonical_worker_defer_media_asset_processing(
                    %s::uuid,
                    coalesce(%s::timestamptz, clock_timestamp())
                )
                """,
                (media_id, next_retry_at),
            )
            await conn.commit()


async def mark_media_asset_failed(
    *,
    media_id: str,
    error_message: str,
    next_retry_at: Any | None = None,
) -> None:
    media_asset = await get_media_asset(media_id)
    if media_asset is None:
        return

    current_state = str(media_asset.get("state") or "").strip().lower()
    if current_state == "uploaded":
        media_asset = await _call_canonical_worker_transition(
            media_id,
            target_state="processing",
        )
        current_state = str((media_asset or {}).get("state") or "").strip().lower()
    if current_state == "processing":
        await _call_canonical_worker_transition(
            media_id,
            target_state="failed",
            error_message=error_message,
            next_retry_at=next_retry_at,
        )
    elif current_state != "failed":
        raise RuntimeError(
            "canonical worker failed transition requires uploaded or processing state"
        )


async def increment_processing_attempts(*, media_id: str) -> None:
    if not await media_processing_queue_supported():
        return
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select app.canonical_worker_increment_media_asset_attempts(
                    %s::uuid
                )
                """,
                (media_id,),
            )
            await conn.commit()
