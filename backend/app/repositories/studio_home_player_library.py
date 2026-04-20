from __future__ import annotations

from typing import Any

from ..db import get_conn


async def list_home_player_uploads(*, teacher_id: str) -> list[dict[str, Any]]:
    query = """
        SELECT
          hpu.id,
          hpu.media_asset_id,
          hpu.title,
          hpu.active,
          hpu.created_at,
          hpu.updated_at,
          'audio' AS kind,
          ma.state::text AS media_state
        FROM app.home_player_uploads hpu
        JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        WHERE hpu.teacher_id = %s::uuid
          AND ma.purpose = 'home_player_audio'::app.media_purpose
          AND ma.media_type = 'audio'::app.media_type
        ORDER BY hpu.created_at DESC, hpu.id DESC
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_home_player_course_links(
    *, teacher_id: str
) -> list[dict[str, Any]]:
    query = """
        SELECT
          hpcl.id,
          hpcl.lesson_media_id,
          hpcl.title,
          c.title AS course_title,
          hpcl.enabled,
          hpcl.created_at,
          hpcl.updated_at,
          'audio' AS kind,
          CASE
            WHEN c.visibility = 'public'::app.course_visibility THEN 'active'
            ELSE 'course_unpublished'
          END AS status
        FROM app.home_player_course_links hpcl
        JOIN app.lesson_media lm ON lm.id = hpcl.lesson_media_id
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.courses c ON c.id = l.course_id
        JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        WHERE c.teacher_id = %s::uuid
          AND ma.purpose = 'lesson_media'::app.media_purpose
          AND ma.media_type = 'audio'::app.media_type
        ORDER BY hpcl.created_at DESC, hpcl.id DESC
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_home_player_course_media(
    *, teacher_id: str
) -> list[dict[str, Any]]:
    query = """
        SELECT
          lm.id AS id,
          lm.lesson_id,
          l.lesson_title,
          c.id AS course_id,
          c.title AS course_title,
          c.slug AS course_slug,
          'audio' AS kind,
          NULL::text AS content_type,
          NULL::integer AS duration_seconds,
          lm.position,
          NULL::timestamptz AS created_at,
          NULL::jsonb AS media
        FROM app.lesson_media lm
        JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.courses c ON c.id = l.course_id
        WHERE c.teacher_id = %s::uuid
          AND ma.purpose = 'lesson_media'::app.media_purpose
          AND ma.media_type = 'audio'::app.media_type
        ORDER BY lower(c.title), l.position ASC, lm.position ASC, lm.id ASC
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_home_player_library(*, teacher_id: str) -> dict[str, list[dict[str, Any]]]:
    return {
        "uploads": await list_home_player_uploads(teacher_id=teacher_id),
        "course_links": await list_home_player_course_links(teacher_id=teacher_id),
        "course_media": await list_home_player_course_media(teacher_id=teacher_id),
    }
