from __future__ import annotations

from datetime import datetime, timedelta, timezone
import logging
from pathlib import Path
from typing import Any

from fastapi import HTTPException, status

from ..media_control_plane.services.media_resolver_service import (
    LessonMediaPlaybackMode,
    LessonMediaResolution,
    LessonMediaResolutionReason,
    media_resolver_service as canonical_media_resolver,
)
from .. import models, repositories
from ..config import settings
from ..db import get_conn
from ..repositories import courses as courses_repo
from ..repositories import media_assets as media_assets_repo
from ..services import courses_service, media_resolver, storage_service
from ..repositories import media_resolution_failures
from ..utils.media_signer import (
    issue_signed_url,
    is_signing_enabled,
)

logger = logging.getLogger(__name__)


def _playback_format(*, media: dict[str, Any], storage_path: str) -> str:
    explicit = (media.get("streaming_format") or "").strip().lower()
    if explicit:
        return explicit
    suffix = Path(storage_path).suffix.lower().lstrip(".")
    if suffix:
        return suffix
    media_type = (media.get("media_type") or "").strip().lower()
    if media_type:
        return media_type
    return "bin"


def _resolution_is_image(resolution: LessonMediaResolution) -> bool:
    kind = str(resolution.kind or "").strip().lower()
    content_type = str(resolution.content_type or "").strip().lower()
    return kind == "image" or content_type.startswith("image/")


async def _authorize_lesson_playback(user_id: str, row: dict[str, Any]) -> None:
    course_id = row.get("course_id")
    if course_id and await courses_service.is_course_teacher_or_instructor(
        user_id, str(course_id)
    ):
        return
    if not row.get("is_published"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Course not published",
        )
    if row.get("is_intro") or row.get("is_free_intro"):
        return
    if not course_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    snapshot = await models.course_access_snapshot(user_id, str(course_id))
    if snapshot.get("can_access") is True:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")


