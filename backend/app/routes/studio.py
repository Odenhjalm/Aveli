import logging
import mimetypes
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, NoReturn
from uuid import UUID, uuid4
from fastapi import (
    APIRouter,
    File,
    Form,
    HTTPException,
    Request,
    Response,
    UploadFile,
    status,
)

from .. import models, schemas
from ..auth import CurrentUser
from ..config import settings
from ..db import get_conn
from ..permissions import TeacherEntryUser
from ..repositories import courses as courses_repo
from ..repositories import home_audio_sources as home_audio_sources_repo
from ..repositories import media_assets as media_assets_repo
from ..repositories import studio_home_player_library as studio_home_player_library_repo
from ..repositories import storage_objects
from ..repositories import teacher_profile_media as profile_media_repo
from ..services import (
    courses_service,
    email_service,
    lesson_playback_service,
    referral_service,
    storage_service,
    studio_authority,
)
from ..services import media_cleanup
from ..utils.profile_media import profile_media_item_from_row
from .media import _build_streaming_response
from . import upload as upload_routes

router = APIRouter(prefix="/studio", tags=["studio"])
course_lesson_router = APIRouter(prefix="/studio", tags=["studio"])
lesson_media_router = APIRouter(prefix="/api/lesson-media", tags=["media"])
media_pipeline_router = APIRouter(prefix="/api", tags=["media"])
logger = logging.getLogger(__name__)
_LESSON_EDITOR_TRACE = os.getenv("LESSON_EDITOR_TRACE", "").lower() in {
    "1",
    "true",
    "yes",
}


def _raise_livekit_paused() -> NoReturn:
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="LiveKit är pausat.",
    )


def _raise_v2_feature_disabled(feature: str) -> NoReturn:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail=f"{feature} has no Baseline V2 authority",
    )


_STUDIO_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)
_COURSE_COVER_MIME_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
_CANONICAL_COURSE_FIELDS = (
    "id",
    "slug",
    "title",
    "teacher",
    "course_group_id",
    "group_position",
    "cover_media_id",
    "cover",
    "price_amount_cents",
    "drip_enabled",
    "drip_interval_days",
    "required_enrollment_source",
    "enrollable",
    "purchasable",
)


def _visible_lesson_text(value: str | None, *, limit: int = 1200) -> str:
    if value is None:
        return "<None>"
    visible = value.replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")
    if len(visible) > limit:
        return f"{visible[:limit]}…"
    return visible


def _log_course_owner_denied(
    user_id: str,
    *,
    course_id: str | None = None,
    lesson_id: str | None = None,
    media_id: str | None = None,
) -> None:
    logger.warning(
        "Permission denied: course owner required user_id=%s course_id=%s lesson_id=%s media_id=%s",
        user_id,
        course_id,
        lesson_id,
        media_id,
    )


def _log_seminar_host_denied(user_id: str, seminar_id: str | None) -> None:
    logger.warning(
        "Permission denied: seminar host required user_id=%s seminar_id=%s",
        user_id,
        seminar_id,
    )


def _log_quiz_owner_denied(user_id: str, quiz_id: str | None) -> None:
    logger.warning(
        "Permission denied: quiz owner required user_id=%s quiz_id=%s",
        user_id,
        quiz_id,
    )


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


def _normalize_studio_media_type(value: str) -> str:
    if value not in {"audio", "image", "video", "document"}:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )
    return value


def _require_studio_mime_type(value: str) -> str:
    exact = str(value or "").strip().lower()
    if not exact:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="mime_type is required",
        )
    return exact


def _studio_audio_ingest_format(*, filename: str, mime_type: str) -> str:
    suffix = Path(filename).suffix.lower().lstrip(".")
    if suffix not in {"mp3", "m4a", "wav"}:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported audio format",
        )
    if mime_type not in {
        "audio/mpeg",
        "audio/mp3",
        "audio/m4a",
        "audio/mp4",
        "audio/wav",
        "audio/x-wav",
    }:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported audio format",
        )
    return suffix


def _studio_passthrough_ingest_format(
    *,
    media_type: str,
    filename: str,
    mime_type: str,
) -> str:
    if media_type == "image":
        if not mime_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="Unsupported image format",
            )
        suffix = Path(filename).suffix.lower().lstrip(".")
        return suffix or mime_type.split("/", 1)[1].split(";", 1)[0]
    if media_type == "video":
        if not mime_type.startswith("video/"):
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="Unsupported video format",
            )
        suffix = Path(filename).suffix.lower().lstrip(".")
        return suffix or mime_type.split("/", 1)[1].split(";", 1)[0]
    if media_type == "document":
        if mime_type != "application/pdf":
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="Unsupported document format",
            )
        return "pdf"
    raise HTTPException(
        status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
        detail="Unsupported media type",
    )


def _studio_course_cover_ingest_format(*, filename: str, mime_type: str) -> str:
    if mime_type not in _COURSE_COVER_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported cover image format",
        )
    suffix = Path(filename).suffix.lower().lstrip(".")
    if mime_type == "image/jpeg":
        return "jpeg"
    if mime_type == "image/png":
        return "png"
    if mime_type == "image/webp":
        return "webp"
    return suffix or "image"


def _build_course_cover_source_object_path(course_id: str, filename: str) -> str:
    safe_name = Path(filename).name.strip() or "cover"
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


def _canonical_lesson_media_asset_scope(
    media_asset: dict[str, Any],
) -> tuple[str, str, str | None]:
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    if purpose != "lesson_media":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only lesson media assets can use the lesson-media pipeline",
        )

    media_type = str(media_asset.get("media_type") or "").strip().lower()
    if media_type not in {"audio", "image", "video", "document"}:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )

    object_path = str(media_asset.get("original_object_path") or "").strip().lstrip("/")
    parts = Path(object_path).parts
    if media_type == "audio":
        if (
            len(parts) < 8
            or parts[:4] != ("media", "source", "audio", "courses")
            or parts[5] != "lessons"
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson audio must use the canonical pipeline source path",
            )
        return media_type, parts[6], parts[4]

    if media_type == "image":
        if len(parts) < 4 or parts[0] != "lessons" or parts[2] != "images":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Lesson image must use the canonical public image path",
            )
        return media_type, parts[1], None

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
    return media_type, parts[3], parts[1]


def _canonical_course_cover_asset_scope(media_asset: dict[str, Any]) -> str:
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    if purpose != "course_cover" or media_type != "image":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only course cover image assets can use the course-cover pipeline",
        )

    object_path = str(media_asset.get("original_object_path") or "").strip().lstrip("/")
    parts = Path(object_path).parts
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
    return course_id


def _canonical_home_player_asset_scope(media_asset: dict[str, Any]) -> str:
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    if purpose != "home_player_audio" or media_type != "audio":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only home player audio assets can use the home-player pipeline",
        )

    object_path = str(media_asset.get("original_object_path") or "").strip().lstrip("/")
    parts = Path(object_path).parts
    if len(parts) < 6 or parts[:4] != (
        "media",
        "source",
        "audio",
        "home-player",
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Home player audio must use the canonical source media path",
        )
    user_id = parts[4].strip()
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Home player audio is missing owner context",
        )
    return user_id


