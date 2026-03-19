from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, status
from fastapi import Request
from pydantic import BaseModel

from .. import models, schemas
from ..auth import CurrentUser
from ..config import settings
from ..permissions import TeacherUser
from ..repositories import courses as courses_repo
from ..repositories import media_assets as media_assets_repo
from ..repositories import storage_objects
from ..services import courses_service, lesson_playback_service, media_cleanup
from ..services import storage_service
from ..utils import media_paths
from ..utils.media_urls import absolutize_media_urls

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/media", tags=["media"])
debug_router = APIRouter(prefix="/debug", tags=["debug"])

_MIN_MEDIA_BYTES = 5 * 1024 * 1024 * 1024
_MP3_MIME_TYPES = {"audio/mpeg", "audio/mp3"}
_AUDIO_SOURCE_MIME_TYPES_BY_EXT = {
    "mp3": _MP3_MIME_TYPES,
    "wav": {"audio/wav", "audio/x-wav"},
    "m4a": {"audio/m4a", "audio/mp4"},
}
_AUDIO_SOURCE_MIME_TYPES = frozenset().union(*_AUDIO_SOURCE_MIME_TYPES_BY_EXT.values())
_COVER_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}
_AUDIO_SOURCE_SUPPORTED_DETAIL = "Only MP3, WAV, or M4A audio files are supported"


class LessonPlaybackRequest(BaseModel):
    lesson_media_id: UUID


class LessonPlaybackResponse(BaseModel):
    playback_url: str
    url: str


class RuntimePlaybackRequest(BaseModel):
    runtime_media_id: UUID


class RuntimePlaybackResponse(BaseModel):
    runtime_media_id: UUID
    playback_url: str
    kind: str | None = None
    content_type: str | None = None
    duration_seconds: int | None = None


class DebugMediaResponse(BaseModel):
    lesson_media_id: UUID
    storage_path: str
    signed_url: str


def _normalized_preview_string(value: object | None) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _preview_file_name(item: dict[str, object]) -> str | None:
    original_name = _normalized_preview_string(item.get("original_name"))
    if original_name:
        return original_name
    storage_path = _normalized_preview_string(item.get("storage_path"))
    if not storage_path:
        return None
    file_name = Path(storage_path).name.strip()
    return file_name or None


def _preview_thumbnail_url(item: dict[str, object]) -> str | None:
    kind = _normalized_preview_string(item.get("kind")) or ""
    if kind != "image":
        return _normalized_preview_string(
            item.get("thumbnail_url") or item.get("thumbnailUrl")
        )
    for candidate in (
        item.get("thumbnail_url"),
        item.get("thumbnailUrl"),
        item.get("preferredUrl"),
        item.get("preferred_url"),
        item.get("download_url"),
        item.get("signed_url"),
        item.get("playback_url"),
    ):
        normalized = _normalized_preview_string(candidate)
        if normalized:
            return normalized
    return None


async def _canonical_lesson_media_row(
    *,
    lesson_id: str,
    lesson_media_id: str,
    base_url: str,
) -> dict[str, object] | None:
    lesson_media_items = await courses_service.list_lesson_media(
        lesson_id,
        mode="editor_preview",
    )
    for item in lesson_media_items:
        if str(item.get("id") or "").strip() != lesson_media_id:
            continue
        canonical = dict(item)
        absolutize_media_urls(canonical, base_url=base_url)
        return canonical
    return None


def _normalize_mime(value: str) -> str:
    return (value or "").strip().lower()


def _audio_ingest_format(filename: str, mime_type: str) -> str:
    ext = Path(filename).suffix.lower().lstrip(".")
    if ext not in _AUDIO_SOURCE_MIME_TYPES_BY_EXT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_AUDIO_SOURCE_SUPPORTED_DETAIL,
        )
    if mime_type not in _AUDIO_SOURCE_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_AUDIO_SOURCE_SUPPORTED_DETAIL,
        )
    if mime_type not in _AUDIO_SOURCE_MIME_TYPES_BY_EXT[ext]:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_AUDIO_SOURCE_SUPPORTED_DETAIL,
        )
    return ext


def _default_audio_content_type(
    *,
    ingest_format: str | None,
    original_filename: str | None,
    original_object_path: str | None,
) -> str:
    candidates = [
        (ingest_format or "").strip().lower(),
        Path(original_filename or "").suffix.lower().lstrip("."),
        Path(original_object_path or "").suffix.lower().lstrip("."),
    ]
    for candidate in candidates:
        if candidate == "mp3":
            return "audio/mpeg"
        if candidate == "m4a":
            return "audio/m4a"
        if candidate == "wav":
            return "audio/wav"
    return "audio/wav"


