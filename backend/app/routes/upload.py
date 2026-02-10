from __future__ import annotations

import hashlib
import logging
import mimetypes
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Annotated, Any
from urllib.parse import urljoin
from uuid import uuid4

import httpx
from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from starlette import status

from .. import models
from ..auth import CurrentUser
from ..config import settings
from ..permissions import TeacherUser
from ..services import courses_service
from ..services import storage_service
from ..utils import media_signer
from ..utils.http_headers import build_content_disposition

logger = logging.getLogger(__name__)

ASSETS_ROOT = Path(__file__).resolve().parents[2] / "assets"
UPLOADS_ROOT = ASSETS_ROOT / "uploads"
_LESSON_MEDIA_BUCKET = "lesson-media"
_PUBLIC_MEDIA_BUCKET = "public-media"
_COURSE_MEDIA_BUCKET = "course-media"
_LESSON_ALLOWED_PREFIXES = ("image/", "video/", "audio/")
_LESSON_ALLOWED_EXACT_TYPES = {"application/pdf"}
_PUBLIC_UPLOAD_BUCKETS = {"public-media", "users", "avatars", "hero", "logos"}
_PROFILE_MAX_BYTES = 5 * 1024 * 1024  # 5 MB avatars
_LESSON_IMAGE_ALLOWED_CONTENT_TYPES = {
    "image/png",
    "image/jpeg",
    "image/webp",
    "image/svg+xml",
}
_LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
}
_LESSON_IMAGE_DEFAULT_EXTENSION_BY_CONTENT_TYPE = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/webp": "webp",
    "image/svg+xml": "svg",
}


class UploadMediaType(str, Enum):
    image = "image"
    audio = "audio"
    video = "video"
    document = "document"


router = APIRouter(prefix="/api/upload", tags=["upload"])
files_router = APIRouter(prefix="/api/files", tags=["files"])
legacy_router = APIRouter(prefix="/upload", tags=["upload"])

_ALLOWED_PROFILE_PREFIXES = ("image/",)
_ALLOWED_MEDIA_PREFIXES = {
    UploadMediaType.image: ("image/",),
    UploadMediaType.audio: ("audio/",),
    UploadMediaType.video: ("video/",),
    UploadMediaType.document: ("application/pdf",),
}


@dataclass(slots=True)
class UploadWriteResult:
    filename: str
    destination_path: Path
    size: int
    checksum: str | None


def _safe_join(base: Path, *parts: str) -> Path:
    candidate = base.joinpath(*parts).resolve()
    if not str(candidate).startswith(str(base.resolve())):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid path")
    return candidate


def _is_public_path(relative_path: Path) -> bool:
    parts = relative_path.parts
    if not parts:
        return False
    return parts[0] in _PUBLIC_UPLOAD_BUCKETS


def _relative_public_path(relative_path: Path) -> str:
    return f"api/files/{relative_path.as_posix()}"


def _public_url(request: Request, relative_path: Path) -> str | None:
    if not _is_public_path(relative_path):
        return None
    base = str(request.base_url)
    return urljoin(base, _relative_public_path(relative_path))


def _detect_kind(content_type: str | None) -> str:
    if not content_type:
        return "other"
    lower = content_type.lower()
    if lower.startswith("image/"):
        return "image"
    if lower.startswith("video/"):
        return "video"
    if lower.startswith("audio/"):
        return "audio"
    if lower == "application/pdf":
        return "pdf"
    return "other"


def _normalize_lesson_image_upload(file: UploadFile) -> tuple[str, str]:
    content_type = (file.content_type or "").split(";", 1)[0].strip().lower()
    if content_type == "image/jpg":
        content_type = "image/jpeg"

    suffix = Path(file.filename or "").suffix.lower()
    if content_type and content_type in _LESSON_IMAGE_ALLOWED_CONTENT_TYPES:
        extension = (
            suffix[1:]
            if suffix in _LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION
            else _LESSON_IMAGE_DEFAULT_EXTENSION_BY_CONTENT_TYPE[content_type]
        )
        return content_type, extension

    if suffix in _LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION:
        normalized_type = _LESSON_IMAGE_CONTENT_TYPE_BY_EXTENSION[suffix]
        return normalized_type, suffix[1:]

    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="Invalid image type. Allowed: png, jpg, jpeg, webp, svg",
    )


