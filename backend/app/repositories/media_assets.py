from __future__ import annotations

from typing import Any

from psycopg.rows import dict_row

from ..db import pool
from ..config import settings


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
    return dict(row) if row else None


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
    return dict(row)


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
    return dict(row) if row else None


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
