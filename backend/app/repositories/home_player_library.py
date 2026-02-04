from __future__ import annotations

from typing import Any, Optional

from ..db import get_conn


async def list_home_player_uploads(teacher_id: str) -> list[dict[str, Any]]:
    query = """
        SELECT
          hpu.id,
          hpu.teacher_id,
          hpu.media_id,
          hpu.media_asset_id,
          hpu.title,
          hpu.kind,
          hpu.active,
          hpu.created_at,
          hpu.updated_at,
          coalesce(mo.content_type, ma.original_content_type) AS content_type,
          coalesce(mo.byte_size, ma.original_size_bytes) AS byte_size,
          coalesce(mo.original_name, ma.original_filename) AS original_name
        FROM app.home_player_uploads hpu
        LEFT JOIN app.media_objects mo ON mo.id = hpu.media_id
        LEFT JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        WHERE hpu.teacher_id = %s
        ORDER BY hpu.created_at DESC
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_home_player_upload(*, upload_id: str, teacher_id: str) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          hpu.id,
          hpu.teacher_id,
          hpu.media_id,
          hpu.media_asset_id,
          hpu.title,
          hpu.kind,
          hpu.active,
          hpu.created_at,
          hpu.updated_at,
          coalesce(mo.content_type, ma.original_content_type) AS content_type,
          coalesce(mo.byte_size, ma.original_size_bytes) AS byte_size,
          coalesce(mo.original_name, ma.original_filename) AS original_name
        FROM app.home_player_uploads hpu
        LEFT JOIN app.media_objects mo ON mo.id = hpu.media_id
        LEFT JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        WHERE hpu.id = %s AND hpu.teacher_id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (upload_id, teacher_id))
        row = await cur.fetchone()
    return dict(row) if row else None


async def create_home_player_upload(
    *,
    teacher_id: str,
    media_id: str | None,
    media_asset_id: str | None,
    title: str,
    kind: str,
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
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (teacher_id, media_id, media_asset_id, title, kind, active),
        )
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_upload(upload_id=str(row["id"]), teacher_id=teacher_id)


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
         WHERE id = %(upload_id)s AND teacher_id = %(teacher_id)s
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_upload(upload_id=upload_id, teacher_id=teacher_id)


async def delete_home_player_upload(*, upload_id: str, teacher_id: str) -> Optional[dict[str, Any]]:
    existing = await get_home_player_upload(upload_id=upload_id, teacher_id=teacher_id)
    if not existing:
        return None
    query = """
        DELETE FROM app.home_player_uploads
        WHERE id = %s AND teacher_id = %s
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(query, (upload_id, teacher_id))
        row = await cur.fetchone()
    return existing if row else None