async def _write_upload(
    destination_dir: Path,
    file: UploadFile,
    *,
    allowed_prefixes: tuple[str, ...] | None = None,
    max_bytes: int | None = None,
) -> UploadWriteResult:
    if not file.filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing filename")

    normalized_content_type = (file.content_type or "").lower()
    if allowed_prefixes and not any(normalized_content_type.startswith(prefix) for prefix in allowed_prefixes):
        logger.warning(
            "Rejected upload with unexpected content type: filename=%s content_type=%s allowed=%s",
            file.filename,
            normalized_content_type,
            allowed_prefixes,
        )
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="Unsupported media type")

    suffix = Path(file.filename).suffix.lower()
    destination_dir.mkdir(parents=True, exist_ok=True)
    safe_name = f"{uuid4().hex}{suffix}"
    destination_path = destination_dir / safe_name

    payload = await file.read()
    if not payload:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File payload is empty")

    size = len(payload)
    if max_bytes is not None and size > max_bytes:
        max_mb = max(1, max_bytes // (1024 * 1024))
        logger.warning(
            "Upload rejected due to size: filename=%s size=%s max=%s",
            file.filename,
            size,
            max_bytes,
        )
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File too large (max {max_mb} MB)",
        )

    try:
        destination_path.write_bytes(payload)
    except Exception:  # pragma: no cover - defensive logging
        logger.exception("Failed to write uploaded file")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to persist file",
        ) from None

    checksum = hashlib.sha256(payload).hexdigest() if payload else None
    return UploadWriteResult(
        filename=safe_name,
        destination_path=destination_path,
        size=size,
        checksum=checksum,
    )


async def _persist_lesson_media(
    *,
    owner_id: str,
    lesson_id: str,
    relative_path: Path,
    original_name: str | None,
    content_type: str,
    size: int,
    checksum: str | None,
    storage_bucket: str = _LESSON_MEDIA_BUCKET,
) -> dict[str, Any]:
    kind = _detect_kind(content_type)

    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=relative_path.as_posix(),
        storage_bucket=storage_bucket,
        content_type=content_type,
        byte_size=size,
        checksum=checksum,
        original_name=original_name,
    )
    media_id = media_object["id"] if media_object else None

    row = await models.add_lesson_media_entry_with_position_retry(
        lesson_id=lesson_id,
        kind=kind,
        storage_path=relative_path.as_posix(),
        storage_bucket=storage_bucket,
        media_id=media_id,
        max_retries=10,
    )
    if not row:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Could not allocate lesson media position",
        )

    media_signer.attach_media_links(row, purpose="editor_preview")
    return row


