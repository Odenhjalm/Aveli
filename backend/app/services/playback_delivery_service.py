from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

from .. import models
from ..repositories import media_assets as media_assets_repo


async def resolve_runtime_media_playback_url(runtime_media: dict[str, Any]) -> str:
    runtime_media_id = runtime_media.get("id")
    if not runtime_media_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Playable media not found",
        )
    return f"/api/media/stream/{runtime_media_id}"


async def resolve_runtime_media_stream_source(
    runtime_media: dict[str, Any],
) -> dict[str, Any]:
    runtime_media_id = runtime_media.get("id")
    if not runtime_media_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Playable media not found",
        )

    media_asset_id = runtime_media.get("media_asset_id")
    if media_asset_id is not None:
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
            "id": str(runtime_media_id),
            "kind": media.get("media_type"),
            "storage_path": str(storage_path),
            "storage_bucket": str(storage_bucket),
            "content_type": media.get("original_content_type"),
            "original_name": media.get("original_filename"),
        }

    media_object_id = runtime_media.get("media_object_id")
    if media_object_id is not None:
        media = await models.get_media_object(str(media_object_id))
        if not media:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Playable media not found",
            )

        storage_path = media.get("storage_path")
        storage_bucket = media.get("storage_bucket")
        if not storage_path or not storage_bucket:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Playable media not found",
            )

        return {
            "id": str(runtime_media_id),
            "kind": None,
            "storage_path": str(storage_path),
            "storage_bucket": str(storage_bucket),
            "content_type": media.get("content_type"),
            "original_name": media.get("original_name"),
        }

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Playable media not found",
    )
