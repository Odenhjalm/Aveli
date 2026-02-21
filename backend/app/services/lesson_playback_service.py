from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import HTTPException, status

from .. import models, repositories
from ..config import settings
from ..db import get_conn
from ..repositories import courses as courses_repo
from ..repositories import media_assets as media_assets_repo
from ..services import courses_service, storage_service
from ..repositories import media_resolution_failures
from ..utils.media_signer import (
    issue_signed_url,
    is_signing_enabled,
)


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
    if (media.get("media_type") or "").lower() != "audio":
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only audio playback is supported",
        )
    if media.get("state") != "ready":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media is not ready",
        )

    purpose = (media.get("purpose") or "").lower()
    if purpose == "lesson_audio":
        await _authorize_lesson_playback(user_id, media)
    elif purpose == "home_player_audio":
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
    else:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    storage_path = media.get("streaming_object_path")
    if not storage_path:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Streaming asset unavailable",
        )

    streaming_bucket = media.get("streaming_storage_bucket") or media.get("storage_bucket")
    storage_client = storage_service.get_storage_service(streaming_bucket)

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
        "format": "mp3",
    }


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
    if not teacher_access:
        if not access_row.get("is_published"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Course not published",
            )
        if not (access_row.get("is_intro") or access_row.get("is_free_intro")):
            if not course_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
            snapshot = await models.course_access_snapshot(user_id, str(course_id))
            if snapshot.get("can_access") is not True:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied",
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