def _build_cover_source_object_path(course_id: str, filename: str) -> str:
    safe_name = Path(filename).name.strip()
    if not safe_name:
        safe_name = "cover"
    token = uuid4().hex
    path = (
        Path("media")
        / "source"
        / "cover"
        / "courses"
        / course_id
        / f"{token}_{safe_name}"
    )
    return path.as_posix()


def _lesson_audio_source_prefix(course_id: str, lesson_id: str) -> str:
    return (
        Path("media")
        / "source"
        / "audio"
        / "courses"
        / course_id
        / "lessons"
        / lesson_id
    ).as_posix() + "/"


def _is_canonical_lesson_audio_source_path(
    object_path: str,
    *,
    course_id: str,
    lesson_id: str,
) -> bool:
    normalized = str(object_path or "").strip().lstrip("/")
    if not normalized:
        return False
    return normalized.startswith(_lesson_audio_source_prefix(course_id, lesson_id))


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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Lesson not found"
        )

    _, resolved_course_id = await models.lesson_course_ids(lesson_id)
    if not resolved_course_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Lesson missing course"
        )

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
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Not course owner"
        )

    return resolved_course_id


async def _authorize_course_upload(user_id: str, course_id: str) -> None:
    course = await models.get_course(course_id=course_id)
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Course not found"
        )
    if not await models.is_course_owner(user_id, course_id):
        logger.warning(
            "Permission denied: course owner required user_id=%s course_id=%s",
            user_id,
            course_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Not course owner"
        )


async def _storage_object_exists(
    *,
    storage_bucket: str,
    storage_path: str,
) -> bool:
    normalized_path = str(storage_path or "").strip().lstrip("/")
    if not normalized_path:
        return False

    existence, storage_table_available = await storage_objects.fetch_storage_object_existence(
        [(storage_bucket, normalized_path)]
    )
    if storage_table_available and existence.get((storage_bucket, normalized_path)):
        return True

    try:
        await storage_service.get_storage_service(storage_bucket).get_presigned_url(
            normalized_path,
            ttl=60,
            download=False,
        )
    except storage_service.StorageObjectNotFoundError:
        return False
    return True


async def _wait_for_storage_object(
    *,
    storage_bucket: str,
    storage_path: str,
    attempts: int = 4,
    delay_seconds: float = 0.35,
) -> bool:
    total_attempts = max(1, int(attempts))
    for index in range(total_attempts):
        if await _storage_object_exists(
            storage_bucket=storage_bucket,
            storage_path=storage_path,
        ):
            return True
        if index < total_attempts - 1:
            await asyncio.sleep(delay_seconds)
    return False


