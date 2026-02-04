from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, status

from .. import models, repositories, schemas
from ..auth import CurrentUser
from ..config import settings
from ..db import get_conn
from ..permissions import TeacherUser
from ..repositories import courses as courses_repo
from ..repositories import media_assets as media_assets_repo
from ..services import media_cleanup
from ..services import storage_service
from ..utils import media_paths

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/media", tags=["media"])

_MIN_MEDIA_BYTES = 5 * 1024 * 1024 * 1024
_WAV_MIME_TYPES = {"audio/wav", "audio/x-wav"}
_COVER_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}


def _normalize_mime(value: str) -> str:
    return (value or "").strip().lower()


def _build_cover_source_object_path(course_id: str, filename: str) -> str:
    safe_name = Path(filename).name.strip()
    if not safe_name:
        safe_name = "cover"
    token = uuid4().hex
    path = Path("media") / "source" / "cover" / "courses" / course_id / f"{token}_{safe_name}"
    return path.as_posix()


def _upload_max_bytes(media_type: str) -> int:
    if media_type == "audio":
        configured = settings.media_upload_max_audio_bytes
    else:
        configured = settings.media_upload_max_video_bytes
    return max(int(configured), _MIN_MEDIA_BYTES)


def _cover_max_bytes() -> int:
    return max(1, int(settings.media_upload_max_image_bytes))


def _cover_ingest_format(mime_type: str, filename: str) -> str:
    if mime_type == "image/jpeg":
        return "jpeg"
    if mime_type == "image/png":
        return "png"
    if mime_type == "image/webp":
        return "webp"
    suffix = Path(filename).suffix.lower().lstrip(".")
    return suffix or "image"


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

    if course_id is not None and str(course_id) != str(resolved_course_id):
        logger.warning(
            "course_id mismatch for lesson upload: provided=%s (type=%s) resolved=%s (type=%s) lesson_id=%s",
            str(course_id),
            type(course_id).__name__,
            str(resolved_course_id),
            type(resolved_course_id).__name__,
            lesson_id,
        )
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


async def _authorize_lesson_playback(user_id: str, row: dict) -> None:
    if str(row.get("created_by")) == user_id:
        return
    if not row.get("is_published"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Course not published")
    if row.get("is_intro") or row.get("is_free_intro"):
        return
    course_id = row.get("course_id")
    if not course_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    snapshot = await models.course_access_snapshot(user_id, str(course_id))
    if snapshot.get("has_access"):
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
    if mime_type not in _WAV_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only WAV uploads are supported",
        )

    max_bytes = _upload_max_bytes(payload.media_type)
    if payload.size_bytes > max_bytes:
        max_gb = max_bytes // (1024 * 1024 * 1024)
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File too large (max {max_gb} GB)",
        )

    purpose = (payload.purpose or "lesson_audio").strip().lower()
    if purpose not in {"lesson_audio", "home_player_audio"}:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Unsupported upload purpose",
        )

    course_id: str | None = None
    lesson_id: str | None = None
    resource_prefix: Path | None = None
    if purpose == "home_player_audio":
        if payload.course_id is not None or payload.lesson_id is not None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="course_id/lesson_id not allowed for home player uploads",
            )
        resource_prefix = Path("home-player") / user_id
    else:
        if payload.lesson_id is not None:
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
                detail="course_id or lesson_id is required",
            )

    object_path = media_paths.build_audio_source_object_path(resource_prefix, payload.filename)
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

    media_asset = await media_assets_repo.create_media_asset(
        owner_id=user_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="audio",
        purpose=purpose,
        ingest_format="wav",
        original_object_path=upload.path,
        original_content_type=mime_type,
        original_filename=payload.filename,
        original_size_bytes=payload.size_bytes,
        storage_bucket=storage_service.storage_service.bucket,
        state="uploaded",
    )
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to create media record",
        )

    if lesson_id:
        try:
            row = await models.add_lesson_media_entry_with_position_retry(
                lesson_id=lesson_id,
                kind="audio",
                storage_path=None,
                storage_bucket=storage_service.storage_service.bucket,
                media_id=None,
                media_asset_id=str(media_asset["id"]),
                duration_seconds=None,
                max_retries=10,
            )
        except Exception:
            await media_assets_repo.delete_media_asset(str(media_asset["id"]))
            raise

        if not row:
            await media_assets_repo.delete_media_asset(str(media_asset["id"]))
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Could not allocate lesson media position",
            )

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    logger.info(
        "Issued WAV upload URL user_id=%s purpose=%s size_bytes=%s path=%s media_id=%s",
        user_id,
        purpose,
        payload.size_bytes,
        upload.path,
        media_asset["id"],
    )
    return schemas.MediaUploadUrlResponse(
        media_id=media_asset["id"],
        upload_url=upload.url,
        object_path=upload.path,
        headers=dict(upload.headers),
        expires_at=expires_at,
    )


