from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

from ..repositories import media_assets as media_assets_repo
from ..config import settings


async def resolve_runtime_media_playback_url(runtime_media: dict[str, Any]) -> str:
    lesson_media_id = runtime_media.get("lesson_media_id")
    if not lesson_media_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Playable media not found",
        )
    return f"/api/media/stream/{lesson_media_id}"


async def resolve_runtime_media_stream_source(
    runtime_media: dict[str, Any],
) -> dict[str, Any]:
    lesson_media_id = runtime_media.get("lesson_media_id")
    if not lesson_media_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Playable media not found",
        )

    media_asset_id = runtime_media.get("media_asset_id")
    if media_asset_id is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Playable media not found",
        )

    media = await media_assets_repo.get_media_asset_access(str(media_asset_id))
    if not media:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Playable media not found",
        )

    storage_path = media.get("streaming_object_path") or media.get("original_object_path")
    storage_bucket = media.get("streaming_storage_bucket") or media.get("storage_bucket")
    if not storage_path or not storage_bucket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Playable media not found",
        )

    return {
        "id": str(lesson_media_id),
        "kind": media.get("media_type"),
        "storage_path": str(storage_path),
        "storage_bucket": str(storage_bucket or settings.media_source_bucket),
        "content_type": None,
        "original_name": None,
    }