async def _authorize_audio_media_asset(
    *,
    user_id: str,
    media_asset_id: str,
) -> dict[str, object]:
    media_asset = await media_assets_repo.get_media_asset(media_asset_id)
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media not found",
        )

    owner_id = media_asset.get("owner_id")
    if owner_id and str(owner_id) != user_id:
        course_id = media_asset.get("course_id")
        if not course_id or not await models.is_course_owner(user_id, str(course_id)):
            logger.warning(
                "Permission denied: media finalize requires owner user_id=%s media_id=%s course_id=%s",
                user_id,
                media_asset_id,
                course_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied",
            )

    media_type = (media_asset.get("media_type") or "").lower()
    if media_type != "audio":
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_AUDIO_SOURCE_SUPPORTED_DETAIL,
        )
    return media_asset


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
    ingest_format = _audio_ingest_format(payload.filename, mime_type)

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
    object_path: str | None = None
    if purpose == "home_player_audio":
        if payload.course_id is not None or payload.lesson_id is not None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="course_id/lesson_id not allowed for home player uploads",
            )
        object_path = media_paths.build_home_player_audio_source_object_path(
            user_id, payload.filename
        )
    else:
        if payload.lesson_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="lesson_id is required for lesson audio uploads",
            )
        lesson_id = str(payload.lesson_id)
        course_id = await _authorize_lesson_upload(
            user_id=user_id,
            lesson_id=lesson_id,
            course_id=payload.course_id,
        )
        course_id = str(course_id)
        object_path = media_paths.build_lesson_audio_source_object_path(
            course_id, lesson_id, payload.filename
        )
    try:
        object_path = media_paths.validate_new_upload_object_path(object_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
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

    media_asset_purpose = (
        "home_player_audio" if purpose == "home_player_audio" else "lesson_audio"
    )
    initial_state = "pending_upload" if purpose == "lesson_audio" else "uploaded"
    media_asset_payload = {
        "owner_id": user_id,
        "course_id": course_id,
        "lesson_id": lesson_id,
        "media_type": "audio",
        "purpose": media_asset_purpose,
        "ingest_format": ingest_format,
        "original_object_path": upload.path,
        "original_content_type": mime_type,
        "original_filename": payload.filename,
        "original_size_bytes": payload.size_bytes,
        "storage_bucket": storage_service.storage_service.bucket,
        "state": initial_state,
    }
    logger.info(
        "Creating audio media_asset lesson_id=%s course_id=%s purpose=%s media_type=%s content_type=%s",
        media_asset_payload["lesson_id"],
        media_asset_payload["course_id"],
        media_asset_payload["purpose"],
        media_asset_payload["media_type"],
        media_asset_payload["original_content_type"],
    )
    try:
        media_asset = await media_assets_repo.create_media_asset(**media_asset_payload)
    except Exception:
        logger.exception(
            "Audio media_asset insert failed lesson_id=%s course_id=%s purpose=%s media_type=%s content_type=%s",
            media_asset_payload["lesson_id"],
            media_asset_payload["course_id"],
            media_asset_payload["purpose"],
            media_asset_payload["media_type"],
            media_asset_payload["original_content_type"],
        )
        raise
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to create media record",
        )

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    logger.info(
        "Issued audio upload URL user_id=%s purpose=%s size_bytes=%s path=%s media_id=%s format=%s",
        user_id,
        purpose,
        payload.size_bytes,
        upload.path,
        media_asset["id"],
        ingest_format,
    )
    return schemas.MediaUploadUrlResponse(
        media_asset_id=media_asset["id"],
        media_id=media_asset["id"],
        upload_url=upload.url,
        storage_path=upload.path,
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
    media_asset = await media_assets_repo.get_media_asset(str(payload.media_asset_id))
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Media not found"
        )

    owner_id = media_asset.get("owner_id")
    if owner_id and str(owner_id) != user_id:
        course_id = media_asset.get("course_id")
        if not course_id or not await models.is_course_owner(user_id, str(course_id)):
            logger.warning(
                "Permission denied: media refresh requires owner user_id=%s media_id=%s course_id=%s",
                user_id,
                payload.media_asset_id,
                course_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="Access denied"
            )

    media_type = (media_asset.get("media_type") or "").lower()
    if media_type != "audio":
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_AUDIO_SOURCE_SUPPORTED_DETAIL,
        )

    object_path = media_asset.get("original_object_path")
    if not object_path:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Media missing storage path",
        )

    purpose = (media_asset.get("purpose") or "").strip().lower()
    course_id = str(media_asset.get("course_id") or "").strip()
    lesson_id = str(media_asset.get("lesson_id") or "").strip()
    if purpose == "lesson_audio":
        if not course_id or not lesson_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson audio is missing course or lesson context",
            )
        if not _is_canonical_lesson_audio_source_path(
            object_path,
            course_id=course_id,
            lesson_id=lesson_id,
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson audio must use the canonical pipeline source path",
            )
    try:
        object_path = media_paths.validate_new_upload_object_path(object_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc

    content_type = _normalize_mime(media_asset.get("original_content_type") or "")
    if not content_type:
        content_type = _default_audio_content_type(
            ingest_format=media_asset.get("ingest_format"),
            original_filename=media_asset.get("original_filename"),
            original_object_path=object_path,
        )

    storage_bucket = (
        media_asset.get("storage_bucket") or storage_service.storage_service.bucket
    )
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
        "Refreshed audio upload URL user_id=%s media_id=%s path=%s",
        user_id,
        media_asset.get("id"),
        upload.path,
    )
    return schemas.MediaUploadUrlResponse(
        media_asset_id=media_asset["id"],
        media_id=media_asset["id"],
        upload_url=upload.url,
        storage_path=upload.path,
        object_path=upload.path,
        headers=dict(upload.headers),
        expires_at=expires_at,
    )