async def _require_canonical_lesson_media_authoring_context(
    *,
    lesson_id: str,
    current: TeacherEntryUser,
) -> str:
    await _require_studio_lesson(lesson_id)
    _, course_id = await courses_service.lesson_course_ids(lesson_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
            lesson_id=lesson_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    return str(course_id)


async def _require_canonical_course_cover_authoring_context(
    *,
    course_id: str,
    current: TeacherEntryUser,
) -> str:
    normalized_course_id = str(course_id or "").strip()
    if not normalized_course_id:
        raise HTTPException(status_code=404, detail="Course not found")
    course = await courses_service.fetch_course(course_id=normalized_course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    if not await models.is_course_owner(current["id"], normalized_course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=normalized_course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    return normalized_course_id


async def _authorize_canonical_lesson_media_asset(
    *,
    media_asset_id: str,
    current: TeacherEntryUser,
    expected_lesson_id: str | None = None,
) -> dict[str, Any]:
    media_asset = await media_assets_repo.get_lesson_media_pipeline_asset(
        media_asset_id
    )
    if not media_asset:
        raise HTTPException(status_code=404, detail="Media asset not found")

    _, asset_lesson_id, asset_course_id = _canonical_lesson_media_asset_scope(
        media_asset
    )
    if expected_lesson_id is not None and asset_lesson_id != expected_lesson_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset is bound to a different lesson",
        )

    course_id = await _require_canonical_lesson_media_authoring_context(
        lesson_id=asset_lesson_id,
        current=current,
    )
    if asset_course_id is not None and asset_course_id != course_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset is bound to a different course",
        )
    return media_asset


async def _authorize_canonical_media_upload_asset(
    *,
    media_asset_id: str,
    current: CurrentUser,
) -> dict[str, Any]:
    try:
        return await _authorize_canonical_lesson_media_asset(
            media_asset_id=media_asset_id,
            current=current,
        )
    except HTTPException as exc:
        if exc.status_code != status.HTTP_422_UNPROCESSABLE_ENTITY:
            raise

    media_asset = await media_assets_repo.get_media_asset(media_asset_id)
    if not media_asset:
        raise HTTPException(status_code=404, detail="Media asset not found")

    purpose = str(media_asset.get("purpose") or "").strip().lower()
    if purpose == "lesson_media":
        _, asset_lesson_id, asset_course_id = _canonical_lesson_media_asset_scope(
            media_asset
        )
        course_id = await _require_canonical_lesson_media_authoring_context(
            lesson_id=asset_lesson_id,
            current=current,
        )
        if asset_course_id is not None and asset_course_id != course_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Media asset is bound to a different course",
            )
        return media_asset

    if purpose == "course_cover":
        course_id = _canonical_course_cover_asset_scope(media_asset)
        await _require_canonical_course_cover_authoring_context(
            course_id=course_id,
            current=current,
        )
        return media_asset

    if purpose == "home_player_audio":
        user_id = _canonical_home_player_asset_scope(media_asset)
        if user_id != str(current["id"]):
            raise HTTPException(status_code=403, detail="Not media owner")
        return media_asset

    if purpose == "profile_media":
        if str(media_asset.get("media_type") or "").strip().lower() != "image":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Mediafilen måste vara en bild.",
            )
        if not profile_media_repo.profile_media_asset_belongs_to_subject(
            asset=media_asset,
            subject_user_id=str(current["id"]),
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Du saknar åtkomst till mediafilen.",
            )
        return media_asset

    raise HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail="Unsupported media purpose",
    )


_MAX_MEDIA_BYTES = settings.lesson_media_max_bytes
_MAX_COURSE_COVER_BYTES = max(1, int(settings.media_upload_max_image_bytes))
_UPLOAD_SESSION_EXPIRES_SECONDS = 2 * 60 * 60
_LIVE_RECORDINGS_ROOT = "live-recordings"


async def _assert_storage_bucket_exists(bucket_id: str) -> None:
    normalized = (bucket_id or "").strip()
    if not normalized:
        raise HTTPException(status_code=500, detail="Storage bucket is not configured")

    try:
        async with get_conn() as cur:
            await cur.execute(
                "SELECT 1 FROM storage.buckets WHERE id = %s LIMIT 1",
                (normalized,),
            )
            row = await cur.fetchone()
    except Exception as exc:
        logger.exception("Failed to validate storage bucket bucket=%s", normalized)
        raise HTTPException(
            status_code=500,
            detail="Failed to validate storage bucket",
        ) from exc

    if not row:
        logger.error("Required storage bucket is missing bucket=%s", normalized)
        raise HTTPException(
            status_code=500,
            detail=f"Storage bucket '{normalized}' does not exist",
        )


def _normalize_metadata(row: Dict[str, Any], keys: tuple[str, ...]) -> Dict[str, Any]:
    normalized = dict(row)
    for key in keys:
        if normalized.get(key) is None:
            normalized[key] = {}
    return normalized


def _seminar_from_row(row: Dict[str, Any]) -> schemas.SeminarResponse:
    data = _normalize_metadata(row, ("livekit_metadata",))
    return schemas.SeminarResponse(**data)


def _session_from_row(row: Dict[str, Any]) -> schemas.SeminarSessionResponse:
    data = _normalize_metadata(row, ("metadata",))
    return schemas.SeminarSessionResponse(**data)


def _attendee_from_row(row: Dict[str, Any]) -> schemas.SeminarRegistrationResponse:
    data = dict(row)
    if data.get("host_course_titles") is None:
        data["host_course_titles"] = []
    return schemas.SeminarRegistrationResponse(**data)


def _recording_from_row(row: Dict[str, Any]) -> schemas.SeminarRecordingResponse:
    data = _normalize_metadata(row, ("metadata",))
    return schemas.SeminarRecordingResponse(**data)


async def _apply_course_read_contract(
    courses: dict[str, Any] | list[dict[str, Any]] | None,
) -> None:
    await courses_service.attach_course_cover_read_contract(courses)


def _canonical_course_payload(course: Dict[str, Any]) -> Dict[str, Any]:
    normalized = dict(course)
    courses_service.attach_course_access_model(normalized)
    courses_service.attach_course_teacher_read_contract(normalized)
    return {field: normalized.get(field) for field in _CANONICAL_COURSE_FIELDS}


def _course_response(course: Dict[str, Any]) -> schemas.Course:
    return schemas.Course(**_canonical_course_payload(course))


def _course_list_response(rows: list[dict[str, Any]]) -> schemas.CourseListResponse:
    return schemas.CourseListResponse(items=[_course_response(row) for row in rows])


async def _require_studio_lesson(lesson_id: str) -> dict[str, Any]:
    lesson = await courses_service.fetch_studio_lesson(lesson_id)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return lesson


def _canonical_upload_endpoint(media_asset_id: str) -> str:
    return f"/api/media-assets/{media_asset_id}/upload-bytes"


def _canonical_upload_storage_bucket(media_asset: dict[str, Any]) -> str:
    return storage_service.canonical_upload_bucket_for_media_asset(media_asset)


def _canonical_upload_content_type(media_asset: dict[str, Any]) -> str:
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    ingest_format = str(media_asset.get("ingest_format") or "").strip().lower()
    if media_type == "audio":
        return {
            "mp3": "audio/mpeg",
            "m4a": "audio/mp4",
            "wav": "audio/wav",
        }.get(ingest_format, "application/octet-stream")
    if media_type == "image":
        return {
            "jpeg": "image/jpeg",
            "jpg": "image/jpeg",
            "png": "image/png",
            "webp": "image/webp",
        }.get(ingest_format, "application/octet-stream")
    if media_type == "video":
        return f"video/{ingest_format}" if ingest_format else "application/octet-stream"
    if media_type == "document":
        return (
            "application/pdf" if ingest_format == "pdf" else "application/octet-stream"
        )
    return "application/octet-stream"