@router.post("/profile")
async def upload_profile_media(
    request: Request,
    file: Annotated[UploadFile, File(description="Profile image file")],
    current: CurrentUser,
) -> dict[str, Any]:
    user_id = str(current["id"])
    suffix = Path(file.filename or "").suffix.lower()
    safe_name = f"{uuid4().hex}{suffix}"
    relative_path = Path("users") / user_id / safe_name

    payload = await file.read()
    if not payload:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File payload is empty")
    if len(payload) > _PROFILE_MAX_BYTES:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="File too large")

    content_type = (
        file.content_type
        or mimetypes.guess_type(relative_path.name)[0]
        or "application/octet-stream"
    )
    normalized_content_type = content_type.lower()
    if not any(normalized_content_type.startswith(prefix) for prefix in _ALLOWED_PROFILE_PREFIXES):
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="Unsupported media type")

    if storage_service.public_storage_service.enabled:
        try:
            upload = await storage_service.public_storage_service.create_upload_url(
                relative_path.as_posix(),
                content_type=content_type,
                upsert=True,
                cache_seconds=settings.media_public_cache_seconds,
            )
            timeout = httpx.Timeout(10.0, read=None)
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.put(upload.url, headers=dict(upload.headers), content=payload)
            if response.status_code >= 400:
                logger.warning(
                    "Supabase avatar upload failed: user_id=%s status=%s path=%s",
                    user_id,
                    response.status_code,
                    upload.path,
                )
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Failed to upload avatar",
                )
        except storage_service.StorageServiceError as exc:
            logger.warning("Supabase avatar upload signing failed: user_id=%s error=%s", user_id, exc)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Storage unavailable",
            ) from exc

        public_url = storage_service.public_storage_service.public_url(upload.path)
        logger.info(
            "Profile upload successful (supabase): user_id=%s path=%s size_bytes=%s",
            user_id,
            upload.path,
            len(payload),
        )
        return {
            "url": public_url,
            "path": upload.path,
            "content_type": content_type,
            "size": len(payload),
        }

    # Fallback for local dev without Supabase storage configured.
    await file.seek(0)
    relative_dir = relative_path.parent
    destination_dir = _safe_join(UPLOADS_ROOT, *relative_dir.parts)
    write_result = await _write_upload(
        destination_dir,
        file,
        allowed_prefixes=_ALLOWED_PROFILE_PREFIXES,
        max_bytes=_PROFILE_MAX_BYTES,
    )
    relative_path = relative_dir / write_result.filename
    url = _public_url(request, relative_path)
    if url is None:
        logger.error(
            "Profile upload attempted to write outside public buckets: user_id=%s path=%s",
            user_id,
            relative_path,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Profile storage misconfigured",
        )
    logger.info(
        "Profile upload successful (local): user_id=%s path=%s size_bytes=%s",
        user_id,
        relative_path,
        write_result.size,
    )
    return {
        "url": url,
        "path": relative_path.as_posix(),
        "content_type": content_type,
        "size": write_result.size,
    }


@router.post("/course-media")
async def upload_course_media(
    request: Request,
    file: Annotated[UploadFile, File(description="Media file for course content")],
    current: TeacherUser,
    course_id: Annotated[str | None, Form()] = None,
    lesson_id: Annotated[str | None, Form()] = None,
    media_type: Annotated[UploadMediaType | None, Form(alias="type")] = None,
    is_intro: Annotated[bool | None, Form()] = None,
) -> dict[str, Any]:
    if not settings.media_allow_legacy_media:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Legacy upload endpoint disabled",
        )

    owner = current["id"]
    owner_id = str(owner)
    if not course_id and not lesson_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="course_id or lesson_id must be provided",
        )

    normalized_content_type = (file.content_type or "").lower()

    type_prefixes: tuple[str, ...] | None = None
    if media_type:
        type_prefixes = _ALLOWED_MEDIA_PREFIXES.get(media_type)

    resolved_course_id = course_id
    lesson_is_intro: bool | None = None
    if lesson_id:
        _, lesson_course_id = await courses_service.lesson_course_ids(lesson_id)
        if not lesson_course_id or not await models.is_course_owner(owner, lesson_course_id):
            logger.warning(
                "Permission denied: course media upload user_id=%s course_id=%s lesson_id=%s",
                owner_id,
                lesson_course_id,
                lesson_id,
            )
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not course owner")
        resolved_course_id = lesson_course_id
        lesson_row = await courses_service.fetch_lesson(lesson_id)
        if not lesson_row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lesson not found")
        lesson_is_intro = bool(lesson_row.get("is_intro"))
    elif course_id and not await models.is_course_owner(owner, course_id):
        logger.warning(
            "Permission denied: course media upload user_id=%s course_id=%s",
            owner_id,
            course_id,
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not course owner")

    effective_is_intro = is_intro if is_intro is not None else lesson_is_intro
    if effective_is_intro is None:
        effective_is_intro = False

    storage_bucket = _COURSE_MEDIA_BUCKET
    if lesson_id:
        is_image_upload = media_type == UploadMediaType.image or normalized_content_type.startswith("image/")
        storage_bucket = _PUBLIC_MEDIA_BUCKET if (is_image_upload or effective_is_intro) else _COURSE_MEDIA_BUCKET

    resolved_course_id_str: str | None = str(resolved_course_id) if resolved_course_id else None
    lesson_id_str = str(lesson_id) if lesson_id else None

    if lesson_id:
        if not resolved_course_id_str or not lesson_id_str:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing course_id for lesson media")
        relative_dir = Path(storage_bucket) / resolved_course_id_str / lesson_id_str
    else:
        if not resolved_course_id_str:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing course_id")
        relative_dir = Path(storage_bucket) / resolved_course_id_str
    if media_type:
        relative_dir /= media_type.value

    allowed_prefixes = type_prefixes
    allowed_exact: set[str] = set()
    if allowed_prefixes is None:
        allowed_prefixes = _LESSON_ALLOWED_PREFIXES + tuple(_LESSON_ALLOWED_EXACT_TYPES)
        allowed_exact = set(_LESSON_ALLOWED_EXACT_TYPES)

    if allowed_prefixes and (
        not normalized_content_type
        or not any(normalized_content_type.startswith(prefix) for prefix in allowed_prefixes)
    ):
        if not normalized_content_type or normalized_content_type not in allowed_exact:
            raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="Unsupported media type")

    destination_dir = _safe_join(UPLOADS_ROOT, *relative_dir.parts)
    write_result = await _write_upload(
        destination_dir,
        file,
        allowed_prefixes=allowed_prefixes,
        max_bytes=settings.lesson_media_max_bytes if lesson_id else None,
    )
    relative_path = relative_dir / write_result.filename
    content_type = (
        file.content_type
        or mimetypes.guess_type(write_result.destination_path.name)[0]
        or "application/octet-stream"
    )
    url = _public_url(request, relative_path)
    logger.info(
        "Course media upload successful: course_id=%s lesson_id=%s type=%s path=%s size_bytes=%s bucket=%s",
        resolved_course_id_str,
        lesson_id,
        media_type.value if media_type else None,
        relative_path,
        write_result.size,
        storage_bucket,
    )
    response: dict[str, Any] = {
        "path": relative_path.as_posix(),
        "content_type": content_type,
        "size": write_result.size,
        "storage_bucket": storage_bucket,
    }
    if url:
        response["url"] = url

    if lesson_id:
        media_row = await _persist_lesson_media(
            owner_id=owner_id,
            lesson_id=lesson_id,
            relative_path=relative_path,
            original_name=file.filename,
            content_type=content_type,
            size=write_result.size,
            checksum=write_result.checksum,
            storage_bucket=storage_bucket,
        )
        response["media"] = media_row

    return response