@router.post("/upload-url/complete", response_model=schemas.MediaStatusResponse)
async def complete_upload_url(
    request: Request,
    payload: schemas.MediaUploadCompleteRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    media_asset_id = str(payload.media_asset_id)
    media_asset = await _authorize_audio_media_asset(
        user_id=user_id,
        media_asset_id=media_asset_id,
    )

    purpose = (media_asset.get("purpose") or "").strip().lower()
    if purpose != "lesson_audio":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only lesson audio uploads can be completed here",
        )

    course_id = str(media_asset.get("course_id") or "").strip()
    lesson_id = str(media_asset.get("lesson_id") or "").strip()
    object_path = str(media_asset.get("original_object_path") or "").strip()
    storage_bucket = str(
        media_asset.get("storage_bucket") or storage_service.storage_service.bucket
    ).strip()
    if not course_id or not lesson_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Lesson audio is missing course or lesson context",
        )
    if not object_path:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Media missing storage path",
        )
    if not _is_canonical_lesson_audio_source_path(
        object_path,
        course_id=course_id,
        lesson_id=lesson_id,
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Lesson audio must use the canonical pipeline source path",
        )

    try:
        source_exists = await _wait_for_storage_object(
            storage_bucket=storage_bucket,
            storage_path=object_path,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Audio upload completion check failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    if not source_exists:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Uploaded file is missing from storage",
        )

    lesson_media = await models.get_lesson_media_by_media_asset_id(media_asset_id)
    if lesson_media is None:
        try:
            lesson_media = await models.add_lesson_media_entry_with_position_retry(
                lesson_id=lesson_id,
                kind="audio",
                storage_path=None,
                storage_bucket=storage_bucket,
                media_id=None,
                media_asset_id=media_asset_id,
                duration_seconds=None,
                max_retries=10,
            )
        except Exception:
            logger.exception(
                "Lesson audio attach failed media_id=%s lesson_id=%s",
                media_asset_id,
                lesson_id,
            )
            raise
        if lesson_media is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Could not allocate lesson media position",
            )

    current_state = str(media_asset.get("state") or "").strip().lower()
    if current_state in {"pending_upload", "failed"}:
        updated = await media_assets_repo.mark_media_asset_uploaded(media_id=media_asset_id)
        if not updated:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Media not found",
            )
        media_asset = await media_assets_repo.get_media_asset(media_asset_id) or media_asset

    canonical_lesson_media = await _canonical_lesson_media_row(
        lesson_id=lesson_id,
        lesson_media_id=str(lesson_media["id"]),
        base_url=str(request.base_url),
    )
    return schemas.MediaStatusResponse(
        media_id=UUID(media_asset_id),
        state=str(media_asset.get("state") or "uploaded"),
        error_message=media_asset.get("error_message"),
        ingest_format=media_asset.get("ingest_format"),
        streaming_format=media_asset.get("streaming_format"),
        duration_seconds=media_asset.get("duration_seconds"),
        codec=media_asset.get("codec"),
        lesson_media_id=UUID(str(lesson_media["id"])),
        lesson_media=canonical_lesson_media,
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
        object_path = media_paths.validate_new_upload_object_path(object_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Media not found"
        )

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
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Media missing storage path"
        )
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Media not found"
        )
    owner_id = media.get("owner_id")
    if owner_id and str(owner_id) != str(current["id"]):
        course_id = media.get("course_id")
        if not course_id or not await models.is_course_owner(
            str(current["id"]), str(course_id)
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="Access denied"
            )
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
    resolved = await lesson_playback_service.resolve_pipeline_playback(
        media_asset_id=str(payload.media_id),
        user_id=user_id,
    )
    logger.info("Issued media playback URL user_id=%s", user_id)
    return schemas.MediaPlaybackUrlResponse(
        playback_url=resolved["url"],
        expires_at=resolved["expires_at"],
        format=resolved["format"],
    )


