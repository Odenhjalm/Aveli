from __future__ import annotations

from typing import Any, Optional

from psycopg.types.json import Jsonb

from ..db import get_conn
from ..utils import media_signer

_BASE_SELECT = """
    select
        tpm.id,
        tpm.teacher_id,
        tpm.media_kind,
        tpm.media_id,
        tpm.external_url,
        tpm.title,
        tpm.description,
        tpm.cover_media_id,
        tpm.cover_image_url,
        tpm.position,
        tpm.is_published,
        tpm.metadata,
        tpm.created_at,
        tpm.updated_at,
        lm.id as lesson_media_id,
        lm.lesson_id,
        lm.kind as lesson_media_kind,
        lm.position as lesson_media_position,
        lm.duration_seconds as lesson_media_duration_seconds,
        lm.created_at as lesson_media_created_at,
        coalesce(mo.storage_path, lm.storage_path) as lesson_media_storage_path,
        coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media') as lesson_media_storage_bucket,
        mo.content_type as lesson_media_content_type,
        mo.byte_size as lesson_media_byte_size,
        mo.original_name as lesson_media_original_name,
        l.title as lesson_title,
        l.position as lesson_position,
        m.id as module_id,
        c.id as course_id,
        c.title as course_title,
        c.slug as course_slug,
        sr.id as seminar_recording_id,
        sr.seminar_id as seminar_id,
        sr.session_id as seminar_session_id,
        sr.asset_url as seminar_recording_asset_url,
        sr.status as seminar_recording_status,
        sr.duration_seconds as seminar_recording_duration_seconds,
        sr.byte_size as seminar_recording_byte_size,
        sr.published as seminar_recording_published,
        sr.metadata as seminar_recording_metadata,
        sr.created_at as seminar_recording_created_at,
        sr.updated_at as seminar_recording_updated_at,
        sem.title as seminar_title
    from app.teacher_profile_media tpm
    left join app.lesson_media lm
        on tpm.media_kind = 'lesson_media' and tpm.media_id = lm.id
    left join app.media_objects mo on mo.id = lm.media_id
    left join app.lessons l on l.id = lm.lesson_id
    left join app.modules m on m.id = l.module_id
    left join app.courses c on c.id = m.course_id
    left join app.seminar_recordings sr
        on tpm.media_kind = 'seminar_recording' and tpm.media_id = sr.id
    left join app.seminars sem on sem.id = sr.seminar_id
"""


def _normalize_row(row: Any) -> dict[str, Any]:
    data = dict(row)
    if data.get("metadata") is None:
        data["metadata"] = {}
    if data.get("seminar_recording_metadata") is None:
        data["seminar_recording_metadata"] = {}
    if data.get("lesson_media_storage_bucket") is None:
        data["lesson_media_storage_bucket"] = "lesson-media"
    return data


async def list_teacher_profile_media(teacher_id: str) -> list[dict[str, Any]]:
    query = (
        _BASE_SELECT
        + """
        where tpm.teacher_id = %(teacher_id)s
        order by tpm.position asc, tpm.created_at asc
        """
    )
    async with get_conn() as cur:
        await cur.execute(query, {"teacher_id": teacher_id})
        rows = await cur.fetchall()
    return [_populate_media_links(_normalize_row(row)) for row in rows]


async def get_teacher_profile_media(
    *,
    item_id: str,
    teacher_id: str,
) -> Optional[dict[str, Any]]:
    query = (
        _BASE_SELECT
        + """
        where tpm.id = %(item_id)s
          and tpm.teacher_id = %(teacher_id)s
        limit 1
        """
    )
    async with get_conn() as cur:
        await cur.execute(query, {"item_id": item_id, "teacher_id": teacher_id})
        row = await cur.fetchone()
    return _populate_media_links(_normalize_row(row)) if row else None


async def create_teacher_profile_media(
    *,
    teacher_id: str,
    media_kind: str,
    media_id: Optional[str] = None,
    external_url: Optional[str] = None,
    title: Optional[str] = None,
    description: Optional[str] = None,
    cover_media_id: Optional[str] = None,
    cover_image_url: Optional[str] = None,
    position: Optional[int] = None,
    is_published: Optional[bool] = None,
    metadata: Optional[dict[str, Any]] = None,
) -> Optional[dict[str, Any]]:
    params: dict[str, Any] = {
        "teacher_id": teacher_id,
        "media_kind": media_kind,
        "media_id": media_id,
        "external_url": external_url,
        "title": title,
        "description": description,
        "cover_media_id": cover_media_id,
        "cover_image_url": cover_image_url,
        "position": position,
        "is_published": is_published,
        "metadata": Jsonb(metadata or {}),
    }
    query = """
        insert into app.teacher_profile_media (
            teacher_id,
            media_kind,
            media_id,
            external_url,
            title,
            description,
            cover_media_id,
            cover_image_url,
            position,
            is_published,
            metadata
        )
        values (
            %(teacher_id)s,
            %(media_kind)s,
            %(media_id)s,
            %(external_url)s,
            %(title)s,
            %(description)s,
            %(cover_media_id)s,
            %(cover_image_url)s,
            coalesce(
                %(position)s,
                (
                    select coalesce(max(position), -1) + 1
                    from app.teacher_profile_media
                    where teacher_id = %(teacher_id)s
                )
            ),
            coalesce(%(is_published)s, true),
            %(metadata)s
        )
        returning id
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
        if not row:
            return None
        item_id = row["id"]
    return await get_teacher_profile_media(item_id=item_id, teacher_id=teacher_id)


async def update_teacher_profile_media(
    *,
    item_id: str,
    teacher_id: str,
    fields: dict[str, Any],
) -> Optional[dict[str, Any]]:
    if not fields:
        return await get_teacher_profile_media(item_id=item_id, teacher_id=teacher_id)

    params: dict[str, Any] = {
        "item_id": item_id,
        "teacher_id": teacher_id,
    }
    assignments: list[str] = []
    for key, value in fields.items():
        if key == "metadata" and value is not None:
            params[key] = Jsonb(value)
        else:
            params[key] = value
        assignments.append(f"{key} = %({key})s")

    query = f"""
        update app.teacher_profile_media
           set {", ".join(assignments)},
               updated_at = now()
         where id = %(item_id)s
           and teacher_id = %(teacher_id)s
        returning id
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
        if not row:
            return None
    return await get_teacher_profile_media(item_id=item_id, teacher_id=teacher_id)


