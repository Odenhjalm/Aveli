from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, status
from fastapi import Request
from pydantic import BaseModel

from .. import models, schemas
from ..auth import CurrentUser
from ..config import settings
from ..db import get_conn
from ..media_control_plane.services.media_resolver_service import (
    media_resolver_service as canonical_media_resolver,
)
from ..permissions import TeacherUser
from ..repositories import courses as courses_repo
from ..repositories import home_audio_sources as home_audio_sources_repo
from ..repositories import media_assets as media_assets_repo
from ..repositories import storage_objects
from ..services import courses_service, lesson_playback_service
from ..services import storage_service
from ..utils import media_paths
from ..utils.media_urls import absolutize_media_urls

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/media", tags=["media"])
debug_router = APIRouter(prefix="/debug", tags=["debug"])

# UWD-001 non-canonical write isolation: this router is not mounted by app.main and
# its write routes are legacy drift, not canonical lesson-media pipeline authority.

_MIN_MEDIA_BYTES = 5 * 1024 * 1024 * 1024
_MP3_MIME_TYPES = {"audio/mpeg", "audio/mp3"}
_AUDIO_SOURCE_MIME_TYPES_BY_EXT = {
    "mp3": _MP3_MIME_TYPES,
    "wav": {"audio/wav", "audio/x-wav"},
    "m4a": {"audio/m4a", "audio/mp4"},
}
_AUDIO_SOURCE_MIME_TYPES = frozenset().union(*_AUDIO_SOURCE_MIME_TYPES_BY_EXT.values())
_COVER_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}
_LESSON_IMAGE_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/svg+xml",
}
_LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".webp": "image/webp",
}
_LESSON_IMAGE_DEFAULT_EXTENSION_BY_CONTENT_TYPE = {
    "image/jpeg": "jpeg",
    "image/png": "png",
    "image/svg+xml": "svg",
    "image/webp": "webp",
}
_AUDIO_SOURCE_SUPPORTED_DETAIL = "Only MP3, WAV, or M4A audio files are supported"
_LESSON_IMAGE_SUPPORTED_DETAIL = (
    "Only PNG, JPEG, WEBP, or SVG lesson images are supported"
)
_LESSON_VIDEO_SUPPORTED_DETAIL = (
    "Only lesson videos with video/* MIME types are supported"
)
_LESSON_DOCUMENT_MIME_TYPES = {"application/pdf"}
_LESSON_DOCUMENT_SUPPORTED_DETAIL = "Only PDF lesson documents are supported"


@dataclass(slots=True)
class _CanonicalMediaAssetScope:
    media_type: str
    purpose: str
    object_path: str
    storage_bucket: str
    course_id: str | None = None
    lesson_id: str | None = None
    owner_user_id: str | None = None


def _normalized_preview_string(value: object | None) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _canonical_media_asset_scope(
    media_asset: dict[str, object],
) -> _CanonicalMediaAssetScope:
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    object_path = str(media_asset.get("original_object_path") or "").strip().lstrip("/")
    if not object_path:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Media missing storage path",
        )

    parts = Path(object_path).parts
    if media_type == "audio":
        if purpose == "home_player_audio":
            if len(parts) < 6 or parts[:4] != (
                "media",
                "source",
                "audio",
                "home-player",
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Home player audio must use the canonical pipeline source path",
                )
            owner_user_id = parts[4].strip()
            if not owner_user_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Home player audio is missing owner context",
                )
            return _CanonicalMediaAssetScope(
                media_type=media_type,
                purpose=purpose,
                object_path=object_path,
                storage_bucket=storage_service.storage_service.bucket,
                owner_user_id=owner_user_id,
            )
        if purpose == "lesson_audio":
            if (
                len(parts) < 8
                or parts[:4] != ("media", "source", "audio", "courses")
                or parts[5] != "lessons"
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Lesson audio must use the canonical pipeline source path",
                )
            course_id = parts[4].strip()
            lesson_id = parts[6].strip()
            if not course_id or not lesson_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Lesson audio is missing course or lesson context",
                )
            return _CanonicalMediaAssetScope(
                media_type=media_type,
                purpose=purpose,
                object_path=object_path,
                storage_bucket=storage_service.storage_service.bucket,
                course_id=course_id,
                lesson_id=lesson_id,
            )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Unsupported media purpose",
        )

    if media_type == "image":
        if purpose == "lesson_media":
            if len(parts) < 4 or parts[0] != "lessons" or parts[2] != "images":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Lesson image must use the canonical public image path",
                )
            lesson_id = parts[1].strip()
            if not lesson_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Lesson image is missing lesson context",
                )
            return _CanonicalMediaAssetScope(
                media_type=media_type,
                purpose=purpose,
                object_path=object_path,
                storage_bucket=settings.media_public_bucket,
                lesson_id=lesson_id,
            )
        if purpose == "course_cover":
            if len(parts) < 6 or parts[:4] != (
                "media",
                "source",
                "cover",
                "courses",
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Course cover must use the canonical source media path",
                )
            course_id = parts[4].strip()
            if not course_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Course cover is missing course context",
                )
            return _CanonicalMediaAssetScope(
                media_type=media_type,
                purpose=purpose,
                object_path=object_path,
                storage_bucket=storage_service.storage_service.bucket,
                course_id=course_id,
            )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Unsupported media purpose",
        )

    if media_type in {"video", "document"}:
        if purpose != "lesson_media":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Unsupported media purpose",
            )
        expected_folder = "documents" if media_type == "document" else media_type
        if (
            len(parts) < 6
            or parts[0] != "courses"
            or parts[2] != "lessons"
            or parts[4] != expected_folder
        ):
            detail = {
                "video": "Lesson video must use the canonical private lesson path",
                "document": "Lesson document must use the canonical private lesson path",
            }[media_type]
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=detail,
            )
        course_id = parts[1].strip()
        lesson_id = parts[3].strip()
        if not course_id or not lesson_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson passthrough media is missing course or lesson context",
            )
        return _CanonicalMediaAssetScope(
            media_type=media_type,
            purpose=purpose,
            object_path=object_path,
            storage_bucket=storage_service.storage_service.bucket,
            course_id=course_id,
            lesson_id=lesson_id,
        )

    raise HTTPException(
        status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
        detail="Unsupported media type",
    )