async def list_home_player_course_links(teacher_id: str) -> list[dict[str, Any]]:
    query = """
        SELECT
          hpcl.id,
          hpcl.teacher_id,
          hpcl.lesson_media_id,
          hpcl.title,
          hpcl.course_title_snapshot,
          hpcl.enabled,
          hpcl.created_at,
          hpcl.updated_at,
          lm.kind AS kind,
          c.title AS course_title,
          c.is_published AS course_is_published,
          CASE
            WHEN hpcl.lesson_media_id IS NULL OR lm.id IS NULL THEN 'source_missing'
            WHEN COALESCE(c.is_published, false) = false THEN 'course_unpublished'
            ELSE 'active'
          END AS status
        FROM app.home_player_course_links hpcl
        LEFT JOIN app.lesson_media lm ON lm.id = hpcl.lesson_media_id
        LEFT JOIN app.lessons l ON l.id = lm.lesson_id
        LEFT JOIN app.courses c ON c.id = l.course_id
        WHERE hpcl.teacher_id = %s
        ORDER BY hpcl.created_at DESC
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    items: list[dict[str, Any]] = []
    for row in rows:
        data = dict(row)
        data["course_title"] = (data.get("course_title") or data.get("course_title_snapshot") or "").strip()
        items.append(data)
    return items


async def get_home_player_course_link(
    *, link_id: str, teacher_id: str
) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          hpcl.id,
          hpcl.teacher_id,
          hpcl.lesson_media_id,
          hpcl.title,
          hpcl.course_title_snapshot,
          hpcl.enabled,
          hpcl.created_at,
          hpcl.updated_at,
          lm.kind AS kind,
          c.title AS course_title,
          c.is_published AS course_is_published,
          CASE
            WHEN hpcl.lesson_media_id IS NULL OR lm.id IS NULL THEN 'source_missing'
            WHEN COALESCE(c.is_published, false) = false THEN 'course_unpublished'
            ELSE 'active'
          END AS status
        FROM app.home_player_course_links hpcl
        LEFT JOIN app.lesson_media lm ON lm.id = hpcl.lesson_media_id
        LEFT JOIN app.lessons l ON l.id = lm.lesson_id
        LEFT JOIN app.courses c ON c.id = l.course_id
        WHERE hpcl.id = %s AND hpcl.teacher_id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (link_id, teacher_id))
        row = await cur.fetchone()
    if not row:
        return None
    data = dict(row)
    data["course_title"] = (data.get("course_title") or data.get("course_title_snapshot") or "").strip()
    return data


async def resolve_lesson_media_course_owner(lesson_media_id: str) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          c.created_by AS teacher_id,
          c.title AS course_title,
          c.is_published AS course_is_published,
          lm.kind,
          mo.content_type
        FROM app.lesson_media lm
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.courses c ON c.id = l.course_id
        LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
        WHERE lm.id = %s
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
    query = """
        INSERT INTO app.home_player_course_links (
          teacher_id,
          lesson_media_id,
          title,
          course_title_snapshot,
          enabled
        )
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (teacher_id, lesson_media_id) DO UPDATE
          SET title = EXCLUDED.title,
              course_title_snapshot = EXCLUDED.course_title_snapshot,
              enabled = EXCLUDED.enabled,
              updated_at = now()
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (teacher_id, lesson_media_id, title, course_title_snapshot, enabled),
        )
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_course_link(link_id=str(row["id"]), teacher_id=teacher_id)


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
        UPDATE app.home_player_course_links
           SET {", ".join(assignments)},
               updated_at = now()
         WHERE id = %(link_id)s AND teacher_id = %(teacher_id)s
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
    if not row:
        return None
    return await get_home_player_course_link(link_id=link_id, teacher_id=teacher_id)


async def delete_home_player_course_link(*, link_id: str, teacher_id: str) -> bool:
    query = """
        DELETE FROM app.home_player_course_links
        WHERE id = %s AND teacher_id = %s
        RETURNING id
    """
    async with get_conn() as cur:
        await cur.execute(query, (link_id, teacher_id))
        row = await cur.fetchone()
    return bool(row)


async def get_active_home_upload_by_media_id(media_id: str) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          hpu.teacher_id,
          hpu.active,
          mo.id AS media_id,
          mo.storage_path,
          mo.storage_bucket,
          mo.content_type,
          mo.byte_size,
          mo.original_name
        FROM app.home_player_uploads hpu
        JOIN app.media_objects mo ON mo.id = hpu.media_id
        WHERE hpu.active = true
          AND hpu.media_id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (media_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_active_home_upload_by_media_asset_id(media_id: str) -> Optional[dict[str, Any]]:
    query = """
        SELECT
          hpu.teacher_id,
          hpu.active,
          ma.id AS media_asset_id,
          ma.storage_bucket,
          ma.streaming_object_path,
          ma.streaming_storage_bucket,
          ma.state
        FROM app.home_player_uploads hpu
        JOIN app.media_assets ma ON ma.id = hpu.media_asset_id
        WHERE hpu.active = true
          AND hpu.media_asset_id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (media_id,))
        row = await cur.fetchone()
    return dict(row) if row else None