def _max_upload_bytes_for_asset(media_asset: dict[str, Any]) -> int:
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    if purpose == "course_cover" or (
        purpose == "profile_media" and media_type == "image"
    ):
        return _MAX_COURSE_COVER_BYTES
    return _MAX_MEDIA_BYTES


async def _assert_canonical_media_storage_write(media_asset: dict[str, Any]) -> None:
    bucket = _canonical_upload_storage_bucket(media_asset)
    object_path = str(media_asset.get("original_object_path") or "").strip().lstrip("/")
    if not bucket or not object_path:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset storage target is incomplete",
        )

    existence, table_available = await storage_objects.fetch_storage_object_existence(
        [(bucket, object_path)]
    )
    if table_available:
        if not existence.get((bucket, object_path), False):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Uploaded file is missing from storage",
            )
        return

    try:
        service = storage_service.get_storage_service(bucket)
        await service.get_presigned_url(object_path, ttl=60, download=False)
    except storage_service.StorageObjectNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Uploaded file is missing from storage",
        ) from exc
    except storage_service.StorageServiceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage verification unavailable",
        ) from exc


async def _issue_canonical_media_upload_session(
    *,
    object_path: str,
    mime_type: str,
    media_type: str,
    purpose: str,
    ingest_format: str,
) -> tuple[dict[str, Any], datetime]:
    del mime_type
    try:
        validated_object_path = (
            upload_routes.media_paths.validate_new_upload_object_path(object_path)
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc

    media_asset = await media_assets_repo.create_media_asset(
        media_asset_id=str(uuid4()),
        media_type=media_type,
        purpose=purpose,
        original_object_path=validated_object_path,
        ingest_format=ingest_format,
        state="pending_upload",
    )
    expires_at = datetime.now(timezone.utc) + timedelta(
        seconds=_UPLOAD_SESSION_EXPIRES_SECONDS
    )
    return media_asset, expires_at


def _preview_file_name(row: dict[str, Any]) -> str | None:
    value = str(row.get("original_name") or "").strip()
    return value or None


def _normalized_studio_media_state(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized not in _STUDIO_MEDIA_STATES:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical studio media state is unavailable",
        )
    return normalized


def _normalized_resolved_url(playback: dict[str, Any]) -> str | None:
    resolved = str(playback.get("resolved_url") or "").strip()
    return resolved or None


async def _compose_studio_media(
    *,
    lesson_media_id: str,
    media_asset_id: str | None,
    media_state: str,
    user_id: str,
) -> schemas.ResolvedMedia | None:
    exact_media_asset_id = str(media_asset_id or "").strip()
    if not exact_media_asset_id:
        return None

    normalized_state = _normalized_studio_media_state(media_state)
    resolved_url: str | None = None
    if normalized_state == "ready":
        try:
            playback = await lesson_playback_service.resolve_lesson_media_playback(
                lesson_media_id=lesson_media_id,
                user_id=user_id,
            )
        except HTTPException:
            return None
        resolved_url = _normalized_resolved_url(playback)
        if resolved_url is None:
            return None

    return schemas.ResolvedMedia(
        media_id=UUID(exact_media_asset_id),
        state=normalized_state,
        resolved_url=resolved_url,
    )


async def _studio_lesson_media_item_from_row(
    *,
    row: dict[str, Any],
    user_id: str,
) -> schemas.StudioLessonMediaItem:
    lesson_media_id = str(row.get("lesson_media_id") or "").strip()
    if not lesson_media_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical studio lesson media identity is unavailable",
        )

    payload = dict(row)
    payload["state"] = _normalized_studio_media_state(row.get("state"))
    payload["preview_ready"] = bool(row.get("preview_ready"))
    payload["media"] = await _compose_studio_media(
        lesson_media_id=lesson_media_id,
        media_asset_id=str(row.get("media_asset_id") or "").strip() or None,
        media_state=payload["state"],
        user_id=user_id,
    )
    return schemas.StudioLessonMediaItem(**payload)


def _preview_failure_item(
    *,
    media_type: str,
    row: dict[str, Any],
    failure_reason: str,
) -> schemas.MediaPreviewItem:
    return schemas.MediaPreviewItem(
        media_type=media_type,
        authoritative_editor_ready=False,
        resolved_preview_url=None,
        file_name=_preview_file_name(row),
        failure_reason=failure_reason,
    )


async def _preview_item_from_row(
    *,
    lesson_media_id: str,
    row: dict[str, Any],
    user_id: str,
) -> schemas.MediaPreviewItem:
    media_type = str(row.get("media_type") or "").strip().lower()
    if media_type not in {"audio", "image", "video"}:
        return _preview_failure_item(
            media_type=media_type,
            row=row,
            failure_reason="unsupported_media_type",
        )

    try:
        playback = await lesson_playback_service.resolve_lesson_media_playback(
            lesson_media_id=lesson_media_id,
            user_id=user_id,
        )
    except HTTPException:
        return _preview_failure_item(
            media_type=media_type,
            row=row,
            failure_reason="unresolvable",
        )

    resolved_url = str(playback.get("resolved_url") or "").strip()
    if media_type in {"image", "video"} and not resolved_url:
        return _preview_failure_item(
            media_type=media_type,
            row=row,
            failure_reason="unresolvable",
        )

    return schemas.MediaPreviewItem(
        media_type=media_type,
        authoritative_editor_ready=True,
        resolved_preview_url=resolved_url if media_type in {"image", "video"} else None,
        file_name=_preview_file_name(row),
        failure_reason=None,
    )


@router.get("/status")
async def studio_status(current: TeacherEntryUser):
    info = await models.teacher_status(current["id"])
    return info


@router.post(
    "/referrals/create",
    response_model=schemas.ReferralCodeCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_referral_invitation(
    payload: schemas.ReferralCodeCreateRequest,
    current: TeacherEntryUser,
):
    try:
        referral, delivery = await referral_service.create_referral_invitation(
            teacher_id=str(current["id"]),
            email=payload.email,
            free_days=payload.free_days,
            free_months=payload.free_months,
        )
    except email_service.EmailDeliveryError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to send referral invitation email",
        ) from exc

    return schemas.ReferralCodeCreateResponse(
        referral=schemas.ReferralCodeRecord(**referral),
        email_delivery=delivery.mode,
    )


@router.get("/certificates")
async def studio_certificates(current: TeacherEntryUser, verified_only: bool = False):
    del current, verified_only
    _raise_v2_feature_disabled("Studio certificates")


@router.post("/certificates")
async def studio_add_certificate(
    payload: schemas.StudioCertificateCreate,
    current: TeacherEntryUser,
):
    del payload, current
    _raise_v2_feature_disabled("Studio certificates")


@course_lesson_router.post("/courses", response_model=schemas.Course)
async def create_course(payload: schemas.StudioCourseCreate, current: TeacherEntryUser):
    try:
        row = await courses_service.create_course(
            payload.model_dump(),
            teacher_id=str(current["id"]),
        )
    except courses_service.CourseCreationError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    except RuntimeError as exc:
        logger.exception("Course create runtime error")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=courses_service.COURSE_CREATE_TECHNICAL_DETAIL,
        ) from exc
    except ValueError as exc:
        logger.warning("Course create validation error: %s", exc)
        raise HTTPException(
            status_code=422,
            detail=courses_service.COURSE_CREATE_INVALID_DATA_DETAIL,
        ) from exc
    if not row:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=courses_service.COURSE_CREATE_INVALID_DATA_DETAIL,
        )
    await _apply_course_read_contract(row)
    return _course_response(row)