async def _ensure_scope_course_id(
    scope: _CanonicalMediaAssetScope,
    *,
    detail: str,
) -> str:
    if scope.course_id:
        return scope.course_id
    if not scope.lesson_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=detail,
        )
    _, resolved_course_id = await models.lesson_course_ids(scope.lesson_id)
    if not resolved_course_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=detail,
        )
    scope.course_id = str(resolved_course_id)
    return scope.course_id


def _default_lesson_image_content_type(
    *,
    ingest_format: str | None,
    object_path: str | None,
) -> str:
    candidates = [
        f".{str(ingest_format or '').strip().lower().lstrip('.')}",
        Path(object_path or "").suffix.lower(),
    ]
    for candidate in candidates:
        if not candidate or candidate == ".":
            continue
        mime_type = _LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION.get(candidate)
        if mime_type:
            return mime_type
    return "image/jpeg"


def _canonical_media_asset_content_type(media_asset: dict[str, object]) -> str:
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    object_path = str(media_asset.get("original_object_path") or "").strip()
    ingest_format = str(media_asset.get("ingest_format") or "").strip().lower()
    if media_type == "audio":
        return _default_audio_content_type(
            ingest_format=ingest_format,
            original_filename=None,
            original_object_path=object_path,
        )
    if media_type == "image":
        if purpose == "course_cover":
            return _default_cover_content_type(object_path)
        return _default_lesson_image_content_type(
            ingest_format=ingest_format,
            object_path=object_path,
        )
    if media_type == "video":
        subtype = ingest_format or Path(object_path).suffix.lower().lstrip(".") or "mp4"
        return f"video/{subtype}"
    if media_type == "document":
        return "application/pdf"
    return ""


def _preview_file_name(item: dict[str, object]) -> str | None:
    explicit_file_name = _normalized_preview_string(
        item.get("file_name") or item.get("fileName")
    )
    if explicit_file_name:
        return explicit_file_name
    original_name = _normalized_preview_string(item.get("original_name"))
    if original_name:
        return original_name
    return None


async def _resolve_preview_url(
    *,
    lesson_media_id: str,
    kind: str,
    user_id: str,
) -> tuple[str | None, str | None]:
    if kind not in {"image", "video", "audio"}:
        return None, "unsupported_media_type"
    try:
        resolved = await lesson_playback_service.resolve_lesson_media_playback(
            lesson_media_id=lesson_media_id,
            user_id=user_id,
        )
    except HTTPException as exc:
        logger.warning(
            "LESSON_MEDIA_PREVIEW_UNRESOLVED lesson_media_id=%s kind=%s status_code=%s",
            lesson_media_id,
            kind,
            exc.status_code,
        )
        return None, "unresolvable"

    resolved_url = _normalized_preview_string(resolved.get("resolved_url"))
    if resolved_url is None:
        logger.warning(
            "LESSON_MEDIA_PREVIEW_UNRESOLVED lesson_media_id=%s kind=%s status_code=200",
            lesson_media_id,
            kind,
        )
        return None, "unresolvable"

    logger.info(
        "LESSON_MEDIA_PREVIEW_BACKEND_RESOLUTION lesson_media_id=%s kind=%s",
        lesson_media_id,
        kind,
    )
    return resolved_url, None


def _preview_duration_seconds(item: dict[str, object]) -> int | None:
    duration_seconds = item.get("duration_seconds")
    if isinstance(duration_seconds, (int, float)):
        return int(duration_seconds)
    return None


def _preview_failure_item(
    *,
    media_type: str = "",
    duration_seconds: int | None = None,
    file_name: str | None = None,
    failure_reason: str,
) -> schemas.MediaPreviewItem:
    return schemas.MediaPreviewItem(
        media_type=media_type,
        authoritative_editor_ready=False,
        resolved_preview_url=None,
        duration_seconds=duration_seconds,
        file_name=file_name,
        failure_reason=failure_reason,
    )