@router.post("/upload-url/refresh", response_model=schemas.MediaUploadUrlResponse)
async def refresh_upload_url(
    payload: schemas.MediaUploadUrlRefreshRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    media_asset = await media_assets_repo.get_media_asset(str(payload.media_id))
    if not media_asset:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")

    owner_id = media_asset.get("owner_id")
    if owner_id and str(owner_id) != user_id:
        course_id = media_asset.get("course_id")
        if not course_id or not await models.is_course_owner(user_id, str(course_id)):
            logger.warning(
                "Permission denied: media refresh requires owner user_id=%s media_id=%s course_id=%s",
                user_id,
                payload.media_id,
                course_id,
            )
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    media_type = (media_asset.get("media_type") or "").lower()
    if media_type != "audio":
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only WAV uploads are supported",
        )

    object_path = media_asset.get("original_object_path")
    if not object_path:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Media missing storage path",
        )

    content_type = _normalize_mime(media_asset.get("original_content_type") or "")
    if not content_type:
        content_type = "audio/wav"

    storage_bucket = media_asset.get("storage_bucket") or storage_service.storage_service.bucket
    storage_client = storage_service.get_storage_service(storage_bucket)

    try:
        upload = await storage_client.create_upload_url(
            object_path,
            content_type=content_type,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Upload URL refresh failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    logger.info(
        "Refreshed WAV upload URL user_id=%s media_id=%s path=%s",
        user_id,
        media_asset.get("id"),
        upload.path,
    )
    return schemas.MediaUploadUrlResponse(
        media_id=media_asset["id"],
        upload_url=upload.url,
        object_path=upload.path,
        headers=dict(upload.headers),
        expires_at=expires_at,
    )


@router.post("/cover-upload-url", response_model=schemas.CoverUploadUrlResponse)
async def request_cover_upload_url(
    payload: schemas.CoverUploadUrlRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    course_id = str(payload.course_id)
    await _authorize_course_upload(user_id, course_id)

    mime_type = _normalize_mime(payload.mime_type)
    if not mime_type:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="mime_type is required",
        )
    if mime_type not in _COVER_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported cover image type",
        )

    max_bytes = _cover_max_bytes()
    if payload.size_bytes > max_bytes:
        max_mb = max_bytes // (1024 * 1024)
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Cover image too large (max {max_mb} MB)",
        )

    object_path = _build_cover_source_object_path(course_id, payload.filename)
    try:
        upload = await storage_service.storage_service.create_upload_url(
            object_path,
            content_type=mime_type,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Cover upload URL issuance failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    media_asset = await media_assets_repo.create_media_asset(
        owner_id=user_id,
        course_id=course_id,
        lesson_id=None,
        media_type="image",
        purpose="course_cover",
        ingest_format=_cover_ingest_format(mime_type, payload.filename),
        original_object_path=upload.path,
        original_content_type=mime_type,
        original_filename=payload.filename,
        original_size_bytes=payload.size_bytes,
        storage_bucket=storage_service.storage_service.bucket,
        state="uploaded",
    )
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to create cover media record",
        )

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    logger.info(
        "Issued cover upload URL user_id=%s course_id=%s path=%s media_id=%s",
        user_id,
        course_id,
        upload.path,
        media_asset["id"],
    )
    return schemas.CoverUploadUrlResponse(
        media_id=media_asset["id"],
        upload_url=upload.url,
        object_path=upload.path,
        headers=dict(upload.headers),
        expires_at=expires_at,
    )