@media_pipeline_router.post(
    "/lessons/{lesson_id}/media-assets/upload-url",
    response_model=schemas.CanonicalLessonMediaUploadUrlResponse,
)
async def canonical_issue_lesson_media_upload_url(
    lesson_id: UUID,
    payload: schemas.CanonicalLessonMediaUploadUrlRequest,
    current: TeacherEntryUser,
):
    lesson_id_str = str(lesson_id)
    course_id = await _require_canonical_lesson_media_authoring_context(
        lesson_id=lesson_id_str,
        current=current,
    )
    if payload.size_bytes > _MAX_MEDIA_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    normalized_media_type = _normalize_studio_media_type(payload.media_type)
    exact_mime_type = _require_studio_mime_type(payload.mime_type)
    if normalized_media_type == "audio":
        ingest_format = _studio_audio_ingest_format(
            filename=payload.filename,
            mime_type=exact_mime_type,
        )
        object_path = upload_routes.media_paths.build_lesson_audio_source_object_path(
            course_id,
            lesson_id_str,
            payload.filename,
        )
    else:
        ingest_format = _studio_passthrough_ingest_format(
            media_type=normalized_media_type,
            filename=payload.filename,
            mime_type=exact_mime_type,
        )
        object_path = upload_routes.media_paths.build_lesson_passthrough_object_path(
            course_id=course_id,
            lesson_id=lesson_id_str,
            media_kind=normalized_media_type,
            filename=payload.filename,
        )

    media_asset, expires_at = await _issue_canonical_media_upload_session(
        object_path=object_path,
        mime_type=exact_mime_type,
        media_type=normalized_media_type,
        purpose="lesson_media",
        ingest_format=ingest_format,
    )
    media_asset_id = UUID(str(media_asset["id"]))
    return schemas.CanonicalLessonMediaUploadUrlResponse(
        media_asset_id=media_asset_id,
        asset_state="pending_upload",
        upload_session_id=media_asset_id,
        upload_endpoint=_canonical_upload_endpoint(str(media_asset_id)),
        expires_at=expires_at,
    )


@media_pipeline_router.post(
    "/courses/{course_id}/cover-media-assets/upload-url",
    response_model=schemas.CanonicalCourseCoverUploadUrlResponse,
)
async def canonical_issue_course_cover_upload_url(
    course_id: UUID,
    payload: schemas.CanonicalCourseCoverUploadUrlRequest,
    current: TeacherEntryUser,
):
    course_id_str = await _require_canonical_course_cover_authoring_context(
        course_id=str(course_id),
        current=current,
    )
    if payload.size_bytes > _MAX_COURSE_COVER_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    exact_mime_type = _require_studio_mime_type(payload.mime_type)
    ingest_format = _studio_course_cover_ingest_format(
        filename=payload.filename,
        mime_type=exact_mime_type,
    )
    object_path = _build_course_cover_source_object_path(
        course_id_str,
        payload.filename,
    )
    media_asset, expires_at = await _issue_canonical_media_upload_session(
        object_path=object_path,
        mime_type=exact_mime_type,
        media_type="image",
        purpose="course_cover",
        ingest_format=ingest_format,
    )
    media_asset_id = UUID(str(media_asset["id"]))
    return schemas.CanonicalCourseCoverUploadUrlResponse(
        media_asset_id=media_asset_id,
        asset_state="pending_upload",
        upload_session_id=media_asset_id,
        upload_endpoint=_canonical_upload_endpoint(str(media_asset_id)),
        expires_at=expires_at,
    )


@media_pipeline_router.post(
    "/home-player/media-assets/upload-url",
    response_model=schemas.CanonicalHomePlayerMediaUploadUrlResponse,
)
async def canonical_issue_home_player_upload_url(
    payload: schemas.CanonicalHomePlayerMediaUploadUrlRequest,
    current: TeacherEntryUser,
):
    if payload.size_bytes > _MAX_MEDIA_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    exact_mime_type = _require_studio_mime_type(payload.mime_type)
    ingest_format = _studio_audio_ingest_format(
        filename=payload.filename,
        mime_type=exact_mime_type,
    )
    object_path = upload_routes.media_paths.build_home_player_audio_source_object_path(
        str(current["id"]),
        payload.filename,
    )
    media_asset, expires_at = await _issue_canonical_media_upload_session(
        object_path=object_path,
        mime_type=exact_mime_type,
        media_type="audio",
        purpose="home_player_audio",
        ingest_format=ingest_format,
    )
    media_asset_id = UUID(str(media_asset["id"]))
    return schemas.CanonicalHomePlayerMediaUploadUrlResponse(
        media_asset_id=media_asset_id,
        asset_state="pending_upload",
        upload_session_id=media_asset_id,
        upload_endpoint=_canonical_upload_endpoint(str(media_asset_id)),
        expires_at=expires_at,
    )


@media_pipeline_router.put(
    "/media-assets/{media_asset_id}/upload-bytes",
    response_model=schemas.CanonicalMediaAssetUploadBytesResponse,
)
async def canonical_upload_media_asset_bytes(
    media_asset_id: UUID,
    request: Request,
    current: CurrentUser,
):
    media_asset_id_str = str(media_asset_id)
    media_asset = await _authorize_canonical_media_upload_asset(
        media_asset_id=media_asset_id_str,
        current=current,
    )
    asset_state = str(media_asset.get("state") or "").strip().lower()
    if asset_state != "pending_upload":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset cannot receive upload bytes from its current state",
        )

    content_length_raw = request.headers.get("content-length")
    if content_length_raw:
        try:
            content_length = int(content_length_raw)
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid content length",
            ) from exc
        if content_length <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File payload is empty",
            )
        if content_length > _max_upload_bytes_for_asset(media_asset):
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="File too large",
            )

    object_path = str(media_asset.get("original_object_path") or "").strip().lstrip("/")
    if not object_path:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset storage target is incomplete",
        )
    bucket = _canonical_upload_storage_bucket(media_asset)
    content_type = request.headers.get(
        "content-type"
    ) or _canonical_upload_content_type(media_asset)
    storage = storage_service.get_storage_service(bucket)

    try:
        await storage.upload_object(
            object_path,
            content=request.stream(),
            content_type=content_type,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning(
            "Backend media upload failed media_asset_id=%s bucket=%s path=%s error=%s",
            media_asset_id_str,
            bucket,
            object_path,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage upload failed",
        ) from exc

    await _assert_canonical_media_storage_write(media_asset)
    return schemas.CanonicalMediaAssetUploadBytesResponse(
        media_asset_id=media_asset_id,
        uploaded=True,
    )


@media_pipeline_router.post(
    "/media-assets/{media_asset_id}/upload-completion",
    response_model=schemas.CanonicalMediaAssetUploadCompletionResponse,
)
async def canonical_complete_lesson_media_upload(
    media_asset_id: UUID,
    payload: schemas.CanonicalMediaAssetUploadCompletionRequest,
    current: CurrentUser,
):
    del payload
    media_asset_id_str = str(media_asset_id)
    media_asset = await _authorize_canonical_media_upload_asset(
        media_asset_id=media_asset_id_str,
        current=current,
    )
    await _assert_canonical_media_storage_write(media_asset)
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    if purpose in {"course_cover", "profile_media"}:
        updated = await media_assets_repo.mark_media_asset_uploaded(
            media_id=media_asset_id_str,
        )
    else:
        updated = await media_assets_repo.mark_lesson_media_pipeline_asset_uploaded(
            media_id=media_asset_id_str,
        )
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset cannot be marked uploaded from its current state",
        )
    return schemas.CanonicalMediaAssetUploadCompletionResponse(
        media_asset_id=media_asset_id,
        asset_state="uploaded",
    )


