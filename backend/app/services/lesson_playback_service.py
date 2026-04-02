from __future__ import annotations

from datetime import datetime, timedelta, timezone
import logging
from pathlib import Path
from typing import Any

from fastapi import HTTPException, status

from .. import models
from ..config import settings
from ..media_control_plane.services.media_resolver_service import (
    LessonMediaPlaybackMode,
    LessonMediaResolution,
    LessonMediaResolutionReason,
    media_resolver_service as canonical_media_resolver,
)
from ..services import courses_service, storage_service

logger = logging.getLogger(__name__)


def _exact_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value or None
    return str(value)


def _playback_format(*, resolution: LessonMediaResolution) -> str:
    media_type = _exact_text(resolution.media_type)
    content_type = _exact_text(resolution.content_type)
    if media_type == "audio" and content_type == "audio/mpeg":
        return "mp3"
    if media_type == "image" and content_type == "image/jpeg":
        return "jpg"
    if media_type == "image" and content_type == "image/png":
        return "png"
    if media_type == "video" and content_type == "video/mp4":
        return "mp4"
    if media_type == "document" and content_type == "application/pdf":
        return "pdf"
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Streaming format unavailable",
    )


def _resolution_is_image(resolution: LessonMediaResolution) -> bool:
    return resolution.media_type == "image"


def _playback_resolution_source(resolution: LessonMediaResolution) -> str:
    if resolution.playback_mode == LessonMediaPlaybackMode.PIPELINE_ASSET:
        return "runtime_media_projection"
    return "unknown"


def _log_image_playback_resolution(
    *,
    resolution: LessonMediaResolution,
    playback: dict[str, Any],
) -> None:
    if not _resolution_is_image(resolution):
        return
    resolved_url = _exact_text(playback.get("playback_url"))
    logger.info(
        "LESSON_IMAGE_PLAYBACK_READ lesson_media_id=%s bucket=%s storage_path=%s resolved_url=%s source=%s playback_mode=%s",
        resolution.lesson_media_id or resolution.runtime_media_id or "<missing>",
        resolution.storage_bucket or "<missing>",
        resolution.storage_path or "<missing>",
        resolved_url or "<none>",
        _playback_resolution_source(resolution),
        resolution.playback_mode.value,
    )


async def _authorize_lesson_resolution_playback(
    *,
    user_id: str,
    lesson_id: str | None,
    course_id: str | None,
) -> None:
    exact_lesson_id = _exact_text(lesson_id)
    exact_course_id = _exact_text(course_id)
    if exact_lesson_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Canonical lesson identity required",
        )
    if exact_course_id and await models.is_course_owner(user_id, exact_course_id):
        return
    access = await courses_service.read_canonical_lesson_access(user_id, exact_lesson_id)
    if access["lesson"] is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson not found",
        )
    if access["can_access"]:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")


async def resolve_pipeline_playback(
    *,
    media_asset_id: str,
    user_id: str,
) -> dict[str, Any]:
    del media_asset_id, user_id
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Direct media-asset playback is unavailable in canonical runtime",
    )


async def _authorize_legacy_media_playback(
    *,
    storage_path: str,
    storage_bucket: str,
    user_id: str,
) -> None:
    del storage_path, storage_bucket, user_id
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Legacy playback is unavailable in canonical runtime",
    )


async def resolve_object_media_playback(
    *,
    lesson_media_id: str,
    user_id: str,
) -> dict[str, Any]:
    del lesson_media_id, user_id
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Legacy playback is unavailable in canonical runtime",
    )


async def _build_pipeline_playback_response(
    *,
    resolution: LessonMediaResolution,
) -> dict[str, Any]:
    storage_path = resolution.storage_path
    storage_bucket = resolution.storage_bucket
    if storage_path is None or storage_bucket is None:
        raise _resolution_http_exception(resolution)

    storage_client = storage_service.get_storage_service(storage_bucket)

    try:
        presigned = await storage_client.get_presigned_url(
            storage_path,
            ttl=settings.media_playback_url_ttl_seconds,
            filename=Path(storage_path).name,
            download=False,
        )
    except storage_service.StorageServiceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=presigned.expires_in)
    return {
        "playback_url": presigned.url,
        "expires_at": expires_at,
        "format": _playback_format(resolution=resolution),
    }


def _resolution_http_exception(resolution: LessonMediaResolution) -> HTTPException:
    reason = resolution.failure_reason
    if reason == LessonMediaResolutionReason.LESSON_MEDIA_NOT_FOUND:
        return HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media not found",
        )
    if reason == LessonMediaResolutionReason.ASSET_NOT_READY:
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media is not ready",
        )
    if reason in {
        LessonMediaResolutionReason.INVALID_KIND,
        LessonMediaResolutionReason.INVALID_CONTENT_TYPE,
    }:
        return HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )
    if reason in {
        LessonMediaResolutionReason.MISSING_STORAGE_IDENTITY,
        LessonMediaResolutionReason.MISSING_STORAGE_OBJECT,
        LessonMediaResolutionReason.UNSUPPORTED_MEDIA_CONTRACT,
    }:
        status_code = (
            status.HTTP_503_SERVICE_UNAVAILABLE
            if resolution.media_asset_id
            else status.HTTP_404_NOT_FOUND
        )
        detail = (
            "Streaming asset unavailable"
            if resolution.media_asset_id
            else "Media not found"
        )
        return HTTPException(status_code=status_code, detail=detail)
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Lesson media has no playable source",
    )


async def _resolve_pipeline_playback_from_resolution(
    *,
    resolution: LessonMediaResolution,
    user_id: str,
) -> dict[str, Any]:
    if resolution.media_asset_id is None:
        raise _resolution_http_exception(resolution)

    await _authorize_lesson_resolution_playback(
        user_id=user_id,
        lesson_id=resolution.lesson_id,
        course_id=resolution.course_id,
    )

    return await _build_pipeline_playback_response(resolution=resolution)


async def _resolve_playback_from_resolution(
    *,
    resolution: LessonMediaResolution,
    user_id: str,
) -> dict[str, Any]:
    if resolution.playback_mode != LessonMediaPlaybackMode.PIPELINE_ASSET:
        logger.warning(
            "NON_PIPELINE_PLAYBACK_BLOCKED",
            extra=resolution.log_fields(),
        )
        raise _resolution_http_exception(resolution)

    playback = await _resolve_pipeline_playback_from_resolution(
        resolution=resolution,
        user_id=user_id,
    )
    _log_image_playback_resolution(
        resolution=resolution,
        playback=playback,
    )
    return playback


async def resolve_runtime_media_playback(
    *,
    runtime_media_id: str,
    user_id: str,
) -> dict[str, Any]:
    resolution = await canonical_media_resolver.resolve_runtime_media(runtime_media_id)
    return await _resolve_playback_from_resolution(
        resolution=resolution,
        user_id=user_id,
    )


async def resolve_lesson_media_playback(
    *,
    lesson_media_id: str,
    user_id: str,
) -> dict[str, Any]:
    runtime_media_id = await canonical_media_resolver.lookup_runtime_media_id_for_lesson_media(
        lesson_media_id
    )
    if runtime_media_id is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Active runtime media not found",
        )
    return await resolve_runtime_media_playback(
        runtime_media_id=runtime_media_id,
        user_id=user_id,
    )


async def resolve_legacy_playback(
    *,
    lesson_media_id: str,
    user_id: str,
    mode: str | None = None,
) -> dict[str, Any]:
    del lesson_media_id, user_id, mode
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Legacy playback is unavailable in canonical runtime",
    )