@router.post("/cover-from-media", response_model=schemas.CoverMediaResponse)
async def request_cover_from_media(
    payload: schemas.CoverFromLessonMediaRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    course_id = str(payload.course_id)
    await _authorize_course_upload(user_id, course_id)

    media = await models.get_media(str(payload.lesson_media_id))
    if not media:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")

    lesson_id = str(media.get("lesson_id")) if media.get("lesson_id") else None
    if not lesson_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Lesson media missing lesson association",
        )

    _, resolved_course_id = await models.lesson_course_ids(lesson_id)
    if not resolved_course_id or str(resolved_course_id) != course_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Media does not belong to course",
        )

    kind = (media.get("kind") or "").lower()
    content_type = _normalize_mime(media.get("content_type") or "")
    if kind != "image" and not content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only image media can be used as a cover",
        )

    storage_path = media.get("storage_path")
    if not storage_path:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Media missing storage path")
    storage_bucket = media.get("storage_bucket") or settings.media_source_bucket

    original_name = media.get("original_name")
    ingest_format = _cover_ingest_format(content_type, original_name or storage_path)
    media_asset = await media_assets_repo.create_media_asset(
        owner_id=user_id,
        course_id=course_id,
        lesson_id=None,
        media_type="image",
        purpose="course_cover",
        ingest_format=ingest_format,
        original_object_path=storage_path,
        original_content_type=content_type or None,
        original_filename=original_name,
        original_size_bytes=None,
        storage_bucket=storage_bucket,
        state="uploaded",
    )
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to create cover media record",
        )

    logger.info(
        "Queued cover from media user_id=%s course_id=%s media_id=%s source=%s",
        user_id,
        course_id,
        media_asset["id"],
        storage_path,
    )
    return schemas.CoverMediaResponse(
        media_id=media_asset["id"],
        state=media_asset["state"],
    )


@router.post("/cover-clear", response_model=schemas.CoverClearResponse)
async def clear_course_cover(
    payload: schemas.CoverClearRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    course_id = str(payload.course_id)
    await _authorize_course_upload(user_id, course_id)
    await courses_repo.clear_course_cover(course_id)
    await media_cleanup.delete_course_cover_assets_for_course(course_id=course_id)
    return schemas.CoverClearResponse(ok=True)


@router.get("/{media_id}", response_model=schemas.MediaStatusResponse)
async def media_status(
    media_id: UUID,
    current: TeacherUser,
):
    media = await media_assets_repo.get_media_asset(str(media_id))
    if not media:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")
    owner_id = media.get("owner_id")
    if owner_id and str(owner_id) != str(current["id"]):
        course_id = media.get("course_id")
        if not course_id or not await models.is_course_owner(str(current["id"]), str(course_id)):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    return schemas.MediaStatusResponse(
        media_id=media_id,
        state=media.get("state"),
        error_message=media.get("error_message"),
        ingest_format=media.get("ingest_format"),
        streaming_format=media.get("streaming_format"),
        duration_seconds=media.get("duration_seconds"),
        codec=media.get("codec"),
    )


@router.post("/playback-url", response_model=schemas.MediaPlaybackUrlResponse)
async def request_playback_url(
    payload: schemas.MediaPlaybackUrlRequest,
    current: CurrentUser,
):
    user_id = str(current["id"])
    media = await media_assets_repo.get_media_asset_access(str(payload.media_id))
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
            str(payload.media_id)
        )
        if not upload:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Media not found")
        teacher_id = upload.get("teacher_id")
        if not teacher_id:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Media missing owner",
            )
        await _authorize_home_player_upload_playback(
            user_id,
            str(teacher_id),
        )
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
        format="mp3",
    )
