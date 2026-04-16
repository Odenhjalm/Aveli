from __future__ import annotations

from pathlib import Path
from typing import Any, Dict
from uuid import UUID

from .. import schemas
from ..config import settings
from ..repositories import runtime_media as runtime_media_repo
from ..services import storage_service

_PROFILE_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)


def _require_uuid(value: Any, field: str) -> UUID:
    if isinstance(value, UUID):
        return value
    if value is None:
        raise ValueError(f"Missing UUID for {field}")
    return UUID(str(value))


def _require_str(value: Any | None, field: str) -> str:
    if value is None:
        raise ValueError(f"Missing string for {field}")
    return str(value)


def _normalized_profile_media_state(value: Any) -> str | None:
    normalized = str(value or "").strip().lower()
    if normalized not in _PROFILE_MEDIA_STATES:
        return None
    return normalized


async def resolved_profile_media_url(runtime_row: Dict[str, Any]) -> str | None:
    media_type = str(runtime_row.get("media_type") or "").strip().lower()
    playback_object_path = str(runtime_row.get("playback_object_path") or "").strip()
    playback_format = str(runtime_row.get("playback_format") or "").strip().lower()
    if not media_type or not playback_object_path:
        return None

    if media_type == "image":
        return storage_service.get_storage_service(
            settings.media_public_bucket
        ).public_url(playback_object_path)

    expected_format = {
        "audio": "mp3",
        "video": "mp4",
        "document": "pdf",
    }.get(media_type)
    if expected_format is None or playback_format != expected_format:
        return None

    try:
        presigned = await storage_service.get_storage_service(
            settings.media_source_bucket
        ).get_presigned_url(
            playback_object_path,
            ttl=settings.media_playback_url_ttl_seconds,
            filename=Path(playback_object_path).name or f"media.{playback_format}",
            download=False,
        )
    except storage_service.StorageServiceError:
        return None
    resolved_url = str(presigned.url or "").strip()
    return resolved_url or None


async def resolve_profile_avatar_photo_url(
    media_asset_id: str | UUID | None,
) -> str | None:
    exact_media_asset_id = str(media_asset_id or "").strip()
    if not exact_media_asset_id:
        return None

    runtime_row = await runtime_media_repo.get_profile_runtime_media(
        media_asset_id=exact_media_asset_id,
    )
    if runtime_row is None:
        return None
    if str(runtime_row.get("state") or "").strip().lower() != "ready":
        return None
    if str(runtime_row.get("media_type") or "").strip().lower() != "image":
        return None
    return await resolved_profile_media_url(runtime_row)


async def profile_projection_with_avatar(profile: dict[str, Any]) -> dict[str, Any]:
    payload = dict(profile)
    payload["photo_url"] = await resolve_profile_avatar_photo_url(
        payload.get("avatar_media_id"),
    )
    return payload


async def profile_media_item_from_row(
    row: Dict[str, Any],
) -> schemas.TeacherProfileMediaItem:
    data = dict(row)
    item_id = _require_uuid(data.get("id"), "profile_media_placements.id")
    subject_user_id = _require_uuid(
        data.get("subject_user_id"), "profile_media_placements.subject_user_id"
    )
    media_asset_id = _require_uuid(
        data.get("media_asset_id"), "profile_media_placements.media_asset_id"
    )
    visibility = _require_str(
        data.get("visibility"), "profile_media_placements.visibility"
    )

    runtime_row = await runtime_media_repo.get_profile_runtime_media(
        media_asset_id=str(media_asset_id),
    )
    media: schemas.ResolvedMedia | None = None
    if runtime_row is not None:
        state = _normalized_profile_media_state(runtime_row.get("state"))
        if state is not None:
            resolved_url: str | None = None
            if state == "ready":
                resolved_url = await resolved_profile_media_url(runtime_row)
            media = schemas.ResolvedMedia(
                media_id=media_asset_id,
                state=state,
                resolved_url=resolved_url,
            )

    return schemas.TeacherProfileMediaItem(
        id=item_id,
        subject_user_id=subject_user_id,
        media_asset_id=media_asset_id,
        visibility=visibility,
        media=media,
    )