@router.post("/lesson-image")
async def upload_lesson_image(
    request: Request,
    file: Annotated[UploadFile, File(description="Lesson image file")],
    current: TeacherUser,
    lesson_id: Annotated[str, Form()],
    course_id: Annotated[str | None, Form()] = None,
) -> dict[str, Any]:
    owner = current["id"]
    owner_id = str(owner)
    lesson_id_str = str(lesson_id).strip()
    if not lesson_id_str:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="lesson_id is required")

    _, lesson_course_id = await courses_service.lesson_course_ids(lesson_id_str)
    if not lesson_course_id or not await models.is_course_owner(owner, lesson_course_id):
        logger.warning(
            "Permission denied: lesson image upload user_id=%s lesson_id=%s course_id=%s",
            owner_id,
            lesson_id_str,
            lesson_course_id,
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not course owner")

    if course_id and str(course_id).strip() and str(course_id).strip() != str(lesson_course_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="course_id does not match lesson ownership",
        )

    content_type, extension = _normalize_lesson_image_upload(file)
    payload = await file.read()
    if not payload:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File payload is empty")

    max_bytes = max(1, int(settings.media_upload_max_image_bytes))
    size = len(payload)
    if size > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    storage_key = f"lessons/{lesson_id_str}/images/{uuid4()}.{extension}"
    if storage_service.public_storage_service.enabled:
        try:
            upload = await storage_service.public_storage_service.create_upload_url(
                storage_key,
                content_type=content_type,
                upsert=True,
                cache_seconds=settings.media_public_cache_seconds,
            )
            timeout = httpx.Timeout(15.0, read=None)
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.put(
                    upload.url,
                    headers=dict(upload.headers),
                    content=payload,
                )
            if response.status_code >= 400:
                logger.warning(
                    "Supabase lesson image upload failed: lesson_id=%s status=%s key=%s",
                    lesson_id_str,
                    response.status_code,
                    upload.path,
                )
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Failed to upload lesson image",
                )
            persisted_storage_path = upload.path
            public_url = storage_service.public_storage_service.public_url(upload.path)
        except storage_service.StorageServiceError as exc:
            logger.warning(
                "Supabase lesson image upload signing failed: lesson_id=%s error=%s",
                lesson_id_str,
                exc,
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Storage unavailable",
            ) from exc
    else:
        relative_public_path = Path(_PUBLIC_MEDIA_BUCKET) / storage_key
        destination_path = _safe_join(UPLOADS_ROOT, *relative_public_path.parts)
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        destination_path.write_bytes(payload)
        public_url = _public_url(request, relative_public_path)
        if public_url is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Public upload storage misconfigured",
            )
        persisted_storage_path = storage_key

    checksum = hashlib.sha256(payload).hexdigest()
    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=persisted_storage_path,
        storage_bucket=_PUBLIC_MEDIA_BUCKET,
        content_type=content_type,
        byte_size=size,
        checksum=checksum,
        original_name=file.filename,
    )
    media_object_id = media_object["id"] if media_object else None
    row = await models.add_lesson_media_entry_with_position_retry(
        lesson_id=lesson_id_str,
        kind="image",
        storage_path=persisted_storage_path,
        storage_bucket=_PUBLIC_MEDIA_BUCKET,
        media_id=media_object_id,
        max_retries=10,
    )
    if not row:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Could not allocate lesson media position",
        )

    media_payload = dict(row)
    media_payload["kind"] = "image"
    media_payload["url"] = public_url
    media_payload["preferredUrl"] = public_url
    media_payload["original_name"] = file.filename or media_payload.get("original_name")
    media_payload.pop("signed_url", None)
    media_payload.pop("signed_url_expires_at", None)
    media_payload.pop("download_url", None)

    return {"media": media_payload}