async def _build_preview_item(
    *,
    lesson_media_id: str,
    item: dict[str, object],
    user_id: str,
) -> schemas.MediaPreviewItem:
    kind = (_normalized_preview_string(item.get("kind")) or "").lower()
    duration_seconds = _preview_duration_seconds(item)
    file_name = _preview_file_name(item)

    resolved_preview_url, failure_reason = await _resolve_preview_url(
        lesson_media_id=lesson_media_id,
        kind=kind,
        user_id=user_id,
    )
    authoritative_editor_ready = failure_reason is None and (
        kind not in {"image", "video"} or resolved_preview_url is not None
    )

    return schemas.MediaPreviewItem(
        media_type=kind,
        authoritative_editor_ready=authoritative_editor_ready,
        resolved_preview_url=(
            resolved_preview_url if kind in {"image", "video"} else None
        ),
        duration_seconds=duration_seconds,
        file_name=file_name,
        failure_reason=failure_reason,
    )


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
        canonical.pop("storage_path", None)
        canonical.pop("storage_bucket", None)
        canonical.pop("media_id", None)
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


def _lesson_image_ingest_format(filename: str, mime_type: str) -> str:
    suffix = Path(filename).suffix.lower()
    if suffix not in _LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_LESSON_IMAGE_SUPPORTED_DETAIL,
        )
    if mime_type not in _LESSON_IMAGE_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_LESSON_IMAGE_SUPPORTED_DETAIL,
        )
    expected_mime_type = _LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION[suffix]
    if mime_type != expected_mime_type:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_LESSON_IMAGE_SUPPORTED_DETAIL,
        )
    return _LESSON_IMAGE_DEFAULT_EXTENSION_BY_CONTENT_TYPE[mime_type]


def _lesson_video_ingest_format(filename: str, mime_type: str) -> str:
    if not mime_type.startswith("video/"):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_LESSON_VIDEO_SUPPORTED_DETAIL,
        )
    suffix = Path(filename).suffix.lower().lstrip(".")
    if suffix:
        return suffix
    subtype = mime_type.split("/", 1)[1].split(";", 1)[0].strip().lower()
    return subtype or "video"


def _lesson_document_ingest_format(filename: str, mime_type: str) -> str:
    if mime_type not in _LESSON_DOCUMENT_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_LESSON_DOCUMENT_SUPPORTED_DETAIL,
        )
    _ = filename
    return "pdf"


def _lesson_passthrough_ingest_format(
    *,
    media_type: str,
    filename: str,
    mime_type: str,
) -> str:
    if media_type == "image":
        return _lesson_image_ingest_format(filename, mime_type)
    if media_type == "video":
        return _lesson_video_ingest_format(filename, mime_type)
    if media_type == "document":
        return _lesson_document_ingest_format(filename, mime_type)
    raise HTTPException(
        status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
        detail="Unsupported media type",
    )


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


def _cover_source_prefix(course_id: str) -> str:
    return (Path("media") / "source" / "cover" / "courses" / course_id).as_posix() + "/"


def _is_canonical_cover_source_path(
    object_path: str,
    *,
    course_id: str,
) -> bool:
    normalized = str(object_path or "").strip().lstrip("/")
    if not normalized:
        return False
    return normalized.startswith(_cover_source_prefix(course_id))


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


def _is_canonical_lesson_image_object_path(
    object_path: str,
    *,
    lesson_id: str,
) -> bool:
    normalized = str(object_path or "").strip().lstrip("/")
    if not normalized:
        return False
    prefix = (Path("lessons") / lesson_id / "images").as_posix() + "/"
    return normalized.startswith(prefix)


def _lesson_passthrough_content_type_supported(
    media_type: str, content_type: str
) -> bool:
    if media_type == "image":
        return content_type in _LESSON_IMAGE_MIME_TYPES
    if media_type == "video":
        return content_type.startswith("video/")
    if media_type == "document":
        return content_type in _LESSON_DOCUMENT_MIME_TYPES
    return False


def _lesson_passthrough_supported_detail(media_type: str) -> str:
    if media_type == "image":
        return _LESSON_IMAGE_SUPPORTED_DETAIL
    if media_type == "video":
        return _LESSON_VIDEO_SUPPORTED_DETAIL
    if media_type == "document":
        return _LESSON_DOCUMENT_SUPPORTED_DETAIL
    return "Unsupported media type"


def _lesson_passthrough_prefix(
    *,
    course_id: str,
    lesson_id: str,
    media_type: str,
) -> str:
    normalized_media_type = str(media_type or "").strip().lower()
    if normalized_media_type == "image":
        return (Path("lessons") / lesson_id / "images").as_posix() + "/"
    folder = (
        "documents"
        if normalized_media_type == "document"
        else (normalized_media_type or "media")
    )
    return (
        Path("courses") / course_id / "lessons" / lesson_id / folder
    ).as_posix() + "/"


