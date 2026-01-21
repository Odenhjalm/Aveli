from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, status

from .. import models, schemas
from ..auth import CurrentUser
from ..config import settings
from ..permissions import TeacherUser
from ..repositories import courses as courses_repo
from ..repositories import seminars as seminars_repo
from ..services import courses_service, storage_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/media", tags=["media"])

_MIN_MEDIA_BYTES = 5 * 1024 * 1024 * 1024
_AUDIO_MIME_TYPES = {"audio/mpeg", "audio/mp3", "audio/aac", "audio/mp4"}
_VIDEO_MIME_TYPES = {"video/mp4"}
_WAV_MIME_TYPES = {"audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave"}


def _normalize_mime(value: str) -> str:
    return (value or "").strip().lower()


def _build_object_path(
    media_type: str,
    resource_prefix: Path,
    filename: str,
) -> str:
    safe_name = Path(filename).name.strip()
    if not safe_name:
        safe_name = "media"
    token = uuid4().hex
    path = Path("media") / media_type / resource_prefix / f"{token}_{safe_name}"
    return path.as_posix()


def _upload_max_bytes(media_type: str) -> int:
    if media_type == "audio":
        configured = settings.media_upload_max_audio_bytes
    else:
        configured = settings.media_upload_max_video_bytes
    return max(int(configured), _MIN_MEDIA_BYTES)


async def _authorize_lesson_upload(
    *,
    user_id: str,
    lesson_id: str,
    course_id: UUID | None,
) -> str:
    lesson = await models.get_lesson(lesson_id)
    if not lesson:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lesson not found")

    _, resolved_course_id = await models.lesson_course_ids(lesson_id)
    if not resolved_course_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Lesson missing course")

    if course_id is not None and str(course_id) != resolved_course_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="course_id does not match lesson course",
        )

    if not await models.is_course_owner(user_id, resolved_course_id):
        logger.warning(
            "Permission denied: course owner required user_id=%s course_id=%s lesson_id=%s",
            user_id,
            resolved_course_id,
            lesson_id,
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not course owner")

    return resolved_course_id


async def _authorize_course_upload(user_id: str, course_id: str) -> None:
    course = await models.get_course(course_id=course_id)
    if not course:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    if not await models.is_course_owner(user_id, course_id):
        logger.warning(
            "Permission denied: course owner required user_id=%s course_id=%s",
            user_id,
            course_id,
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not course owner")


async def _authorize_seminar_upload(user_id: str, seminar_id: str) -> None:
    seminar = await seminars_repo.get_seminar(seminar_id)
    if not seminar:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Seminar not found")
    if str(seminar.get("host_id")) != user_id:
        logger.warning(
            "Permission denied: seminar host required user_id=%s seminar_id=%s",
            user_id,
            seminar_id,
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not seminar host")


async def _authorize_lesson_playback(user_id: str, row: dict) -> None:
    if str(row.get("created_by")) == user_id:
        return
    if not row.get("is_published"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Course not published")
    if await courses_service.user_has_global_course_access(user_id):
        return
    if row.get("is_intro") or row.get("is_free_intro"):
        return
    course_id = row.get("course_id")
    if course_id and await courses_repo.is_enrolled(user_id, str(course_id)):
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")


async def _authorize_recording_playback(user_id: str, recording: dict) -> None:
    seminar_id = recording.get("seminar_id")
    if not seminar_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Seminar not found")
    seminar = await seminars_repo.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Seminar not found")
    if str(seminar.get("host_id")) == user_id:
        return
    if await seminars_repo.user_has_seminar_access(user_id, seminar):
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")


@router.post("/upload-url", response_model=schemas.MediaUploadUrlResponse)
async def request_upload_url(
    payload: schemas.MediaUploadUrlRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    mime_type = _normalize_mime(payload.mime_type)
    if not mime_type:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="mime_type is required",
        )
    if mime_type in _WAV_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="WAV uploads are not supported",
        )

    if payload.media_type == "audio":
        allowed = _AUDIO_MIME_TYPES
    else:
        allowed = _VIDEO_MIME_TYPES
    if mime_type not in allowed:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )

    max_bytes = _upload_max_bytes(payload.media_type)
    if payload.size_bytes > max_bytes:
        max_gb = max_bytes // (1024 * 1024 * 1024)
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File too large (max {max_gb} GB)",
        )

    course_id: str | None = None
    resource_prefix = None
    if payload.seminar_id is not None:
        if payload.lesson_id is not None or payload.course_id is not None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="seminar_id cannot be combined with course_id or lesson_id",
            )
        seminar_id = str(payload.seminar_id)
        await _authorize_seminar_upload(user_id, seminar_id)
        resource_prefix = Path("seminars") / seminar_id
    elif payload.lesson_id is not None:
        lesson_id = str(payload.lesson_id)
        course_id = await _authorize_lesson_upload(
            user_id=user_id,
            lesson_id=lesson_id,
            course_id=payload.course_id,
        )
        course_id = str(course_id)
        resource_prefix = Path("courses") / course_id / "lessons" / lesson_id
    elif payload.course_id is not None:
        course_id = str(payload.course_id)
        await _authorize_course_upload(user_id, course_id)
        resource_prefix = Path("courses") / course_id
    else:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="course_id, lesson_id, or seminar_id is required",
        )

    object_path = _build_object_path(payload.media_type, resource_prefix, payload.filename)
    try:
        upload = await storage_service.storage_service.create_upload_url(
            object_path,
            content_type=mime_type,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Upload URL issuance failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    logger.info(
        "Issued media upload URL user_id=%s media_type=%s size_bytes=%s path=%s",
        user_id,
        payload.media_type,
        payload.size_bytes,
        upload.path,
    )
    return schemas.MediaUploadUrlResponse(
        upload_url=upload.url,
        object_path=upload.path,
        expires_at=expires_at,
    )


@router.post("/playback-url", response_model=schemas.MediaPlaybackUrlResponse)
async def request_playback_url(
    payload: schemas.MediaPlaybackUrlRequest,
    current: CurrentUser,
):
    user_id = str(current["id"])
    raw_path = (payload.object_path or "").strip()
    if not raw_path:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="object_path is required",
        )

    normalized = raw_path.lstrip("/")
    bucket = storage_service.storage_service.bucket
    prefix = f"{bucket}/"
    storage_path = normalized[len(prefix) :] if normalized.startswith(prefix) else normalized

    row = await courses_repo.get_lesson_media_access_by_path(
        storage_path=storage_path,
        storage_bucket=bucket,
    )
    if row:
        await _authorize_lesson_playback(user_id, dict(row))
    else:
        recording = await seminars_repo.get_recording_by_asset_url(storage_path)
        if not recording:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")
        await _authorize_recording_playback(user_id, dict(recording))

    try:
        presigned = await storage_service.storage_service.get_presigned_url(
            storage_path,
            ttl=settings.media_playback_url_ttl_seconds,
            filename=Path(storage_path).name,
            download=False,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Playback URL issuance failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=presigned.expires_in)
    logger.info("Issued media playback URL user_id=%s path=%s", user_id, storage_path)
    return schemas.MediaPlaybackUrlResponse(
        playback_url=presigned.url,
        expires_at=expires_at,
    )