@media_pipeline_router.get(
    "/media-assets/{media_asset_id}/status",
    response_model=schemas.CanonicalMediaAssetStatusResponse,
)
async def canonical_read_media_asset_status(
    media_asset_id: UUID,
    current: CurrentUser,
):
    media_asset = await _authorize_canonical_media_upload_asset(
        media_asset_id=str(media_asset_id),
        current=current,
    )
    return schemas.CanonicalMediaAssetStatusResponse(
        media_asset_id=media_asset_id,
        asset_state=_normalized_studio_media_state(media_asset.get("state")),
    )


@media_pipeline_router.post(
    "/lessons/{lesson_id}/media-placements",
    response_model=schemas.CanonicalLessonMediaPlacementResponse,
)
async def canonical_create_lesson_media_placement(
    lesson_id: UUID,
    payload: schemas.CanonicalLessonMediaPlacementCreate,
    current: TeacherEntryUser,
):
    lesson_id_str = str(lesson_id)
    await _require_canonical_lesson_media_authoring_context(
        lesson_id=lesson_id_str,
        current=current,
    )
    media_asset_id = str(payload.media_asset_id)
    media_asset = await _authorize_canonical_lesson_media_asset(
        media_asset_id=media_asset_id,
        current=current,
        expected_lesson_id=lesson_id_str,
    )
    asset_state = str(media_asset.get("state") or "").strip().lower()
    if asset_state in {"pending_upload", "failed"}:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset cannot be placed from its current state",
        )
    if asset_state not in {"uploaded", "processing", "ready"}:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset has an unsupported lifecycle state",
        )
    if await courses_repo.lesson_media_asset_is_linked(media_asset_id):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset is already attached to lesson media",
        )

    row = await courses_repo.create_lesson_media(
        lesson_id=lesson_id_str,
        media_asset_id=media_asset_id,
    )
    return schemas.CanonicalLessonMediaPlacementResponse(
        lesson_media_id=UUID(str(row["lesson_media_id"])),
        lesson_id=lesson_id,
        media_asset_id=payload.media_asset_id,
        position=int(row["position"]),
        media_type=str(row["media_type"]),
        asset_state=str(row["state"]),
    )


@media_pipeline_router.get(
    "/media-placements/{lesson_media_id}",
    response_model=schemas.CanonicalMediaPlacementReadResponse,
)
async def canonical_get_lesson_media_placement(
    lesson_media_id: UUID,
    current: TeacherEntryUser,
):
    row = await courses_repo.get_lesson_media_by_id_for_studio(str(lesson_media_id))
    if not row:
        raise HTTPException(status_code=404, detail="Lesson media not found")
    lesson_id = str(row["lesson_id"])
    await _require_canonical_lesson_media_authoring_context(
        lesson_id=lesson_id,
        current=current,
    )
    media = await _compose_studio_media(
        lesson_media_id=str(lesson_media_id),
        media_asset_id=str(row.get("media_asset_id") or "").strip() or None,
        media_state=str(row.get("state") or "").strip(),
        user_id=str(current["id"]),
    )
    return schemas.CanonicalMediaPlacementReadResponse(
        lesson_media_id=lesson_media_id,
        lesson_id=UUID(lesson_id),
        media_asset_id=UUID(str(row["media_asset_id"])),
        position=int(row["position"]),
        media_type=str(row["media_type"]),
        asset_state=str(row["state"]),
        media=media,
    )


@media_pipeline_router.patch("/lessons/{lesson_id}/media-placements/reorder")
async def canonical_reorder_lesson_media_placements(
    lesson_id: UUID,
    payload: schemas.StudioLessonMediaReorder,
    current: TeacherEntryUser,
):
    await _require_canonical_lesson_media_authoring_context(
        lesson_id=str(lesson_id),
        current=current,
    )
    ordered_ids = [str(item) for item in payload.lesson_media_ids]
    if not ordered_ids:
        return {"ok": True}
    if len(set(ordered_ids)) != len(ordered_ids):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Duplicate lesson media id in reorder payload",
        )
    try:
        await courses_repo.reorder_lesson_media(str(lesson_id), ordered_ids)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"ok": True}


@media_pipeline_router.delete("/media-placements/{lesson_media_id}")
async def canonical_delete_lesson_media_placement(
    lesson_media_id: UUID,
    current: TeacherEntryUser,
):
    row = await courses_repo.get_lesson_media_by_id_for_studio(str(lesson_media_id))
    if not row:
        raise HTTPException(status_code=404, detail="Lesson media not found")

    lesson_id = str(row["lesson_id"])
    await _require_canonical_lesson_media_authoring_context(
        lesson_id=lesson_id,
        current=current,
    )
    deleted = await courses_repo.delete_lesson_media(
        lesson_id,
        str(lesson_media_id),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Lesson media not found")
    await media_cleanup.request_lifecycle_evaluation(
        media_asset_ids=[str(deleted.get("media_asset_id") or "")],
        trigger_source="placement_delete",
        subject_type="lesson_media",
        subject_id=str(lesson_media_id),
    )
    return {"deleted": True}


@lesson_media_router.get(
    "/{lesson_id}",
    include_in_schema=False,
)
async def studio_list_lesson_media(
    lesson_id: UUID,
    current: TeacherEntryUser,
):
    del lesson_id, current
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Legacy lesson media listing endpoint removed from canonical runtime",
    )


@lesson_media_router.get(
    "/{lesson_id}/{lesson_media_id}/preview",
    response_model=schemas.StudioLessonMediaPreviewResponse,
)
async def studio_preview_lesson_media(
    lesson_id: UUID,
    lesson_media_id: UUID,
    current: TeacherEntryUser,
):
    user_id = str(current["id"])
    await _require_studio_lesson(str(lesson_id))
    row = await courses_repo.get_lesson_media_for_studio(
        str(lesson_id),
        str(lesson_media_id),
    )
    if not row:
        raise HTTPException(status_code=404, detail="Lesson media not found")
    row_lesson_media_id = str(row.get("lesson_media_id") or "").strip()
    try:
        canonical_lesson_media_id = UUID(row_lesson_media_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical studio lesson media identity is unavailable",
        ) from exc
    if canonical_lesson_media_id != lesson_media_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical studio lesson media identity is unavailable",
        )
    if row.get("preview_ready") is not True:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Preview is not ready",
        )

    playback = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id=str(canonical_lesson_media_id),
        user_id=user_id,
    )
    resolved_url = str(playback.get("resolved_url") or "").strip()
    expires_at = playback.get("expires_at")
    if not resolved_url or not isinstance(expires_at, datetime):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Preview storage is unavailable",
        )
    return schemas.StudioLessonMediaPreviewResponse(
        lesson_media_id=canonical_lesson_media_id,
        preview_url=resolved_url,
        expires_at=expires_at,
    )