async def delete_teacher_profile_media(
    *,
    item_id: str,
    teacher_id: str,
) -> bool:
    query = """
        delete from app.teacher_profile_media
        where id = %s
          and teacher_id = %s
        returning id
    """
    async with get_conn() as cur:
        await cur.execute(query, (item_id, teacher_id))
        row = await cur.fetchone()
    return bool(row)


async def list_teacher_lesson_media_sources(teacher_id: str) -> list[dict[str, Any]]:
    query = """
        select
            lm.id,
            lm.lesson_id,
            l.title as lesson_title,
            l.position as lesson_position,
            m.id as module_id,
            c.id as course_id,
            c.title as course_title,
            c.slug as course_slug,
            lm.kind,
            coalesce(mo.storage_path, lm.storage_path) as storage_path,
            coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media') as storage_bucket,
            mo.content_type,
            mo.byte_size,
            lm.duration_seconds,
            lm.position,
            lm.created_at
        from app.lesson_media lm
        join app.lessons l on l.id = lm.lesson_id
        join app.modules m on m.id = l.module_id
        join app.courses c on c.id = m.course_id
        left join app.media_objects mo on mo.id = lm.media_id
        where c.created_by = %s
        order by c.title asc, l.position asc, lm.position asc
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    items: list[dict[str, Any]] = []
    for row in rows:
        data = dict(row)
        if data.get("storage_bucket") is None:
            data["storage_bucket"] = "lesson-media"
        items.append(_attach_lesson_links(data))
    return items


async def list_public_teacher_profile_media(teacher_id: str) -> list[dict[str, Any]]:
    query = (
        _BASE_SELECT
        + """
        where tpm.teacher_id = %(teacher_id)s
          and tpm.is_published = true
        order by tpm.position asc, tpm.created_at asc
        """
    )
    async with get_conn() as cur:
        await cur.execute(query, {"teacher_id": teacher_id})
        rows = await cur.fetchall()
    return [_populate_media_links(_normalize_row(row)) for row in rows]


def _attach_lesson_links(data: dict[str, Any]) -> dict[str, Any]:
    lesson = {
        "id": data.get("id"),
        "storage_bucket": data.get("storage_bucket") or "lesson-media",
        "storage_path": data.get("storage_path"),
    }
    media_signer.attach_media_links(lesson)
    download_url = lesson.get("download_url")
    signed_url = lesson.get("signed_url")
    signed_expires = lesson.get("signed_url_expires_at")
    if download_url:
        data["download_url"] = download_url
    if signed_url:
        data["signed_url"] = signed_url
    if signed_expires:
        data["signed_url_expires_at"] = signed_expires
    return data


async def list_teacher_seminar_recording_sources(teacher_id: str) -> list[dict[str, Any]]:
    query = """
        select
            sr.id,
            sr.seminar_id,
            sem.title as seminar_title,
            sr.session_id,
            sr.asset_url,
            sr.status,
            sr.duration_seconds,
            sr.byte_size,
            sr.published,
            sr.metadata,
            sr.created_at,
            sr.updated_at
        from app.seminar_recordings sr
        join app.seminars sem on sem.id = sr.seminar_id
        where sem.host_id = %s
        order by sr.created_at desc
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    items: list[dict[str, Any]] = []
    for row in rows:
        data = dict(row)
        if data.get("metadata") is None:
            data["metadata"] = {}
        items.append(data)
    return items


def _populate_media_links(row: dict[str, Any]) -> dict[str, Any]:
    data = dict(row)
    if data.get("lesson_media_id"):
        lesson = {
            "id": data["lesson_media_id"],
            "storage_bucket": data.get("lesson_media_storage_bucket")
            or "lesson-media",
            "storage_path": data.get("lesson_media_storage_path"),
        }
        media_signer.attach_media_links(lesson)
        download_url = lesson.get("download_url")
        signed_url = lesson.get("signed_url")
        expires_at = lesson.get("signed_url_expires_at")
        if download_url:
            data["lesson_media_download_url"] = download_url
        if signed_url:
            data["lesson_media_signed_url"] = signed_url
        if expires_at:
            data["lesson_media_signed_url_expires_at"] = expires_at
    return data
