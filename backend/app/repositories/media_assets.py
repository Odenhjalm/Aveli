from __future__ import annotations

from typing import Any

from psycopg.rows import dict_row

from ..db import pool
from ..config import settings


async def get_media_asset(media_id: str) -> dict[str, Any] | None:
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
            await cur.execute(query, (media_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_media_asset_access(media_id: str) -> dict[str, Any] | None:
    row = await get_media_asset(media_id)
    if not row:
        return None
    row.setdefault("storage_bucket", settings.media_source_bucket)
    return row
