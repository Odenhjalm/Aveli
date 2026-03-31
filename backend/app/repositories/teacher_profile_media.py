from __future__ import annotations

from typing import Any, Optional

from ..db import get_conn
from ..utils import media_signer

_ITEM_SELECT = """
    select
        tpm.id,
        tpm.teacher_id,
        tpm.media_kind,
        tpm.lesson_media_id,
        tpm.seminar_recording_id,
        tpm.external_url,
        tpm.title,
        tpm.description,
        tpm.cover_media_id,
        tpm.cover_image_url,
        tpm.position,
        tpm.is_published,
        tpm.enabled_for_home_player,
        tpm.created_at,
        tpm.updated_at
    from app.teacher_profile_media tpm
"""


async def list_teacher_profile_media(teacher_id: str) -> list[dict[str, Any]]:
    query = (
        _ITEM_SELECT
        + """
        where tpm.teacher_id = %(teacher_id)s
        order by tpm.position asc, tpm.created_at asc
        """
    )
    async with get_conn() as cur:
        await cur.execute(query, {"teacher_id": teacher_id})
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_teacher_profile_media(
    *,
    item_id: str,
    teacher_id: str,
) -> Optional[dict[str, Any]]:
    query = (
        _ITEM_SELECT
        + """
        where tpm.id = %(item_id)s
          and tpm.teacher_id = %(teacher_id)s
        limit 1
        """
    )
    async with get_conn() as cur:
        await cur.execute(query, {"item_id": item_id, "teacher_id": teacher_id})
        row = await cur.fetchone()
    return dict(row) if row else None


async def create_teacher_profile_media(
    *,
    teacher_id: str,
    media_kind: str,
    lesson_media_id: Optional[str],
    seminar_recording_id: Optional[str],
    external_url: Optional[str],
    title: Optional[str],
    description: Optional[str],
    cover_media_id: Optional[str],
    cover_image_url: Optional[str],
    position: int,
    is_published: bool,
    enabled_for_home_player: bool,
) -> Optional[dict[str, Any]]:
    params: dict[str, Any] = {
        "teacher_id": teacher_id,
        "media_kind": media_kind,
        "lesson_media_id": lesson_media_id,
        "seminar_recording_id": seminar_recording_id,
        "external_url": external_url,
        "title": title,
        "description": description,
        "cover_media_id": cover_media_id,
        "cover_image_url": cover_image_url,
        "position": position,
        "is_published": is_published,
        "enabled_for_home_player": enabled_for_home_player,
    }
    query = """
        insert into app.teacher_profile_media (
            teacher_id,
            media_kind,
            lesson_media_id,
            seminar_recording_id,
            external_url,
            title,
            description,
            cover_media_id,
            cover_image_url,
            position,
            is_published,
            enabled_for_home_player
        )
        values (
            %(teacher_id)s,
            %(media_kind)s,
            %(lesson_media_id)s,
            %(seminar_recording_id)s,
            %(external_url)s,
            %(title)s,
            %(description)s,
            %(cover_media_id)s,
            %(cover_image_url)s,
            %(position)s,
            %(is_published)s,
            %(enabled_for_home_player)s
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
            l.lesson_title,
            l.position as lesson_position,
            c.id as course_id,
            c.title as course_title,
            c.slug as course_slug,
            lm.kind,
            case
                when ma.id is not null then
                    case when ma.state = 'ready' then ma.streaming_object_path else null end
                else coalesce(mo.storage_path, lm.storage_path)
            end as storage_path,
            case
                when ma.id is not null then
                    case when ma.state = 'ready' then ma.storage_bucket else null end
                else coalesce(mo.storage_bucket, lm.storage_bucket)
            end as storage_bucket,
            mo.content_type,
            mo.byte_size,
            lm.media_asset_id,
            coalesce(ma.duration_seconds, lm.duration_seconds) as duration_seconds,
            ma.state as media_state,
            lm.position,
            lm.created_at
        from app.lesson_media lm
        join app.lessons l on l.id = lm.lesson_id
        join app.courses c on c.id = l.course_id
        left join app.media_objects mo on mo.id = lm.media_id
        left join app.media_assets ma on ma.id = lm.media_asset_id
        where c.created_by = %s
        order by c.title asc, l.position asc, lm.position asc
    """
    async with get_conn() as cur:
        await cur.execute(query, (teacher_id,))
        rows = await cur.fetchall()
    items: list[dict[str, Any]] = []
    for row in rows:
        items.append(_attach_lesson_links(dict(row)))
    return items


async def list_public_teacher_profile_media(teacher_id: str) -> list[dict[str, Any]]:
    query = (
        _ITEM_SELECT
        + """
        where tpm.teacher_id = %(teacher_id)s
          and tpm.is_published = true
        order by tpm.position asc, tpm.created_at asc
        """
    )
    async with get_conn() as cur:
        await cur.execute(query, {"teacher_id": teacher_id})
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


def _attach_lesson_links(data: dict[str, Any]) -> dict[str, Any]:
    if data.get("media_asset_id"):
        return data
    storage_bucket = data.get("storage_bucket")
    storage_path = data.get("storage_path")
    if not storage_bucket or not storage_path:
        return data
    lesson = {
        "id": data.get("id"),
        "storage_bucket": storage_bucket,
        "storage_path": storage_path,
        "media_asset_id": data.get("media_asset_id"),
        "media_state": data.get("media_state"),
    }
    media_signer.attach_media_links(lesson, purpose="editor_preview")
    if (
        lesson.get("media_asset_id") is None
        or str(lesson.get("media_state") or "").strip().lower() != "ready"
    ):
        media_signer.strip_renderable_media_links(lesson)
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
    return [dict(row) for row in rows]