@legacy_router.post("/public-media")
async def upload_public_media(
    request: Request,
    file: Annotated[UploadFile, File(description="Public media upload")],
    current: TeacherUser,
) -> dict[str, Any]:
    if not settings.media_allow_legacy_media:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Legacy upload endpoint disabled",
        )

    user_id = str(current["id"])
    relative_dir = Path("public-media") / user_id
    destination_dir = _safe_join(UPLOADS_ROOT, *relative_dir.parts)
    write_result = await _write_upload(
        destination_dir,
        file,
        allowed_prefixes=_LESSON_ALLOWED_PREFIXES + tuple(_LESSON_ALLOWED_EXACT_TYPES),
    )
    relative_path = relative_dir / write_result.filename
    content_type = (
        file.content_type
        or mimetypes.guess_type(write_result.destination_path.name)[0]
        or "application/octet-stream"
    )
    url = _public_url(request, relative_path)
    if url is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Public upload storage misconfigured",
        )
    return {
        "url": url,
        "path": relative_path.as_posix(),
        "content_type": content_type,
        "size": write_result.size,
    }


@files_router.get("/{path:path}", name="serve_uploaded_file")
async def serve_uploaded_file(path: str):
    if not path:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing path")
    relative = Path(path)
    if relative.is_absolute() or ".." in relative.parts:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid file path")
    if not _is_public_path(relative):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Media not publicly accessible")

    file_path = _safe_join(UPLOADS_ROOT, *relative.parts)
    if not file_path.exists() or not file_path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")

    media_type, _ = mimetypes.guess_type(file_path.name)
    response = FileResponse(file_path, media_type=media_type or "application/octet-stream")
    cache_seconds = max(0, settings.media_public_cache_seconds)
    if cache_seconds > 0:
        response.headers["Cache-Control"] = f"public, max-age={cache_seconds}"
    else:
        response.headers["Cache-Control"] = "no-store"
    response.headers["Content-Disposition"] = build_content_disposition(relative.name, disposition="inline")
    return response


# Backwards-compatible aliases for older Flutter Web routes.
legacy_router.add_api_route("/profile", upload_profile_media, methods=["POST"])
legacy_router.add_api_route("/course-media", upload_course_media, methods=["POST"])
legacy_router.add_api_route("/lesson-image", upload_lesson_image, methods=["POST"])


__all__ = ["router", "files_router", "legacy_router"]
