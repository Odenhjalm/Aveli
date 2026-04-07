from __future__ import annotations

from typing import Any, Optional
from uuid import uuid4

from ..db import get_conn


_ITEM_SELECT = """
    select
        pmp.id,
        pmp.subject_user_id,
        pmp.media_asset_id,
        pmp.visibility
    from app.profile_media_placements as pmp
"""


async def list_teacher_profile_media(teacher_id: str) -> list[dict[str, Any]]:
    query = (
        _ITEM_SELECT
        + """
        where pmp.subject_user_id = %(teacher_id)s
        order by pmp.id asc
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
        where pmp.id = %(item_id)s
          and pmp.subject_user_id = %(teacher_id)s
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
    media_asset_id: str,
    visibility: str,
) -> Optional[dict[str, Any]]:
    item_id = str(uuid4())
    params: dict[str, Any] = {
        "item_id": item_id,
        "teacher_id": teacher_id,
        "media_asset_id": media_asset_id,
        "visibility": visibility,
    }
    query = """
        insert into app.profile_media_placements (
            id,
            subject_user_id,
            media_asset_id,
            visibility
        )
        values (
            %(item_id)s,
            %(teacher_id)s,
            %(media_asset_id)s,
            %(visibility)s
        )
        returning id
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
        if not row:
            return None
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
        update app.profile_media_placements
           set {", ".join(assignments)}
         where id = %(item_id)s
           and subject_user_id = %(teacher_id)s
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
        delete from app.profile_media_placements
        where id = %s
          and subject_user_id = %s
        returning id
    """
    async with get_conn() as cur:
        await cur.execute(query, (item_id, teacher_id))
        row = await cur.fetchone()
    return bool(row)


async def list_public_teacher_profile_media(teacher_id: str) -> list[dict[str, Any]]:
    query = (
        _ITEM_SELECT
        + """
        where pmp.subject_user_id = %(teacher_id)s
          and pmp.visibility = 'published'
        order by pmp.id asc
        """
    )
    async with get_conn() as cur:
        await cur.execute(query, {"teacher_id": teacher_id})
        rows = await cur.fetchall()
    return [dict(row) for row in rows]