def _is_canonical_lesson_passthrough_object_path(
    object_path: str,
    *,
    course_id: str,
    lesson_id: str,
    media_type: str,
) -> bool:
    normalized = str(object_path or "").strip().lstrip("/")
    if not normalized:
        return False
    if media_type == "image":
        return _is_canonical_lesson_image_object_path(
            object_path,
            lesson_id=lesson_id,
        )
    return normalized.startswith(
        _lesson_passthrough_prefix(
            course_id=course_id,
            lesson_id=lesson_id,
            media_type=media_type,
        )
    )


def _upload_max_bytes(media_type: str) -> int:
    if media_type == "audio":
        configured = settings.media_upload_max_audio_bytes
        minimum = _MIN_MEDIA_BYTES
    elif media_type == "image":
        configured = settings.media_upload_max_image_bytes
        minimum = 1
    else:
        configured = settings.media_upload_max_video_bytes
        minimum = _MIN_MEDIA_BYTES
    return max(int(configured), minimum)


def _default_cover_content_type(filename: str | None) -> str:
    suffix = Path(filename or "").suffix.lower()
    return _LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION.get(suffix, "image/jpeg")


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

    (
        existence,
        storage_table_available,
    ) = await storage_objects.fetch_storage_object_existence(
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


async def _authorize_media_asset(
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

    scope = _canonical_media_asset_scope(media_asset)
    if scope.owner_user_id:
        if scope.owner_user_id != user_id:
            logger.warning(
                "Permission denied: media finalize requires owner user_id=%s media_id=%s owner_user_id=%s",
                user_id,
                media_asset_id,
                scope.owner_user_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied",
            )
        return media_asset

    course_id = await _ensure_scope_course_id(
        scope,
        detail="Media asset is missing course context",
    )
    if not await models.is_course_owner(user_id, course_id):
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

    return media_asset


async def _finalize_media_asset_upload(
    media_asset: dict[str, object],
) -> dict[str, object]:
    scope = _canonical_media_asset_scope(media_asset)
    media_asset_id = str(media_asset.get("id") or "").strip()
    media_type = scope.media_type
    purpose = scope.purpose
    course_id = scope.course_id or ""
    lesson_id = scope.lesson_id or ""
    object_path = scope.object_path
    storage_bucket = scope.storage_bucket

    if media_type == "audio":
        if purpose not in {"lesson_audio", "home_player_audio"}:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Unsupported media purpose",
            )
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
    elif media_type == "image":
        if purpose == "lesson_media":
            if storage_bucket != settings.media_public_bucket:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Lesson image must use the public media bucket",
                )
            if not lesson_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Lesson image is missing lesson context",
                )
            if not _is_canonical_lesson_image_object_path(
                object_path,
                lesson_id=lesson_id,
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Lesson image must use the canonical public image path",
                )
        elif purpose == "course_cover":
            if not course_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Course cover is missing course context",
                )
            if storage_bucket != storage_service.storage_service.bucket:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Course cover must use the canonical source media bucket",
                )
            if not _is_canonical_cover_source_path(
                object_path,
                course_id=course_id,
            ):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Course cover must use the canonical source media path",
                )
        else:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Unsupported media purpose",
            )
    elif media_type in {"video", "document"}:
        if purpose != "lesson_media":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Unsupported media purpose",
            )
        if storage_bucket != storage_service.storage_service.bucket:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson passthrough media must use the private media bucket",
            )
        if not course_id or not lesson_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson passthrough media is missing course or lesson context",
            )
        if not _is_canonical_lesson_passthrough_object_path(
            object_path,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type=media_type,
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson passthrough media must use the canonical private lesson path",
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )

    try:
        source_exists = await _wait_for_storage_object(
            storage_bucket=storage_bucket,
            storage_path=object_path,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Media upload completion check failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    if not source_exists:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Uploaded file is missing from storage",
        )

    current_state = str(media_asset.get("state") or "").strip().lower()
    if media_type == "audio":
        if current_state == "pending_upload":
            updated = await media_assets_repo.mark_media_asset_uploaded(
                media_id=media_asset_id
            )
            if not updated:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Media not found",
                )
            media_asset = (
                await media_assets_repo.get_media_asset(media_asset_id) or media_asset
            )
    elif purpose == "lesson_media":
        (
            details,
            storage_table_available,
        ) = await storage_objects.fetch_storage_object_details(
            [(storage_bucket, object_path)]
        )
        storage_detail = (
            details.get((storage_bucket, object_path))
            if storage_table_available
            else None
        )
        content_type = _normalize_mime(
            storage_detail.get("content_type") if storage_detail else None
        ) or _canonical_media_asset_content_type(media_asset)
        if not _lesson_passthrough_content_type_supported(media_type, content_type):
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail=_lesson_passthrough_supported_detail(media_type),
            )
        if current_state == "pending_upload":
            updated = await media_assets_repo.mark_media_asset_uploaded(
                media_id=media_asset_id,
            )
            if not updated:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Media not found",
                )
            media_asset = (
                await media_assets_repo.get_media_asset(media_asset_id) or media_asset
            )
    else:
        (
            details,
            storage_table_available,
        ) = await storage_objects.fetch_storage_object_details(
            [(storage_bucket, object_path)]
        )
        storage_detail = (
            details.get((storage_bucket, object_path))
            if storage_table_available
            else None
        )
        content_type = _normalize_mime(
            storage_detail.get("content_type") if storage_detail else None
        ) or _canonical_media_asset_content_type(media_asset)
        if content_type not in _COVER_MIME_TYPES:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="Unsupported cover image type",
            )
        if current_state == "pending_upload":
            updated = await media_assets_repo.mark_media_asset_uploaded(
                media_id=media_asset_id
            )
            if not updated:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Media not found",
                )
            media_asset = (
                await media_assets_repo.get_media_asset(media_asset_id) or media_asset
            )

    return media_asset


