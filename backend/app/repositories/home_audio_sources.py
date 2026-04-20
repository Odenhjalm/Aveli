from __future__ import annotations

from typing import Any, Optional

from ..db import get_conn


def _test_visibility_clause(alias: str) -> str:
    return f"app.is_test_row_visible({alias}.is_test, {alias}.test_session_id)"


async def get_home_audio_media_asset(media_asset_id: str) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          ma.id,
          ma.owner_id,
          ma.course_id,
          ma.lesson_id,
          ma.media_type::text AS media_type,
          ma.purpose::text AS purpose,
          ma.state::text AS state,
          ma.original_content_type,
          ma.original_filename,
          ma.original_size_bytes
        FROM app.media_assets ma
        WHERE ma.id = %s::uuid
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (media_asset_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_home_player_upload(
    *,
    upload_id: str,
    teacher_id: str,
) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          hpu.id,
          hpu.teacher_id,
          hpu.media_asset_id,
          hpu.title,
          hpu.kind,
          hpu.active,
          hpu.created_at,
          hpu.updated_at,
          ma.original_content_type AS content_type,
          ma.original_size_bytes AS byte_size,
          ma.original_filename AS original_name,
          ma.state::text AS media_state
        FROM app.home_player_uploads hpu
        JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        WHERE hpu.id = %s::uuid
          AND hpu.teacher_id = %s::uuid
          AND ma.purpose = 'home_player_audio'::app.media_purpose
          AND ma.media_type = 'audio'::app.media_type
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (upload_id, teacher_id))
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_home_player_upload_by_media_asset_id(
    *,
    media_asset_id: str,
    teacher_id: str,
) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          hpu.id,
          hpu.teacher_id,
          hpu.media_asset_id,
          hpu.title,
          hpu.kind,
          hpu.active,
          hpu.created_at,
          hpu.updated_at,
          ma.original_content_type AS content_type,
          ma.original_size_bytes AS byte_size,
          ma.original_filename AS original_name,
          ma.state::text AS media_state
        FROM app.home_player_uploads hpu
        JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        WHERE hpu.media_asset_id = %s::uuid
          AND hpu.teacher_id = %s::uuid
          AND ma.purpose = 'home_player_audio'::app.media_purpose
          AND ma.media_type = 'audio'::app.media_type
        ORDER BY hpu.active DESC, hpu.updated_at DESC, hpu.created_at DESC
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (media_asset_id, teacher_id))
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_active_home_upload_by_media_asset_id(
    media_asset_id: str,
) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          hpu.id,
          hpu.teacher_id,
          hpu.media_asset_id,
          hpu.title,
          hpu.active,
          hpu.created_at,
          hpu.updated_at
        FROM app.home_player_uploads hpu
        JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        WHERE hpu.media_asset_id = %s::uuid
          AND hpu.active = true
          AND ma.purpose = 'home_player_audio'::app.media_purpose
          AND ma.media_type = 'audio'::app.media_type
        ORDER BY hpu.updated_at DESC, hpu.created_at DESC, hpu.id DESC
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (media_asset_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def create_home_player_upload(
    *,
    teacher_id: str,
    media_asset_id: str,
    title: str,
    active: bool,
) -> Optional[dict[str, Any]]:
    query = """
        INSERT INTO app.home_player_uploads (
          teacher_id,
          media_id,
          media_asset_id,
          title,
          kind,
          active
        )
        VALUES (%s::uuid, NULL, %s::uuid, %s, 'audio', %s)
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (teacher_id, media_asset_id, title, active),
        )
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_upload(
        upload_id=str(row["id"]),
        teacher_id=teacher_id,
    )


async def update_home_player_upload(
    *,
    upload_id: str,
    teacher_id: str,
    fields: dict[str, Any],
) -> Optional[dict[str, Any]]:
    if not fields:
        return await get_home_player_upload(upload_id=upload_id, teacher_id=teacher_id)

    params: dict[str, Any] = {"upload_id": upload_id, "teacher_id": teacher_id}
    assignments: list[str] = []
    for key, value in fields.items():
        params[key] = value
        assignments.append(f"{key} = %({key})s")

    query = f"""
        UPDATE app.home_player_uploads
           SET {", ".join(assignments)},
               updated_at = now()
         WHERE id = %(upload_id)s::uuid
           AND teacher_id = %(teacher_id)s::uuid
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_upload(upload_id=upload_id, teacher_id=teacher_id)


async def delete_home_player_upload(
    *,
    upload_id: str,
    teacher_id: str,
) -> Optional[dict[str, Any]]:
    existing = await get_home_player_upload(upload_id=upload_id, teacher_id=teacher_id)
    if not existing:
        return None
    query = """
        DELETE FROM app.home_player_uploads
        WHERE id = %s::uuid
          AND teacher_id = %s::uuid
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(query, (upload_id, teacher_id))
        row = await cur.fetchone()
    return existing if row else None


async def get_home_player_course_link(
    *,
    link_id: str,
    teacher_id: str,
) -> Optional[dict[str, Any]]:
    query = f"""
        SELECT
          hpcl.id,
          c.teacher_id AS teacher_id,
          hpcl.lesson_media_id,
          hpcl.title,
          coalesce(c.title, ''::text) AS course_title,
          hpcl.enabled,
          CASE
            WHEN hpcl.lesson_media_id IS NULL OR lm.id IS NULL OR ma.id IS NULL THEN 'source_missing'
            WHEN c.visibility <> 'public'::app.course_visibility THEN 'course_unpublished'
            ELSE 'active'
          END AS status,
          ma.media_type::text AS kind,
          hpcl.created_at,
          hpcl.updated_at
        FROM app.home_player_course_links hpcl
        LEFT JOIN app.lesson_media lm ON lm.id = hpcl.lesson_media_id
        LEFT JOIN app.lessons l ON l.id = lm.lesson_id
        LEFT JOIN app.courses c ON c.id = l.course_id
        LEFT JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        WHERE hpcl.id = %s::uuid
          AND EXISTS (
            SELECT 1
            FROM app.lesson_media lm_owner
            JOIN app.lessons l_owner ON l_owner.id = lm_owner.lesson_id
            JOIN app.courses c_owner ON c_owner.id = l_owner.course_id
            WHERE lm_owner.id = hpcl.lesson_media_id
              AND c_owner.teacher_id = %s::uuid
              AND {_test_visibility_clause("lm_owner")}
              AND {_test_visibility_clause("l_owner")}
              AND {_test_visibility_clause("c_owner")}
          )
          AND {_test_visibility_clause("lm")}
          AND {_test_visibility_clause("l")}
          AND {_test_visibility_clause("c")}
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (link_id, teacher_id))
        row = await cur.fetchone()
    return dict(row) if row else None


