from __future__ import annotations

from pathlib import PurePosixPath
from typing import Any, Optional
from uuid import uuid4

from ..db import get_conn
from . import media_assets as media_assets_repo


_PROFILE_MEDIA_BINDING_STATES = frozenset({"uploaded", "processing", "ready"})
_PROFILE_MEDIA_SOURCE_PREFIXES = (
    ("media", "source", "profile-avatar"),
    ("media", "source", "profile-media"),
    ("media", "source", "profile"),
)

_ITEM_SELECT = """
    select
        pmp.id,
        pmp.subject_user_id,
        pmp.media_asset_id,
        pmp.visibility
    from app.profile_media_placements as pmp
"""


def _normalized_string(value: Any) -> str:
    return str(value or "").strip()


def _normalized_media_path(value: Any) -> str:
    return _normalized_string(value).replace("\\", "/").lstrip("/")


def _profile_media_path_subject_user_id(asset: dict[str, Any]) -> str | None:
    object_path = _normalized_media_path(asset.get("original_object_path"))
    if not object_path:
        return None

    parts = PurePosixPath(object_path).parts
    for prefix in _PROFILE_MEDIA_SOURCE_PREFIXES:
        if len(parts) <= len(prefix) + 1:
            continue
        if parts[: len(prefix)] != prefix:
            continue
        subject_user_id = _normalized_string(parts[len(prefix)])
        return subject_user_id or None
    return None


def _profile_media_asset_belongs_to_subject(
    *,
    asset: dict[str, Any],
    teacher_id: str,
) -> bool:
    normalized_teacher_id = _normalized_string(teacher_id)
    for owner_key in ("owner_id", "subject_user_id", "user_id"):
        owner_id = _normalized_string(asset.get(owner_key))
        if owner_id:
            return owner_id == normalized_teacher_id

    path_subject_user_id = _profile_media_path_subject_user_id(asset)
    return bool(path_subject_user_id and path_subject_user_id == normalized_teacher_id)


async def validate_profile_media_asset_for_subject(
    *,
    teacher_id: str,
    media_asset_id: str,
) -> dict[str, Any] | None:
    media_asset = await media_assets_repo.get_media_asset(media_asset_id)
    if not media_asset:
        return None

    if _normalized_string(media_asset.get("purpose")).lower() != "profile_media":
        return None
    if _normalized_string(media_asset.get("media_type")).lower() != "image":
        return None
    if (
        _normalized_string(media_asset.get("state")).lower()
        not in _PROFILE_MEDIA_BINDING_STATES
    ):
        return None
    if not _profile_media_asset_belongs_to_subject(
        asset=media_asset,
        teacher_id=teacher_id,
    ):
        return None
    return media_asset


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
    if not await validate_profile_media_asset_for_subject(
        teacher_id=teacher_id,
        media_asset_id=media_asset_id,
    ):
        return None

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

    existing = await get_teacher_profile_media(item_id=item_id, teacher_id=teacher_id)
    if not existing:
        return None

    media_asset_id = str(fields.get("media_asset_id") or existing["media_asset_id"])
    if not await validate_profile_media_asset_for_subject(
        teacher_id=teacher_id,
        media_asset_id=media_asset_id,
    ):
        return None

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