async def _authorize_audio_media_asset(
    *,
    user_id: str,
    media_asset_id: str,
) -> dict[str, object]:
    media_asset = await _authorize_media_asset(
        user_id=user_id,
        media_asset_id=media_asset_id,
    )
    media_type = (media_asset.get("media_type") or "").lower()
    if media_type != "audio":
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_AUDIO_SOURCE_SUPPORTED_DETAIL,
        )
    return media_asset


def _media_asset_kind(media_asset: dict[str, object]) -> str:
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    if media_type in {"audio", "image", "video", "document"}:
        return media_type
    raise HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail="Unsupported media type",
    )


def _lesson_media_storage_kind(kind: str) -> str:
    normalized_kind = str(kind or "").strip().lower()
    if normalized_kind == "document":
        return "pdf"
    return normalized_kind


async def _ensure_lesson_media_runtime_id(lesson_media_id: str) -> str:
    runtime_media_id = (
        await canonical_media_resolver.lookup_runtime_media_id_for_lesson_media(
            lesson_media_id
        )
    )
    if runtime_media_id is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Runtime media mapping is missing",
        )
    return runtime_media_id


async def _attach_lesson_media_asset(
    *,
    request: Request,
    user_id: str,
    media_asset: dict[str, object],
    lesson_id: str,
    replacement_lesson_media_id: str | None,
) -> schemas.MediaAttachResponse:
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    if purpose not in {"lesson_audio", "lesson_media"}:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only lesson uploads can use link_scope=lesson",
        )

    course_id = await _authorize_lesson_upload(
        user_id=user_id,
        lesson_id=lesson_id,
        course_id=None,
    )
    scope = _canonical_media_asset_scope(media_asset)
    asset_lesson_id = str(scope.lesson_id or "").strip()
    if asset_lesson_id and asset_lesson_id != lesson_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset is bound to a different lesson",
        )

    asset_course_id = str(scope.course_id or "").strip()
    if asset_course_id and str(course_id) != asset_course_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset is bound to a different course",
        )

    media_asset_id = str(media_asset["id"])
    kind = _media_asset_kind(media_asset)
    lesson_media_kind = _lesson_media_storage_kind(kind)
    asset_state = str(media_asset.get("state") or "").strip().lower()
    if purpose == "lesson_audio":
        if asset_state not in {"uploaded", "processing", "ready"}:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Media asset must be completed before it can be attached",
            )
    else:
        if kind not in {"image", "video", "document"}:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Only lesson image, video, or document assets currently support purpose=lesson_media",
            )
        if asset_state != "ready":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Media asset must be ready before it can be attached",
            )
    duration_seconds = media_asset.get("duration_seconds")
    if duration_seconds is not None:
        duration_seconds = int(duration_seconds)

    lesson_media: dict[str, object] | None = None
    if replacement_lesson_media_id:
        existing_attachment = await models.get_lesson_media_by_media_asset_id(
            media_asset_id
        )
        if (
            existing_attachment is not None
            and str(existing_attachment.get("id") or "") != replacement_lesson_media_id
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Media asset is already attached to another lesson media row",
            )
        existing = await models.get_media(replacement_lesson_media_id)
        if existing is None or str(existing.get("lesson_id") or "") != lesson_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Lesson media not found",
            )
        existing_kind = str(existing.get("kind") or "").strip().lower()
        normalized_existing_kind = (
            "document" if existing_kind == "pdf" else existing_kind
        )
        if normalized_existing_kind and normalized_existing_kind != kind:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Replacement media kind does not match the existing lesson media kind",
            )
        lesson_media = await models.update_lesson_media_asset_link(
            lesson_media_id=replacement_lesson_media_id,
            lesson_id=lesson_id,
            kind=lesson_media_kind,
            media_asset_id=media_asset_id,
            storage_bucket=scope.storage_bucket,
            duration_seconds=duration_seconds,
        )
    else:
        existing = await models.get_lesson_media_by_media_asset_id(media_asset_id)
        if existing is not None:
            existing_lesson_id = str(existing.get("lesson_id") or "").strip()
            if existing_lesson_id and existing_lesson_id != lesson_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Media asset is already attached to another lesson",
                )
            lesson_media = existing
        else:
            lesson_media = await models.add_lesson_media_entry_with_position_retry(
                lesson_id=lesson_id,
                kind=lesson_media_kind,
                storage_path=None,
                storage_bucket=scope.storage_bucket,
                media_id=None,
                media_asset_id=media_asset_id,
                duration_seconds=duration_seconds,
                max_retries=10,
            )

    if lesson_media is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Could not attach media to lesson",
        )

    runtime_media_id: str | None = None
    if kind == "document":
        runtime_media_id = (
            await canonical_media_resolver.lookup_runtime_media_id_for_lesson_media(
                str(lesson_media["id"])
            )
        )
        if runtime_media_id is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Document lesson media must not create runtime playback ids",
            )
    else:
        runtime_media_id = await _ensure_lesson_media_runtime_id(
            str(lesson_media["id"])
        )
    canonical_lesson_media = await _canonical_lesson_media_row(
        lesson_id=lesson_id,
        lesson_media_id=str(lesson_media["id"]),
        base_url=str(request.base_url),
    )
    return schemas.MediaAttachResponse(
        media_asset_id=UUID(media_asset_id),
        media_id=UUID(media_asset_id),
        state=str(media_asset.get("state") or "uploaded"),
        error_message=media_asset.get("error_message"),
        ingest_format=media_asset.get("ingest_format"),
        streaming_format=media_asset.get("playback_format")
        or media_asset.get("streaming_format"),
        duration_seconds=media_asset.get("duration_seconds"),
        codec=media_asset.get("codec"),
        lesson_media_id=UUID(str(lesson_media["id"])),
        runtime_media_id=UUID(runtime_media_id)
        if runtime_media_id is not None
        else None,
        lesson_media=canonical_lesson_media,
    )


