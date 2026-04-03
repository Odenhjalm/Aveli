from __future__ import annotations

from typing import Any

from ..db import get_conn


def _test_visibility_clause(alias: str) -> str:
    return f"app.is_test_row_visible({alias}.is_test, {alias}.test_session_id)"


def _clamp_limit(limit: int | None) -> int:
    return max(1, min(int(limit or 100), 250))


async def list_home_audio_direct_upload_sources(*, limit: int = 100) -> list[dict[str, Any]]:
    query = """
        SELECT
          hpu.teacher_id,
          hpu.title,
          hpu.created_at,
          prof.display_name AS teacher_name,
          ma.id AS media_asset_id,
          ma.state::text AS media_state
        FROM app.home_player_uploads hpu
        JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        LEFT JOIN app.profiles prof ON prof.user_id = hpu.teacher_id
        WHERE hpu.active = true
          AND ma.purpose = 'home_player_audio'::app.media_purpose
          AND ma.media_type = 'audio'::app.media_type
        ORDER BY hpu.created_at DESC, hpu.id DESC
        LIMIT %s
    """
    async with get_conn() as cur:
        await cur.execute(query, (_clamp_limit(limit),))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_home_audio_course_link_sources(*, limit: int = 100) -> list[dict[str, Any]]:
    query = f"""
        SELECT
          hpcl.teacher_id,
          hpcl.title,
          hpcl.created_at,
          prof.display_name AS teacher_name,
          l.id AS lesson_id,
          l.course_id,
          l.lesson_title,
          c.title AS course_title,
          c.slug AS course_slug,
          ma.id AS media_asset_id,
          ma.state::text AS media_state
        FROM app.home_player_course_links hpcl
        JOIN app.lesson_media lm ON lm.id = hpcl.lesson_media_id
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.courses c ON c.id = l.course_id
        JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        LEFT JOIN app.profiles prof ON prof.user_id = hpcl.teacher_id
        WHERE hpcl.enabled = true
          AND COALESCE(c.is_published, false) = true
          AND ma.media_type = 'audio'::app.media_type
          AND {_test_visibility_clause("lm")}
          AND {_test_visibility_clause("l")}
          AND {_test_visibility_clause("c")}
        ORDER BY hpcl.created_at DESC, hpcl.id DESC
        LIMIT %s
    """
    async with get_conn() as cur:
        await cur.execute(query, (_clamp_limit(limit),))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]