@lesson_media_router.post("/previews", response_model=schemas.MediaPreviewBatchResponse)
async def studio_request_lesson_media_previews(
    payload: schemas.MediaPreviewBatchRequest,
    current: TeacherEntryUser,
):
    requested_ids: list[str] = []
    seen_ids: set[str] = set()
    preview_items: dict[str, schemas.MediaPreviewItem] = {}
    for lesson_media_id in payload.ids:
        requested_id = str(lesson_media_id)
        if requested_id in seen_ids:
            continue
        seen_ids.add(requested_id)
        requested_ids.append(requested_id)

    if not requested_ids:
        return schemas.MediaPreviewBatchResponse(items={})

    rows = await courses_repo.list_lesson_media_by_ids_for_studio(requested_ids)
    rows_by_id = {
        str(row["lesson_media_id"]): dict(row)
        for row in rows
        if row.get("lesson_media_id") is not None
    }

    for lesson_media_id in requested_ids:
        row = rows_by_id.get(lesson_media_id)
        if row is None:
            continue

        lesson_id_value = str(row.get("lesson_id") or "").strip()
        _, course_id = await courses_service.lesson_course_ids(lesson_id_value)
        if not course_id or not await models.is_course_owner(current["id"], course_id):
            preview_items[lesson_media_id] = _preview_failure_item(
                media_type=str(row.get("media_type") or "").strip().lower(),
                row=row,
                failure_reason="unavailable",
            )
            continue

        preview_items[lesson_media_id] = await _preview_item_from_row(
            lesson_media_id=lesson_media_id,
            row=row,
            user_id=str(current["id"]),
        )

    ordered_items = {
        lesson_media_id: preview_items[lesson_media_id]
        for lesson_media_id in requested_ids
        if lesson_media_id in preview_items
    }
    return schemas.MediaPreviewBatchResponse(items=ordered_items)


@router.get("/lessons/{lesson_id}/media", include_in_schema=False)
async def list_lesson_media(
    request: Request, lesson_id: UUID, current: TeacherEntryUser
):
    del request, lesson_id, current
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Legacy lesson media listing endpoint removed from canonical runtime",
    )


@router.get(
    "/profile/media",
    response_model=schemas.TeacherProfileMediaListResponse,
)
async def studio_profile_media(current: TeacherEntryUser):
    teacher_id = str(current["id"])
    rows = await profile_media_repo.list_teacher_profile_media(teacher_id)
    return schemas.TeacherProfileMediaListResponse(
        items=[await profile_media_item_from_row(row) for row in rows],
    )


@router.post(
    "/profile/media",
    response_model=schemas.TeacherProfileMediaItem,
    status_code=201,
)
async def studio_create_profile_media(
    payload: schemas.TeacherProfileMediaCreate,
    current: TeacherEntryUser,
):
    row = await profile_media_repo.create_teacher_profile_media(
        teacher_id=str(current["id"]),
        media_asset_id=str(payload.media_asset_id),
        visibility=payload.visibility.value,
    )
    if not row:
        raise HTTPException(
            status_code=400, detail="Failed to create profile media item"
        )
    return await profile_media_item_from_row(row)


@router.patch(
    "/profile/media/{item_id}",
    response_model=schemas.TeacherProfileMediaItem,
)
async def studio_update_profile_media(
    item_id: UUID,
    payload: schemas.TeacherProfileMediaUpdate,
    current: TeacherEntryUser,
):
    fields: Dict[str, Any] = {}
    if payload.media_asset_id is not None:
        fields["media_asset_id"] = str(payload.media_asset_id)
    if payload.visibility is not None:
        fields["visibility"] = payload.visibility.value

    row = await profile_media_repo.update_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
        fields=fields,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    return await profile_media_item_from_row(row)


@router.delete("/profile/media/{item_id}", status_code=204)
async def studio_delete_profile_media(item_id: UUID, current: TeacherEntryUser):
    existing = await profile_media_repo.get_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    deleted = await profile_media_repo.delete_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    media_asset_id = str(existing.get("media_asset_id") or "").strip()
    if media_asset_id:
        await media_cleanup.request_lifecycle_evaluation(
            media_asset_ids=[media_asset_id],
            trigger_source="profile_media_delete",
            subject_type="profile_media",
            subject_id=str(item_id),
        )
    return Response(status_code=204)


@router.get(
    "/home-player/library",
    response_model=schemas.HomePlayerLibraryResponse,
)
async def studio_home_player_library(current: TeacherEntryUser):
    payload = await studio_home_player_library_repo.get_home_player_library(
        teacher_id=str(current["id"]),
    )
    return schemas.HomePlayerLibraryResponse(
        uploads=[
            schemas.HomePlayerLibraryUploadItem(**item)
            for item in payload["uploads"]
        ],
        course_links=[
            schemas.HomePlayerLibraryCourseLinkItem(**item)
            for item in payload["course_links"]
        ],
        course_media=[
            schemas.HomePlayerLibraryCourseMediaItem(**item)
            for item in payload["course_media"]
        ],
    )


@router.post(
    "/home-player/uploads",
    response_model=schemas.HomePlayerUploadItem,
    status_code=status.HTTP_201_CREATED,
)
async def studio_create_home_player_upload(
    payload: schemas.HomePlayerUploadCreate,
    current: TeacherEntryUser,
):
    teacher_id = str(current["id"])
    normalized_title = (payload.title or "").strip()
    if not normalized_title:
        raise HTTPException(status_code=422, detail="title is required")
    media_asset = await home_audio_sources_repo.get_home_audio_media_asset(
        str(payload.media_asset_id)
    )
    if not media_asset:
        raise HTTPException(status_code=404, detail="Media not found")
    if str(media_asset.get("purpose") or "").strip().lower() != "home_player_audio":
        raise HTTPException(status_code=422, detail="Invalid media purpose")
    if str(media_asset.get("media_type") or "").strip().lower() != "audio":
        raise HTTPException(status_code=422, detail="Invalid media type")

    created = await home_audio_sources_repo.create_home_player_upload(
        teacher_id=teacher_id,
        media_asset_id=str(payload.media_asset_id),
        title=normalized_title,
        active=bool(payload.active),
    )
    if not created:
        raise HTTPException(status_code=400, detail="Failed to create upload")
    return schemas.HomePlayerUploadItem(**created)