async def _attach_home_upload_media_asset(
    *,
    user_id: str,
    media_asset: dict[str, object],
) -> schemas.MediaAttachResponse:
    media_asset_id = str(media_asset["id"])
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    asset_state = str(media_asset.get("state") or "").strip().lower()
    if purpose != "home_player_audio":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only home player uploads can use link_scope=home_upload",
        )
    if asset_state not in {"uploaded", "processing", "ready"}:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset must be completed before it can be attached",
        )

    existing_upload = (
        await home_audio_sources_repo.get_home_player_upload_by_media_asset_id(
            media_asset_id=media_asset_id,
            teacher_id=user_id,
        )
    )
    if existing_upload is None:
        original_name = Path(
            str(media_asset.get("original_object_path") or "").strip()
        ).name.strip()
        title = Path(original_name or "Home upload").stem.strip() or "Home upload"
        created_upload = await home_audio_sources_repo.create_home_player_upload(
            teacher_id=user_id,
            media_asset_id=media_asset_id,
            title=title,
            active=True,
        )
        if created_upload is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Could not attach media to the home player",
            )
        upload_id = str(created_upload["id"])
    else:
        upload_id = str(existing_upload["id"])
        if existing_upload.get("active") is not True:
            updated_upload = await home_audio_sources_repo.update_home_player_upload(
                upload_id=upload_id,
                teacher_id=user_id,
                fields={"active": True},
            )
            if updated_upload is None:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Could not reactivate the home player upload",
                )

    return schemas.MediaAttachResponse(
        media_asset_id=UUID(media_asset_id),
        media_id=UUID(media_asset_id),
        state=str(media_asset.get("state") or "uploaded"),
        error_message=media_asset.get("error_message"),
        ingest_format=media_asset.get("ingest_format"),
        streaming_format=media_asset.get("playback_format")
        or media_asset.get("streaming_format"),
        duration_seconds=media_asset.get("duration_seconds"),
        codec=media_asset.get("codec"),
        lesson_media_id=None,
        lesson_media=None,
    )


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
    media_type = str(payload.media_type or "").strip().lower()
    max_bytes = _upload_max_bytes(media_type)
    if payload.size_bytes > max_bytes:
        if media_type == "image":
            max_mb = max(1, max_bytes // (1024 * 1024))
            detail = f"File too large (max {max_mb} MB)"
        else:
            max_gb = max_bytes // (1024 * 1024 * 1024)
            detail = f"File too large (max {max_gb} GB)"
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=detail,
        )

    purpose = (
        (
            payload.purpose
            or ("lesson_audio" if media_type == "audio" else "lesson_media")
        )
        .strip()
        .lower()
    )
    course_id: str | None = None
    lesson_id: str | None = None
    object_path: str | None = None
    storage_client = storage_service.storage_service
    if media_type == "audio":
        ingest_format = _audio_ingest_format(payload.filename, mime_type)
        if purpose not in {"lesson_audio", "home_player_audio"}:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Unsupported upload purpose",
            )
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
    elif media_type in {"image", "video", "document"}:
        ingest_format = _lesson_passthrough_ingest_format(
            media_type=media_type,
            filename=payload.filename,
            mime_type=mime_type,
        )
        if purpose != "lesson_media":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Unsupported upload purpose",
            )
        if payload.lesson_id is None:
            detail = {
                "image": "lesson_id is required for lesson image uploads",
                "video": "lesson_id is required for lesson video uploads",
                "document": "lesson_id is required for lesson document uploads",
            }[media_type]
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=detail,
            )
        lesson_id = str(payload.lesson_id)
        course_id = await _authorize_lesson_upload(
            user_id=user_id,
            lesson_id=lesson_id,
            course_id=payload.course_id,
        )
        course_id = str(course_id)
        object_path = media_paths.build_lesson_passthrough_object_path(
            course_id=course_id,
            lesson_id=lesson_id,
            media_kind=media_type,
            filename=payload.filename,
        )
        if media_type == "image":
            storage_client = storage_service.public_storage_service
    else:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )
    try:
        object_path = media_paths.validate_new_upload_object_path(object_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    try:
        upload = await storage_client.create_upload_url(
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

    if media_type == "audio":
        media_asset_purpose = (
            "home_player_audio" if purpose == "home_player_audio" else "lesson_audio"
        )
        initial_state = "pending_upload"
    else:
        media_asset_purpose = "lesson_media"
        initial_state = "pending_upload"
    media_asset_id = str(uuid4())
    media_asset_payload = {
        "media_asset_id": media_asset_id,
        "media_type": media_type,
        "purpose": media_asset_purpose,
        "ingest_format": ingest_format,
        "original_object_path": upload.path,
        "state": initial_state,
    }
    logger.info(
        "Creating media_asset lesson_id=%s course_id=%s purpose=%s media_type=%s content_type=%s",
        lesson_id,
        course_id,
        media_asset_payload["purpose"],
        media_asset_payload["media_type"],
        mime_type,
    )
    try:
        media_asset = await media_assets_repo.create_media_asset(**media_asset_payload)
    except Exception:
        logger.exception(
            "Media_asset insert failed lesson_id=%s course_id=%s purpose=%s media_type=%s content_type=%s",
            lesson_id,
            course_id,
            media_asset_payload["purpose"],
            media_asset_payload["media_type"],
            mime_type,
        )
        raise
    if not media_asset:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to create media record",
        )

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    logger.info(
        "Issued media upload URL user_id=%s media_type=%s purpose=%s size_bytes=%s path=%s media_id=%s format=%s",
        user_id,
        media_type,
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
    media_asset = await _authorize_media_asset(
        user_id=user_id,
        media_asset_id=str(payload.media_asset_id),
    )
    scope = _canonical_media_asset_scope(media_asset)

    media_type = scope.media_type
    object_path = scope.object_path
    purpose = scope.purpose
    course_id = scope.course_id or ""
    lesson_id = scope.lesson_id or ""
    if media_type == "audio":
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
    elif media_type in {"image", "video", "document"}:
        if purpose != "lesson_media":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Unsupported media purpose",
            )
        if not lesson_id:
            detail = {
                "image": "Lesson image is missing lesson context",
                "video": "Lesson video is missing lesson context",
                "document": "Lesson document is missing lesson context",
            }[media_type]
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=detail,
            )
        if media_type != "image" and not course_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson passthrough media is missing course or lesson context",
            )
        if not _is_canonical_lesson_passthrough_object_path(
            object_path,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type=media_type,
        ):
            detail = {
                "image": "Lesson image must use the canonical public image path",
                "video": "Lesson video must use the canonical private lesson path",
                "document": "Lesson document must use the canonical private lesson path",
            }[media_type]
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=detail,
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )
    try:
        object_path = media_paths.validate_new_upload_object_path(object_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc

    content_type = _canonical_media_asset_content_type(media_asset)
    if media_type != "audio" and not _lesson_passthrough_content_type_supported(
        media_type, content_type
    ):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=_lesson_passthrough_supported_detail(media_type),
        )
    if media_type == "image" and scope.storage_bucket != settings.media_public_bucket:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Lesson image must use the public media bucket",
        )
    if (
        media_type in {"video", "document"}
        and scope.storage_bucket != storage_service.storage_service.bucket
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Lesson passthrough media must use the private media bucket",
        )
    storage_client = storage_service.get_storage_service(scope.storage_bucket)

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
        "Refreshed media upload URL user_id=%s media_id=%s path=%s",
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