@router.post("/previews", response_model=schemas.MediaPreviewBatchResponse)
async def request_media_previews(
    request: Request,
    payload: schemas.MediaPreviewBatchRequest,
    current: TeacherUser,
):
    requested_ids: list[str] = []
    seen_ids: set[str] = set()
    for media_id in payload.ids:
        media_id_str = str(media_id)
        if media_id_str in seen_ids:
            continue
        seen_ids.add(media_id_str)
        requested_ids.append(media_id_str)

    if not requested_ids:
        return schemas.MediaPreviewBatchResponse(items={})

    rows = await courses_repo.list_lesson_media_by_ids(requested_ids)
    if not rows:
        return schemas.MediaPreviewBatchResponse(items={})

    requested_by_lesson: dict[str, set[str]] = {}
    for row in rows:
        lesson_id = _normalized_preview_string(row.get("lesson_id"))
        lesson_media_id = _normalized_preview_string(row.get("id"))
        if not lesson_id or not lesson_media_id:
            continue
        requested_by_lesson.setdefault(lesson_id, set()).add(lesson_media_id)

    for lesson_id in requested_by_lesson:
        _, course_id = await courses_service.lesson_course_ids(lesson_id)
        if not course_id or not await models.is_course_owner(current["id"], course_id):
            logger.warning(
                "Permission denied: course owner required user_id=%s lesson_id=%s",
                str(current["id"]),
                lesson_id,
            )
            raise HTTPException(status_code=403, detail="Not course owner")

    preview_items: dict[str, schemas.MediaPreviewItem] = {}
    for lesson_id, lesson_media_ids in requested_by_lesson.items():
        lesson_media = await courses_service.list_lesson_media(
            lesson_id,
            mode="editor_preview",
        )
        by_id = {str(item.get("id")): item for item in lesson_media}
        for lesson_media_id in lesson_media_ids:
            item = by_id.get(lesson_media_id)
            if item is None:
                continue
            item = dict(item)
            absolutize_media_urls(item, base_url=str(request.base_url))
            duration_seconds = item.get("duration_seconds")
            preview_items[lesson_media_id] = schemas.MediaPreviewItem(
                media_type=_normalized_preview_string(item.get("kind")) or "",
                thumbnail_url=_preview_thumbnail_url(item),
                poster_frame=_normalized_preview_string(
                    item.get("poster_frame") or item.get("posterFrame")
                ),
                duration_seconds=(
                    int(duration_seconds)
                    if isinstance(duration_seconds, (int, float))
                    else None
                ),
                file_name=_preview_file_name(item),
                preview_blocked=item.get("preview_blocked") is True,
            )

    return schemas.MediaPreviewBatchResponse(items=preview_items)


@router.post("/playback", response_model=RuntimePlaybackResponse)
async def request_runtime_playback(
    payload: RuntimePlaybackRequest,
    current: CurrentUser,
):
    playback = await lesson_playback_service.resolve_runtime_media_playback(
        runtime_media_id=str(payload.runtime_media_id),
        user_id=str(current["id"]),
    )
    return RuntimePlaybackResponse(
        runtime_media_id=UUID(str(playback["runtime_media_id"])),
        playback_url=playback["playback_url"],
        kind=playback.get("kind"),
        content_type=playback.get("content_type"),
        duration_seconds=playback.get("duration_seconds"),
    )


@router.post("/lesson-playback", response_model=LessonPlaybackResponse)
async def request_lesson_playback(
    payload: LessonPlaybackRequest,
    current: CurrentUser,
):
    lesson_media_id = str(payload.lesson_media_id)
    playback = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id=lesson_media_id,
        user_id=str(current["id"]),
    )
    return LessonPlaybackResponse(
        playback_url=playback["url"],
        url=playback["url"],
    )


@debug_router.get("/media/{lesson_media_id}", response_model=DebugMediaResponse)
async def debug_media(
    lesson_media_id: UUID,
    current: CurrentUser,
):
    lesson_media_id_str = str(lesson_media_id)
    row = await models.get_media(lesson_media_id_str)
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson media not found",
        )

    storage_path = row.get("storage_path")
    signed_url: str | None = None

    media_asset_id = row.get("media_asset_id")
    if media_asset_id:
        playback = await lesson_playback_service.resolve_lesson_media_playback(
            lesson_media_id=lesson_media_id_str,
            user_id=str(current["id"]),
        )
        signed_url = playback["url"]
        if not storage_path:
            media_asset = await media_assets_repo.get_media_asset_access(
                str(media_asset_id)
            )
            if media_asset:
                storage_path = media_asset.get("streaming_object_path")
    elif storage_path:
        playback = await lesson_playback_service.resolve_object_media_playback(
            lesson_media_id=lesson_media_id_str,
            user_id=str(current["id"]),
        )
        signed_url = playback["url"]

    if not storage_path or not signed_url:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson media has no playable source",
        )

    return DebugMediaResponse(
        lesson_media_id=lesson_media_id,
        storage_path=str(storage_path),
        signed_url=signed_url,
    )