@router.patch(
    "/home-player/uploads/{upload_id}",
    response_model=schemas.HomePlayerUploadItem,
)
async def studio_update_home_player_upload(
    upload_id: UUID,
    payload: schemas.HomePlayerUploadUpdate,
    current: TeacherEntryUser,
):
    if payload.title is not None and not payload.title.strip():
        raise HTTPException(status_code=422, detail="title cannot be empty")
    fields: dict[str, Any] = {}
    if payload.title is not None:
        fields["title"] = payload.title
    if payload.active is not None:
        fields["active"] = payload.active
    row = await home_audio_sources_repo.update_home_player_upload(
        upload_id=str(upload_id),
        teacher_id=str(current["id"]),
        fields=fields,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Home upload not found")
    return schemas.HomePlayerUploadItem(**row)


@router.delete(
    "/home-player/uploads/{upload_id}", status_code=status.HTTP_204_NO_CONTENT
)
async def studio_delete_home_player_upload(upload_id: UUID, current: TeacherEntryUser):
    deleted = await home_audio_sources_repo.delete_home_player_upload(
        upload_id=str(upload_id),
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Home upload not found")
    media_asset_id = deleted.get("media_asset_id")
    if media_asset_id:
        await media_cleanup.request_lifecycle_evaluation(
            media_asset_ids=[str(media_asset_id)],
            trigger_source="home_player_upload_delete",
            subject_type="home_player_upload",
            subject_id=str(upload_id),
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/home-player/course-links",
    response_model=schemas.HomePlayerCourseLinkItem,
    status_code=status.HTTP_201_CREATED,
)
async def studio_create_home_player_course_link(
    payload: schemas.HomePlayerCourseLinkCreate,
    current: TeacherEntryUser,
):
    teacher_id = str(current["id"])
    title = (payload.title or "").strip()
    if not title:
        raise HTTPException(status_code=422, detail="title is required")

    resolved = await home_audio_sources_repo.resolve_lesson_media_course_owner(
        str(payload.lesson_media_id),
    )
    if not resolved:
        raise HTTPException(status_code=404, detail="Lesson media not found")
    if str(resolved.get("teacher_id")) != teacher_id:
        raise HTTPException(status_code=403, detail="Not course owner")
    if str(resolved.get("media_type") or "").strip().lower() != "audio":
        raise HTTPException(status_code=422, detail="Only audio can be linked")
    if str(resolved.get("media_purpose") or "").strip().lower() != "lesson_media":
        raise HTTPException(status_code=422, detail="Invalid media purpose")

    row = await home_audio_sources_repo.upsert_home_player_course_link(
        teacher_id=teacher_id,
        lesson_media_id=str(payload.lesson_media_id),
        title=title,
        enabled=bool(payload.enabled),
    )
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create course link")
    return schemas.HomePlayerCourseLinkItem(**row)


@router.patch(
    "/home-player/course-links/{link_id}",
    response_model=schemas.HomePlayerCourseLinkItem,
)
async def studio_update_home_player_course_link(
    link_id: UUID,
    payload: schemas.HomePlayerCourseLinkUpdate,
    current: TeacherEntryUser,
):
    if payload.title is not None and not payload.title.strip():
        raise HTTPException(status_code=422, detail="title cannot be empty")

    fields: dict[str, Any] = {}
    if payload.enabled is not None:
        fields["enabled"] = payload.enabled
    if payload.title is not None:
        fields["title"] = payload.title

    row = await home_audio_sources_repo.update_home_player_course_link(
        link_id=str(link_id),
        teacher_id=str(current["id"]),
        fields=fields,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Course link not found")
    return schemas.HomePlayerCourseLinkItem(**row)


@router.delete(
    "/home-player/course-links/{link_id}", status_code=status.HTTP_204_NO_CONTENT
)
async def studio_delete_home_player_course_link(
    link_id: UUID, current: TeacherEntryUser
):
    deleted = await home_audio_sources_repo.delete_home_player_course_link(
        link_id=str(link_id),
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Course link not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _ensure_host_access(seminar: Dict[str, Any], user_id: str) -> None:
    if str(seminar["host_id"]) != user_id:
        seminar_id = seminar.get("id")
        _log_seminar_host_denied(
            user_id,
            str(seminar_id) if seminar_id else None,
        )
        raise HTTPException(status_code=403, detail="Not seminar host")


@router.get("/seminars", response_model=schemas.SeminarListResponse)
async def studio_list_seminars(current: TeacherEntryUser):
    del current
    _raise_v2_feature_disabled("Studio seminars")


@router.post("/seminars", response_model=schemas.SeminarResponse)
async def studio_create_seminar(
    payload: schemas.SeminarCreateRequest,
    current: TeacherEntryUser,
):
    del payload, current
    _raise_v2_feature_disabled("Studio seminars")


@router.get("/seminars/{seminar_id}", response_model=schemas.SeminarDetailResponse)
async def studio_get_seminar(seminar_id: UUID, current: TeacherEntryUser):
    del seminar_id, current
    _raise_v2_feature_disabled("Studio seminars")


@router.post(
    "/seminars/{seminar_id}/attendees",
    response_model=schemas.SeminarRegistrationResponse,
    status_code=status.HTTP_201_CREATED,
)
async def studio_grant_seminar_access(
    seminar_id: UUID,
    payload: schemas.SeminarAttendeeGrantRequest,
    current: TeacherEntryUser,
):
    del seminar_id, payload, current
    _raise_v2_feature_disabled("Studio seminars")


@router.delete(
    "/seminars/{seminar_id}/attendees/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def studio_revoke_seminar_access(
    seminar_id: UUID,
    user_id: UUID,
    current: TeacherEntryUser,
):
    del seminar_id, user_id, current
    _raise_v2_feature_disabled("Studio seminars")


@router.patch("/seminars/{seminar_id}", response_model=schemas.SeminarResponse)
async def studio_update_seminar(
    seminar_id: UUID,
    payload: schemas.SeminarUpdateRequest,
    current: TeacherEntryUser,
):
    del seminar_id, payload, current
    _raise_v2_feature_disabled("Studio seminars")


@router.post("/seminars/{seminar_id}/publish", response_model=schemas.SeminarResponse)
async def studio_publish_seminar(seminar_id: UUID, current: TeacherEntryUser):
    del seminar_id, current
    _raise_v2_feature_disabled("Studio seminars")


@router.post("/seminars/{seminar_id}/cancel", response_model=schemas.SeminarResponse)
async def studio_cancel_seminar(seminar_id: UUID, current: TeacherEntryUser):
    del seminar_id, current
    _raise_v2_feature_disabled("Studio seminars")


@router.post(
    "/seminars/{seminar_id}/sessions/start",
    response_model=schemas.SeminarSessionStartResponse,
)
async def studio_start_seminar_session(
    seminar_id: UUID,
    payload: schemas.SeminarSessionStartRequest,
    current: TeacherEntryUser,
):
    del seminar_id, payload, current
    _raise_v2_feature_disabled("Studio seminars")


@router.post(
    "/seminars/{seminar_id}/sessions/{session_id}/end",
    response_model=schemas.SeminarSessionResponse,
)
async def studio_end_seminar_session(
    seminar_id: UUID,
    session_id: UUID,
    current: TeacherEntryUser,
    payload: schemas.SeminarSessionEndRequest | None = None,
):
    del seminar_id, session_id, current, payload
    _raise_v2_feature_disabled("Studio seminars")


@router.post(
    "/seminars/{seminar_id}/recordings/reserve",
    response_model=schemas.SeminarRecordingResponse,
)
async def studio_reserve_recording(
    seminar_id: UUID,
    payload: schemas.SeminarRecordingReserveRequest,
    current: TeacherEntryUser,
):
    del seminar_id, payload, current
    _raise_v2_feature_disabled("Studio seminars")


@course_lesson_router.get("/courses", response_model=schemas.CourseListResponse)
async def studio_courses(current: TeacherEntryUser):
    rows = list(await courses_service.list_courses(teacher_id=str(current["id"])))
    await _apply_course_read_contract(rows)
    return _course_list_response(rows)


@course_lesson_router.get("/courses/{course_id}", response_model=schemas.Course)
async def course_meta(course_id: str, current: TeacherEntryUser):
    row = await studio_authority.get_course_for_teacher_or_404(
        course_id,
        str(current["id"]),
    )
    await _apply_course_read_contract(row)
    return _course_response(row)


@course_lesson_router.post(
    "/courses/{course_id}/public",
    response_model=schemas.CoursePublicContent,
)
async def upsert_course_public_content(
    course_id: str,
    payload: schemas.StudioCoursePublicContentUpsert,
    current: TeacherEntryUser,
):
    await studio_authority.get_course_for_teacher_or_404(
        course_id,
        str(current["id"]),
    )
    public_content = await courses_service.upsert_course_public_content(
        course_id,
        short_description=payload.short_description,
    )
    return schemas.CoursePublicContent(**public_content)


@course_lesson_router.post("/courses/{course_id}/publish", response_model=schemas.Course)
async def publish_course(course_id: str, current: TeacherEntryUser):
    try:
        row = await courses_service.publish_course(
            course_id,
            teacher_id=str(current["id"]),
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(
            status_code=502,
            detail="Kunde inte publicera kursen",
        ) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Kursen hittades inte")
    await _apply_course_read_contract(row)
    return _course_response(row)


@course_lesson_router.patch("/courses/{course_id}", response_model=schemas.Course)
async def update_course(
    course_id: str,
    payload: schemas.StudioCourseUpdate,
    current: TeacherEntryUser,
):
    await studio_authority.get_course_for_teacher_or_404(
        course_id,
        str(current["id"]),
    )
    try:
        row = await courses_service.update_course(
            course_id,
            payload.model_dump(exclude_unset=True),
            teacher_id=str(current["id"]),
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    await _apply_course_read_contract(row)
    return _course_response(row)


@course_lesson_router.delete("/courses/{course_id}")
async def delete_course(course_id: str, current: TeacherEntryUser):
    await studio_authority.get_course_for_teacher_or_404(
        course_id,
        str(current["id"]),
    )
    deleted = await courses_service.delete_course(
        course_id=course_id,
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Course not found")
    return {"deleted": True}


@course_lesson_router.get(
    "/courses/{course_id}/lessons",
    response_model=schemas.StudioLessonListResponse,
)
async def course_lessons(course_id: str, current: TeacherEntryUser):
    await studio_authority.get_course_for_teacher_or_404(
        course_id,
        str(current["id"]),
    )
    lessons = await courses_service.list_studio_course_lessons(course_id)
    return schemas.StudioLessonListResponse(
        items=[schemas.StudioLesson(**lesson) for lesson in lessons]
    )


@course_lesson_router.post(
    "/courses/{course_id}/lessons",
    response_model=schemas.StudioLessonStructure,
)
async def create_lesson_structure(
    course_id: str,
    payload: schemas.StudioLessonStructureCreate,
    current: TeacherEntryUser,
):
    await studio_authority.get_course_for_teacher_or_404(
        course_id,
        str(current["id"]),
    )
    try:
        row = await courses_service.create_lesson_structure(
            course_id=course_id,
            lesson_title=payload.lesson_title,
            position=payload.position,
            teacher_id=str(current["id"]),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create lesson structure")
    return schemas.StudioLessonStructure(**row)


@course_lesson_router.patch("/courses/{course_id}/lessons/reorder")
async def reorder_course_lessons(
    course_id: str,
    payload: schemas.LessonReorder,
    current: TeacherEntryUser,
):
    await studio_authority.get_course_for_teacher_or_404(
        course_id,
        str(current["id"]),
    )

    requested = payload.lessons
    if not requested:
        return {"ok": True}

    positions: set[int] = set()
    ordered_entries: list[schemas.LessonReorderItem] = []
    seen_ids: set[str] = set()
    for item in requested:
        lesson_id = item.id.strip()
        if not lesson_id:
            raise HTTPException(status_code=422, detail="Lesson id cannot be empty")
        if lesson_id in seen_ids:
            raise HTTPException(
                status_code=422, detail="Duplicate lesson id in reorder payload"
            )
        if item.position in positions:
            raise HTTPException(
                status_code=422, detail="Duplicate lesson position in reorder payload"
            )
        seen_ids.add(lesson_id)
        positions.add(item.position)
        ordered_entries.append(
            schemas.LessonReorderItem(id=lesson_id, position=item.position)
        )

    existing = await courses_service.list_studio_course_lessons(course_id)
    existing_ids = {
        str(row.get("id")).strip()
        for row in existing
        if row.get("id") is not None and str(row.get("id")).strip()
    }
    if seen_ids != existing_ids:
        raise HTTPException(
            status_code=422,
            detail="Reorder payload must include every lesson in the course exactly once",
        )

    ordered_entries.sort(key=lambda entry: entry.position)
    ordered_lesson_ids = [entry.id for entry in ordered_entries]
    try:
        await courses_service.reorder_lessons(
            course_id=course_id,
            ordered_lesson_ids=ordered_lesson_ids,
            teacher_id=str(current["id"]),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    return {"ok": True}


@course_lesson_router.patch(
    "/lessons/{lesson_id}/structure",
    response_model=schemas.StudioLessonStructure,
)
async def update_lesson_structure(
    lesson_id: str,
    payload: schemas.StudioLessonStructureUpdate,
    current: TeacherEntryUser,
):
    await studio_authority.get_lesson_for_teacher_or_404(
        lesson_id,
        str(current["id"]),
    )
    patch = payload.model_dump(exclude_unset=True)
    try:
        row = await courses_service.update_lesson_structure(
            lesson_id,
            patch,
            teacher_id=str(current["id"]),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return schemas.StudioLessonStructure(**row)


@course_lesson_router.get(
    "/lessons/{lesson_id}/content",
    response_model=schemas.StudioLessonContentRead,
)
async def read_lesson_content(
    lesson_id: str,
    response: Response,
    current: TeacherEntryUser,
):
    try:
        result = await courses_service.read_studio_lesson_content(
            lesson_id,
            teacher_id=str(current["id"]),
        )
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if result is None:
        raise HTTPException(status_code=404, detail="Lesson not found")
    response.headers["ETag"] = str(result["etag"])
    return schemas.StudioLessonContentRead(**result["body"])


@course_lesson_router.patch(
    "/lessons/{lesson_id}/content",
    response_model=schemas.StudioLessonContent,
)
async def update_lesson_content(
    lesson_id: str,
    payload: schemas.StudioLessonContentUpdate,
    request: Request,
    response: Response,
    current: TeacherEntryUser,
):
    try:
        row = await courses_service.update_lesson_content(
            lesson_id,
            content_markdown=payload.content_markdown,
            if_match=request.headers.get("if-match"),
            teacher_id=str(current["id"]),
        )
    except courses_service.LessonContentPreconditionRequired as exc:
        raise HTTPException(
            status_code=status.HTTP_428_PRECONDITION_REQUIRED,
            detail=str(exc),
        ) from exc
    except courses_service.LessonContentPreconditionFailed as exc:
        raise HTTPException(
            status_code=status.HTTP_412_PRECONDITION_FAILED,
            detail=str(exc),
        ) from exc
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Lesson not found")
    response.headers["ETag"] = str(row["etag"])
    return schemas.StudioLessonContent(**row["body"])


@course_lesson_router.delete("/lessons/{lesson_id}")
async def delete_lesson(lesson_id: str, current: TeacherEntryUser):
    await studio_authority.get_lesson_for_teacher_or_404(
        lesson_id,
        str(current["id"]),
    )
    deleted = await courses_service.delete_lesson(
        lesson_id=lesson_id,
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return {"deleted": True}


@router.get("/media/{media_id}")
async def media_file(
    media_id: str,
    request: Request,
    current: TeacherEntryUser,
):
    del media_id, request, current
    raise HTTPException(
        status_code=410,
        detail="Legacy media endpoint removed from canonical runtime",
    )


@router.post("/courses/{course_id}/quiz")
async def ensure_quiz(course_id: str, current: TeacherEntryUser):
    del course_id, current
    _raise_v2_feature_disabled("Studio quizzes")


@router.get("/quizzes/{quiz_id}/questions")
async def quiz_questions(quiz_id: str, current: TeacherEntryUser):
    del quiz_id, current
    _raise_v2_feature_disabled("Studio quizzes")


@router.post("/quizzes/{quiz_id}/questions")
async def create_question(
    quiz_id: str,
    payload: schemas.QuizQuestionUpsert,
    current: TeacherEntryUser,
):
    del quiz_id, payload, current
    _raise_v2_feature_disabled("Studio quizzes")


@router.put("/quizzes/{quiz_id}/questions/{question_id}")
async def update_question(
    quiz_id: str,
    question_id: str,
    payload: schemas.QuizQuestionUpsert,
    current: TeacherEntryUser,
):
    del quiz_id, question_id, payload, current
    _raise_v2_feature_disabled("Studio quizzes")


@router.delete("/quizzes/{quiz_id}/questions/{question_id}")
async def delete_question(quiz_id: str, question_id: str, current: TeacherEntryUser):
    del quiz_id, question_id, current
    _raise_v2_feature_disabled("Studio quizzes")