@router.post("/complete", response_model=schemas.MediaCompleteResponse)
@router.post("/upload-url/complete", response_model=schemas.MediaCompleteResponse)
async def complete_upload_url(
    payload: schemas.MediaUploadCompleteRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    media_asset_id = str(payload.media_asset_id)
    media_asset = await _authorize_media_asset(
        user_id=user_id,
        media_asset_id=media_asset_id,
    )
    media_asset = await _finalize_media_asset_upload(media_asset)
    media_type = str(media_asset.get("media_type") or "").strip().lower()

    return schemas.MediaCompleteResponse(
        media_asset_id=UUID(media_asset_id),
        media_id=UUID(media_asset_id),
        state=str(media_asset.get("state") or "uploaded"),
        error_message=media_asset.get("error_message"),
        ingest_format=media_asset.get("ingest_format"),
        streaming_format=media_asset.get("playback_format")
        or media_asset.get("streaming_format"),
        duration_seconds=media_asset.get("duration_seconds"),
        codec=media_asset.get("codec"),
    )


@router.post("/attach", response_model=schemas.MediaAttachResponse)
async def attach_media(
    request: Request,
    payload: schemas.MediaAttachRequest,
    current: TeacherUser,
):
    user_id = str(current["id"])
    media_asset = await _authorize_media_asset(
        user_id=user_id,
        media_asset_id=str(payload.media_asset_id),
    )

    if payload.link_scope == "lesson":
        lesson_id = str(payload.lesson_id or "").strip()
        if not lesson_id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="lesson_id is required for lesson attachments",
            )
        return await _attach_lesson_media_asset(
            request=request,
            user_id=user_id,
            media_asset=media_asset,
            lesson_id=lesson_id,
            replacement_lesson_media_id=(
                str(payload.lesson_media_id)
                if payload.lesson_media_id is not None
                else None
            ),
        )

    if payload.lesson_id is not None or payload.lesson_media_id is not None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="home_upload attachments do not accept lesson linkage fields",
        )

    return await _attach_home_upload_media_asset(
        user_id=user_id,
        media_asset=media_asset,
    )