async def resolve_lesson_media_course_owner(lesson_media_id: str) -> Optional[dict[str, Any]]:
    query = f"""
        SELECT
          c.teacher_id AS teacher_id,
          c.title AS course_title,
          (c.visibility = 'public'::app.course_visibility) AS course_is_published,
          ma.media_type::text AS media_type
        FROM app.lesson_media lm
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.courses c ON c.id = l.course_id
        JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        WHERE lm.id = %s::uuid
          AND {_test_visibility_clause("lm")}
          AND {_test_visibility_clause("l")}
          AND {_test_visibility_clause("c")}
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (lesson_media_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def upsert_home_player_course_link(
    *,
    teacher_id: str,
    lesson_media_id: str,
    title: str,
    course_title_snapshot: str,
    enabled: bool,
) -> Optional[dict[str, Any]]:
    del course_title_snapshot
    query = f"""
        INSERT INTO app.home_player_course_links (
          lesson_media_id,
          title,
          enabled
        )
        SELECT
          lm.id,
          %s,
          %s
        FROM app.lesson_media lm
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.courses c ON c.id = l.course_id
        WHERE lm.id = %s::uuid
          AND c.teacher_id = %s::uuid
          AND {_test_visibility_clause("lm")}
          AND {_test_visibility_clause("l")}
          AND {_test_visibility_clause("c")}
        ON CONFLICT (lesson_media_id) DO UPDATE
          SET title = EXCLUDED.title,
              enabled = EXCLUDED.enabled,
              updated_at = now()
        WHERE EXISTS (
          SELECT 1
          FROM app.lesson_media lm_owner
          JOIN app.lessons l_owner ON l_owner.id = lm_owner.lesson_id
          JOIN app.courses c_owner ON c_owner.id = l_owner.course_id
          WHERE lm_owner.id = app.home_player_course_links.lesson_media_id
            AND c_owner.teacher_id = %s::uuid
            AND {_test_visibility_clause("lm_owner")}
            AND {_test_visibility_clause("l_owner")}
            AND {_test_visibility_clause("c_owner")}
        )
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (title, enabled, lesson_media_id, teacher_id, teacher_id),
        )
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_course_link(
        link_id=str(row["id"]),
        teacher_id=teacher_id,
    )


async def update_home_player_course_link(
    *,
    link_id: str,
    teacher_id: str,
    fields: dict[str, Any],
) -> Optional[dict[str, Any]]:
    if not fields:
        return await get_home_player_course_link(link_id=link_id, teacher_id=teacher_id)

    params: dict[str, Any] = {"link_id": link_id, "teacher_id": teacher_id}
    assignments: list[str] = []
    for key, value in fields.items():
        params[key] = value
        assignments.append(f"{key} = %({key})s")

    query = f"""
        UPDATE app.home_player_course_links AS hpcl
           SET {", ".join(assignments)},
               updated_at = now()
         WHERE hpcl.id = %(link_id)s::uuid
           AND EXISTS (
             SELECT 1
             FROM app.lesson_media lm
             JOIN app.lessons l ON l.id = lm.lesson_id
             JOIN app.courses c ON c.id = l.course_id
             WHERE lm.id = hpcl.lesson_media_id
               AND c.teacher_id = %(teacher_id)s::uuid
               AND {_test_visibility_clause("lm")}
               AND {_test_visibility_clause("l")}
               AND {_test_visibility_clause("c")}
           )
        RETURNING hpcl.id
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_course_link(link_id=link_id, teacher_id=teacher_id)


async def delete_home_player_course_link(
    *,
    link_id: str,
    teacher_id: str,
) -> bool:
    query = f"""
        DELETE FROM app.home_player_course_links AS hpcl
        WHERE hpcl.id = %s::uuid
          AND EXISTS (
            SELECT 1
            FROM app.lesson_media lm
            JOIN app.lessons l ON l.id = lm.lesson_id
            JOIN app.courses c ON c.id = l.course_id
            WHERE lm.id = hpcl.lesson_media_id
              AND c.teacher_id = %s::uuid
              AND {_test_visibility_clause("lm")}
              AND {_test_visibility_clause("l")}
              AND {_test_visibility_clause("c")}
          )
        RETURNING hpcl.id
    """
    async with get_conn() as cur:
        await cur.execute(query, (link_id, teacher_id))
        row = await cur.fetchone()
    return bool(row)