async def _authorize_home_player_upload_playback(user_id: str, teacher_id: str) -> None:
    if user_id == teacher_id:
        return
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT 1
            FROM app.enrollments e
            JOIN app.courses c ON c.id = e.course_id
            WHERE e.user_id = %s
              AND e.status = 'active'
              AND c.is_published = true
              AND c.created_by = %s
            LIMIT 1
            """,
            (user_id, teacher_id),
        )
        row = await cur.fetchone()
    if not row:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")


async def resolve_pipeline_playback(
    *,
    media_asset_id: str,
    user_id: str,
) -> dict[str, Any]:
    media = await media_assets_repo.get_media_asset_access(str(media_asset_id))
    if not media:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")
    if media.get("state") != "ready":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media is not ready",
        )

    purpose = (media.get("purpose") or "").lower()
    if purpose == "home_player_audio":
        upload = await repositories.get_active_home_upload_by_media_asset_id(
            str(media_asset_id)
        )
        if not upload:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")
        teacher_id = upload.get("teacher_id")
        if not teacher_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Media missing owner",
            )
        await _authorize_home_player_upload_playback(user_id, str(teacher_id))
    elif media.get("lesson_id"):
        await _authorize_lesson_playback(user_id, media)
    else:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    storage_path = media.get("streaming_object_path") or media.get("original_object_path")
    if not storage_path:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Streaming asset unavailable",
        )
    media_type = (media.get("media_type") or "").strip().lower()
    if media_type == "audio" and purpose == "lesson_audio" and not media_resolver.is_derived_audio_path(str(storage_path)):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Streaming asset unavailable",
        )

    streaming_bucket = media.get("streaming_storage_bucket") or media.get("storage_bucket")
    return await _build_pipeline_playback_response(
        media=media,
        storage_path=str(storage_path),
        storage_bucket=str(streaming_bucket or settings.media_source_bucket),
    )


async def _authorize_legacy_media_playback(
    *,
    storage_path: str,
    storage_bucket: str,
    user_id: str,
) -> None:
    access_row = await courses_repo.get_lesson_media_access_by_path(
        storage_path=storage_path,
        storage_bucket=storage_bucket,
    )
    if not access_row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")

    course_id = access_row.get("course_id")
    teacher_access = (
        await courses_service.is_course_teacher_or_instructor(user_id, str(course_id))
        if course_id
        else False
    )
    if teacher_access:
        return

    if not access_row.get("is_published"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Course not published",
        )
    if access_row.get("is_intro") or access_row.get("is_free_intro"):
        return
    if not course_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    snapshot = await models.course_access_snapshot(user_id, str(course_id))
    if snapshot.get("can_access") is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied",
        )


async def resolve_object_media_playback(
    *,
    lesson_media_id: str,
    user_id: str,
) -> dict[str, Any]:
    row = await models.get_media(lesson_media_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")

    storage_path = row.get("storage_path")
    storage_bucket = row.get("storage_bucket")
    if not storage_path or not storage_bucket:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")

    await _authorize_legacy_media_playback(
        storage_path=str(storage_path),
        storage_bucket=str(storage_bucket),
        user_id=user_id,
    )

    try:
        playback_url = await media_resolver.resolve_storage_playback_url(
            lesson_media_id=str(row["id"]),
            storage_path=str(storage_path),
            storage_bucket=str(storage_bucket),
            cache_version=(
                str(row["media_id"]) if row.get("media_id") is not None else None
            ),
            require_derived_audio=(str(row.get("kind") or "").strip().lower() == "audio"),
        )
    except (ValueError, storage_service.StorageServiceError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    return {
        "media_id": str(row["id"]),
        "url": playback_url,
        "playback_url": playback_url,
        "storage_path": str(storage_path),
    }


async def _build_pipeline_playback_response(
    *,
    media: dict[str, Any],
    storage_path: str,
    storage_bucket: str,
) -> dict[str, Any]:
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
        "url": presigned.url,
        "expires_at": expires_at,
        "format": _playback_format(media=media, storage_path=storage_path),
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
    if reason == LessonMediaResolutionReason.LEGACY_OBJECT_NOT_FOUND:
        return HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media not found",
        )
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Lesson media has no playable source",
    )


async def _resolve_pipeline_playback_from_resolution(
    *,
    resolution: LessonMediaResolution,
    user_id: str,
) -> dict[str, Any]:
    media_asset_id = resolution.media_asset_id
    storage_path = resolution.storage_path
    storage_bucket = resolution.storage_bucket
    if media_asset_id is None or storage_path is None or storage_bucket is None:
        raise _resolution_http_exception(resolution)

    media = await media_assets_repo.get_media_asset_access(str(media_asset_id))
    if not media:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")
    if media.get("state") != "ready":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media is not ready",
        )

    if resolution.auth_scope == "home_teacher_library":
        teacher_id = resolution.teacher_id
        if not teacher_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Media missing owner",
            )
        await _authorize_home_player_upload_playback(user_id, str(teacher_id))
    elif resolution.auth_scope == "lesson_course":
        await _authorize_lesson_playback(user_id, media)
    else:
        purpose = (media.get("purpose") or "").lower()
        if purpose == "home_player_audio":
            upload = await repositories.get_active_home_upload_by_media_asset_id(
                str(media_asset_id)
            )
            if not upload:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Media not found",
                )
            teacher_id = upload.get("teacher_id")
            if not teacher_id:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Media missing owner",
                )
            await _authorize_home_player_upload_playback(user_id, str(teacher_id))
        elif media.get("lesson_id"):
            await _authorize_lesson_playback(user_id, media)
        else:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    return await _build_pipeline_playback_response(
        media=media,
        storage_path=storage_path,
        storage_bucket=storage_bucket,
    )


async def _resolve_legacy_storage_playback_from_resolution(
    *,
    resolution: LessonMediaResolution,
    user_id: str,
) -> dict[str, Any]:
    storage_path = resolution.storage_path
    storage_bucket = resolution.storage_bucket
    if storage_path is None or storage_bucket is None:
        raise _resolution_http_exception(resolution)

    if resolution.auth_scope == "home_teacher_library":
        teacher_id = resolution.teacher_id
        if teacher_id is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Media missing owner",
            )
        await _authorize_home_player_upload_playback(user_id, teacher_id)
    else:
        await _authorize_legacy_media_playback(
            storage_path=storage_path,
            storage_bucket=storage_bucket,
            user_id=user_id,
        )

    try:
        playback_url = await media_resolver.resolve_storage_playback_url(
            lesson_media_id=resolution.lesson_media_id or resolution.runtime_media_id,
            storage_path=storage_path,
            storage_bucket=storage_bucket,
            cache_version=resolution.legacy_media_object_id,
            require_derived_audio=(str(resolution.kind or "").strip().lower() == "audio"),
        )
    except (ValueError, storage_service.StorageServiceError) as exc:
        logger.warning(
            "LESSON_MEDIA_LEGACY_PLAYBACK_FAILED",
            extra={
                **resolution.log_fields(),
                "error": str(exc),
            },
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    return {
        "media_id": resolution.lesson_media_id,
        "url": playback_url,
        "playback_url": playback_url,
        "storage_path": storage_path,
    }


async def _resolve_playback_from_resolution(
    *,
    resolution: LessonMediaResolution,
    user_id: str,
) -> dict[str, Any]:
    if resolution.playback_mode == LessonMediaPlaybackMode.PIPELINE_ASSET:
        return await _resolve_pipeline_playback_from_resolution(
            resolution=resolution,
            user_id=user_id,
        )

    if resolution.playback_mode == LessonMediaPlaybackMode.LEGACY_STORAGE:
        allow_lesson_media_passthrough = (
            resolution.reference_type == "lesson_media"
            and _resolution_is_image(resolution)
        )
        if resolution.reference_type == "lesson_media" and not allow_lesson_media_passthrough:
            logger.warning(
                "LEGACY_LESSON_MEDIA_PLAYBACK_BLOCKED",
                extra=resolution.log_fields(),
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Lesson media has no playable source",
            )
        return await _resolve_legacy_storage_playback_from_resolution(
            resolution=resolution,
            user_id=user_id,
        )

    raise _resolution_http_exception(resolution)


async def resolve_runtime_media_playback(
    *,
    runtime_media_id: str,
    user_id: str,
) -> dict[str, Any]:
    resolution = await canonical_media_resolver.resolve_runtime_media(runtime_media_id)
    playback = await _resolve_playback_from_resolution(
        resolution=resolution,
        user_id=user_id,
    )

    playback_url = str(playback["url"])
    return {
        **playback,
        "runtime_media_id": resolution.runtime_media_id or runtime_media_id,
        "lesson_media_id": resolution.lesson_media_id,
        "playback_url": playback_url,
        "url": playback_url,
        "kind": resolution.kind,
        "content_type": resolution.content_type,
        "duration_seconds": resolution.duration_seconds,
    }


async def resolve_lesson_media_playback(
    *,
    lesson_media_id: str,
    user_id: str,
) -> dict[str, Any]:
    runtime_media_id = await canonical_media_resolver.lookup_runtime_media_id_for_lesson_media(
        lesson_media_id
    )
    if runtime_media_id is None:
        resolution = await canonical_media_resolver.resolve_lesson_media(lesson_media_id)
        return await _resolve_playback_from_resolution(
            resolution=resolution,
            user_id=user_id,
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
    row = await models.get_media(lesson_media_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")

    normalized_mode = media_resolution_failures.normalize_mode(mode)
    if not is_signing_enabled():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Media signing disabled",
        )

    storage_path = row.get("storage_path")
    storage_bucket = row.get("storage_bucket")
    if not storage_path or not storage_bucket:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")

    await _authorize_legacy_media_playback(
        storage_path=storage_path,
        storage_bucket=storage_bucket,
        user_id=user_id,
    )

    issued = issue_signed_url(str(row["id"]), purpose=normalized_mode)
    if not issued:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to create signed URL",
        )

    signed_url, expires_at = issued
    return {
        "media_id": str(row["id"]),
        "url": signed_url,
        "expires_at": expires_at,
    }