@router.get("/{media_id}", response_model=schemas.MediaStatusResponse)
async def media_status(
    media_id: UUID,
    current: TeacherUser,
):
    media = await _authorize_media_asset(
        user_id=str(current["id"]),
        media_asset_id=str(media_id),
    )
    return schemas.MediaStatusResponse(
        media_id=media_id,
        state=media.get("state"),
        error_message=media.get("error_message"),
        ingest_format=media.get("ingest_format"),
        streaming_format=media.get("playback_format") or media.get("streaming_format"),
        duration_seconds=media.get("duration_seconds"),
        codec=media.get("codec"),
    )


@router.post("/previews", response_model=schemas.MediaPreviewBatchResponse)
async def request_media_previews(
    request: Request,
    payload: schemas.MediaPreviewBatchRequest,
    current: TeacherUser,
):
    requested_ids: list[str] = []
    valid_requested_ids: list[str] = []
    seen_ids: set[str] = set()
    preview_items: dict[str, schemas.MediaPreviewItem] = {}
    for media_id in payload.ids:
        media_id_str = _normalized_preview_string(media_id)
        if media_id_str is None or media_id_str in seen_ids:
            continue
        seen_ids.add(media_id_str)
        requested_ids.append(media_id_str)
        try:
            UUID(media_id_str)
        except (TypeError, ValueError):
            preview_items[media_id_str] = _preview_failure_item(
                failure_reason="invalid_id"
            )
            continue
        valid_requested_ids.append(media_id_str)

    if not requested_ids:
        return schemas.MediaPreviewBatchResponse(items={})

    if not valid_requested_ids:
        return schemas.MediaPreviewBatchResponse(items=preview_items)

    rows = await courses_repo.list_lesson_media_by_ids(valid_requested_ids)
    rows_by_id = {
        lesson_media_id: row
        for row in rows
        if (lesson_media_id := _normalized_preview_string(row.get("id"))) is not None
    }

    requested_by_lesson: dict[str, set[str]] = {}
    for lesson_media_id in valid_requested_ids:
        row = rows_by_id.get(lesson_media_id)
        if row is None:
            preview_items[lesson_media_id] = _preview_failure_item(
                failure_reason="not_found"
            )
            continue
        lesson_id = _normalized_preview_string(row.get("lesson_id"))
        if not lesson_id or not lesson_media_id:
            preview_items[lesson_media_id] = _preview_failure_item(
                failure_reason="not_found"
            )
            continue
        requested_by_lesson.setdefault(lesson_id, set()).add(lesson_media_id)

    for lesson_id in requested_by_lesson:
        _, course_id = await courses_service.lesson_course_ids(lesson_id)
        if not course_id or not await models.is_course_owner(current["id"], course_id):
            for lesson_media_id in requested_by_lesson[lesson_id]:
                preview_items[lesson_media_id] = _preview_failure_item(
                    failure_reason="unavailable"
                )
            continue

    for lesson_id, lesson_media_ids in requested_by_lesson.items():
        if any(
            preview_items.get(lesson_media_id) is not None
            for lesson_media_id in lesson_media_ids
        ):
            unresolved_ids = {
                lesson_media_id
                for lesson_media_id in lesson_media_ids
                if lesson_media_id not in preview_items
            }
            if not unresolved_ids:
                continue
            lesson_media_ids = unresolved_ids
        lesson_media = await courses_service.list_lesson_media(
            lesson_id,
            mode="editor_preview",
        )
        by_id = {str(item.get("id")): item for item in lesson_media}
        for lesson_media_id in lesson_media_ids:
            item = by_id.get(lesson_media_id)
            if item is None:
                preview_items[lesson_media_id] = _preview_failure_item(
                    failure_reason="not_found"
                )
                continue
            preview_items[lesson_media_id] = await _build_preview_item(
                lesson_media_id=lesson_media_id,
                item=dict(item),
                user_id=str(current["id"]),
            )

    ordered_items = {
        lesson_media_id: preview_items[lesson_media_id]
        for lesson_media_id in requested_ids
        if lesson_media_id in preview_items
    }
    return schemas.MediaPreviewBatchResponse(items=ordered_items)
