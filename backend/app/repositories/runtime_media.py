from __future__ import annotations

from typing import Any

from ..db import get_conn


_RUNTIME_MEDIA_COLUMNS = """
    rm.lesson_media_id as id,
    rm.lesson_media_id,
    rm.lesson_id,
    rm.course_id,
    rm.media_asset_id,
    rm.media_type::text as media_type,
    rm.playback_object_path,
    rm.playback_format
"""


async def sync_home_player_upload_runtime_media(
    *,
    upload_id: str | None = None,
    teacher_id: str | None = None,
) -> int:
    del upload_id, teacher_id
    raise RuntimeError("app.runtime_media is a read-only projection in canonical runtime")


async def list_runtime_media_for_asset(
    media_asset_id: str,
    *,
    limit: int = 25,
) -> list[dict[str, Any]]:
    capped_limit = max(1, min(int(limit or 25), 100))
    async with get_conn() as cur:
        await cur.execute(
            f"""
            select
              {_RUNTIME_MEDIA_COLUMNS}
            from app.runtime_media as rm
            where rm.media_asset_id = %s::uuid
            order by rm.lesson_media_id asc
            limit %s
            """,
            (media_asset_id, capped_limit),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_runtime_media_for_lesson(
    lesson_id: str,
    *,
    limit: int = 100,
) -> list[dict[str, Any]]:
    capped_limit = max(1, min(int(limit or 100), 200))
    async with get_conn() as cur:
        await cur.execute(
            f"""
            select
              {_RUNTIME_MEDIA_COLUMNS}
            from app.runtime_media as rm
            where rm.lesson_id = %s::uuid
            order by rm.lesson_media_id asc
            limit %s
            """,
            (lesson_id, capped_limit),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]
