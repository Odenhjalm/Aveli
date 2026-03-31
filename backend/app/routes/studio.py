import logging
import mimetypes
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated, Any, Dict
from uuid import UUID, uuid4
from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Request,
    Response,
    UploadFile,
    status,
)

from .. import models, repositories, schemas
from ..auth import CurrentUser
from ..config import settings
from ..db import get_conn
from ..permissions import TeacherUser
from ..repositories import courses as courses_repo
from ..repositories import media_assets as media_assets_repo
from ..services import (
    courses_service,
    email_service,
    lesson_playback_service,
    livekit as livekit_service,
    referral_service,
    storage_service,
)
from ..services import media_cleanup
from ..services.livekit_tokens import LiveKitTokenConfigError, build_token
from ..utils import media_signer
from ..utils.media_urls import absolutize_media_url_items, absolutize_media_urls
from ..utils.profile_media import (
    lesson_media_source_from_row,
    recording_source_from_row,
)
from .media import _build_streaming_response
from . import upload as upload_routes

router = APIRouter(prefix="/studio", tags=["studio"])
course_lesson_router = APIRouter(prefix="/studio", tags=["studio"])
lesson_media_router = APIRouter(prefix="/api/lesson-media", tags=["media"])
logger = logging.getLogger(__name__)
_LESSON_EDITOR_TRACE = os.getenv("LESSON_EDITOR_TRACE", "").lower() in {
    "1",
    "true",
    "yes",
}


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


async def _require_studio_actor(current: CurrentUser) -> dict[str, Any]:
    role = str(current.get("role_v2") or "").strip().lower()
    if current.get("is_admin") or role == "teacher":
        return current
    raise HTTPException(status_code=403, detail="Teacher permissions required")


StudioActor = Annotated[dict[str, Any], Depends(_require_studio_actor)]


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
    exact = str(value or "")
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
    if mime_type not in {"audio/mpeg", "audio/mp3", "audio/m4a", "audio/mp4", "audio/wav", "audio/x-wav"}:
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


_MAX_MEDIA_BYTES = settings.lesson_media_max_bytes
_LIVE_RECORDINGS_ROOT = "live-recordings"
_HOME_PLAYER_UPLOADS_STORAGE_BUCKET = "course-media"
_HOME_PLAYER_WAV_MIME_TYPES = {
    "audio/wav",
    "audio/x-wav",
    "audio/wave",
    "audio/vnd.wave",
}
_HOME_PLAYER_MP3_MIME_TYPES = {"audio/mpeg", "audio/mp3"}


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


async def _require_studio_lesson(lesson_id: str) -> dict[str, Any]:
    lesson = await courses_service.fetch_studio_lesson(lesson_id)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return lesson


def _preview_file_name(row: dict[str, Any]) -> str | None:
    value = str(row.get("original_name") or "").strip()
    return value or None


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

    resolved_url = str(playback.get("playback_url") or "").strip()
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


@router.get("/courses")
async def studio_courses(current: TeacherUser):
    rows = list(await courses_service.list_courses(teacher_id=str(current["id"])))
    await _apply_course_read_contract(rows)
    return {"items": rows}


@router.get("/status")
async def studio_status(current: CurrentUser):
    info = await models.teacher_status(current["id"])
    return info


@router.post(
    "/referrals/create",
    response_model=schemas.ReferralCodeCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_referral_invitation(
    payload: schemas.ReferralCodeCreateRequest,
    current: TeacherUser,
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
async def studio_certificates(current: CurrentUser, verified_only: bool = False):
    rows = await models.user_certificates(current["id"], verified_only)
    return {"items": rows}


@router.post("/certificates")
async def studio_add_certificate(
    payload: schemas.StudioCertificateCreate,
    current: CurrentUser,
):
    row = await models.add_certificate(
        current["id"],
        title=payload.title,
        status=payload.status,
        notes=payload.notes,
        evidence_url=payload.evidence_url,
    )
    return row


@course_lesson_router.post("/courses", response_model=schemas.Course)
async def create_course(payload: schemas.StudioCourseCreate, current: StudioActor):
    del current
    try:
        row = await courses_service.create_course(payload.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create course")
    return row


@lesson_media_router.post(
    "/{lesson_id}/upload-url",
    response_model=schemas.StudioLessonMediaUploadUrlResponse,
)
async def studio_issue_lesson_media_upload_url(
    lesson_id: UUID,
    payload: schemas.StudioLessonMediaUploadUrlRequest,
    current: StudioActor,
):
    del current
    lesson = await _require_studio_lesson(str(lesson_id))
    if payload.size_bytes > _MAX_MEDIA_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    course_id = str(lesson["course_id"])
    normalized_media_type = _normalize_studio_media_type(payload.media_type)
    exact_mime_type = _require_studio_mime_type(payload.mime_type)
    if normalized_media_type == "audio":
        ingest_format = _studio_audio_ingest_format(
            filename=payload.filename,
            mime_type=exact_mime_type,
        )
        object_path = upload_routes.media_paths.build_lesson_audio_source_object_path(
            course_id,
            str(lesson_id),
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
            lesson_id=str(lesson_id),
            media_kind=normalized_media_type,
            filename=payload.filename,
        )

    try:
        upload = await storage_service.storage_service.create_upload_url(
            object_path,
            content_type=exact_mime_type,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    media_asset_id = str(uuid4())
    lesson_media_row = None
    try:
        await media_assets_repo.create_media_asset(
            media_asset_id=media_asset_id,
            media_type=normalized_media_type,
            purpose="lesson_media",
            original_object_path=upload.path,
            ingest_format=ingest_format,
            state="pending_upload",
        )
        lesson_media_row = await courses_repo.create_lesson_media(
            lesson_id=str(lesson_id),
            media_asset_id=media_asset_id,
        )
    except Exception:
        if lesson_media_row is None:
            await media_assets_repo.delete_media_asset(media_asset_id)
        raise

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    return schemas.StudioLessonMediaUploadUrlResponse(
        lesson_media_id=UUID(str(lesson_media_row["lesson_media_id"])),
        lesson_id=UUID(str(lesson_id)),
        media_type=normalized_media_type,
        state="pending_upload",
        position=int(lesson_media_row["position"]),
        upload_url=upload.url,
        headers=dict(upload.headers),
        expires_at=expires_at,
    )


@lesson_media_router.post(
    "/{lesson_id}/{lesson_media_id}/complete",
    response_model=schemas.StudioLessonMediaItem,
)
async def studio_complete_lesson_media_upload(
    lesson_id: UUID,
    lesson_media_id: UUID,
    payload: schemas.StudioLessonMediaCompleteRequest,
    current: StudioActor,
):
    del current, payload
    await _require_studio_lesson(str(lesson_id))
    row = await courses_repo.get_lesson_media_for_studio(
        str(lesson_id),
        str(lesson_media_id),
    )
    if not row:
        raise HTTPException(status_code=404, detail="Lesson media not found")

    media_asset = await media_assets_repo.get_media_asset(str(row["media_asset_id"]))
    if not media_asset:
        raise HTTPException(status_code=404, detail="Media asset not found")

    original_object_path = str(media_asset.get("original_object_path") or "").strip()
    if not original_object_path:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Media asset is missing upload storage",
        )

    updated = await media_assets_repo.update_media_asset_state(
        str(row["media_asset_id"]),
        state="uploaded",
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Media asset not found")

    refreshed = await courses_repo.get_lesson_media_for_studio(
        str(lesson_id),
        str(lesson_media_id),
    )
    if not refreshed:
        raise HTTPException(status_code=404, detail="Lesson media not found")
    return schemas.StudioLessonMediaItem(**refreshed)


@lesson_media_router.get(
    "/{lesson_id}",
    response_model=schemas.StudioLessonMediaListResponse,
)
async def studio_list_lesson_media(
    lesson_id: UUID,
    current: StudioActor,
):
    del current
    await _require_studio_lesson(str(lesson_id))
    rows = await courses_service.list_studio_lesson_media(str(lesson_id))
    return schemas.StudioLessonMediaListResponse(
        items=[schemas.StudioLessonMediaItem(**dict(row)) for row in rows]
    )


@lesson_media_router.get(
    "/{lesson_id}/{lesson_media_id}/preview",
    response_model=schemas.StudioLessonMediaPreviewResponse,
)
async def studio_preview_lesson_media(
    lesson_id: UUID,
    lesson_media_id: UUID,
    current: StudioActor,
):
    del current
    await _require_studio_lesson(str(lesson_id))
    row = await courses_repo.get_lesson_media_for_studio(
        str(lesson_id),
        str(lesson_media_id),
    )
    if not row:
        raise HTTPException(status_code=404, detail="Lesson media not found")
    if row.get("preview_ready") is not True:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Preview is not ready",
        )

    playback = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id=str(lesson_media_id),
        user_id=str(current["id"]),
    )
    playback_url = str(playback.get("playback_url") or "").strip()
    expires_at = playback.get("expires_at")
    if not playback_url or not isinstance(expires_at, datetime):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Preview storage is unavailable",
        )
    return schemas.StudioLessonMediaPreviewResponse(
        lesson_media_id=lesson_media_id,
        preview_url=playback_url,
        expires_at=expires_at,
    )


@lesson_media_router.post("/previews", response_model=schemas.MediaPreviewBatchResponse)
async def studio_request_lesson_media_previews(
    payload: schemas.MediaPreviewBatchRequest,
    current: StudioActor,
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
            preview_items[lesson_media_id] = _preview_failure_item(
                media_type="",
                row={},
                failure_reason="not_found",
            )
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


@lesson_media_router.patch("/{lesson_id}/reorder")
async def studio_reorder_lesson_media(
    lesson_id: UUID,
    payload: schemas.StudioLessonMediaReorder,
    current: StudioActor,
):
    del current
    await _require_studio_lesson(str(lesson_id))
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


@lesson_media_router.delete("/{lesson_id}/{lesson_media_id}")
async def studio_delete_lesson_media(
    lesson_id: UUID,
    lesson_media_id: UUID,
    current: StudioActor,
):
    del current
    await _require_studio_lesson(str(lesson_id))
    deleted = await courses_repo.delete_lesson_media(
        str(lesson_id),
        str(lesson_media_id),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Lesson media not found")

    media_asset_id = str(deleted.get("media_asset_id") or "").strip()
    if media_asset_id and not await courses_repo.lesson_media_asset_is_linked(media_asset_id):
        await media_assets_repo.delete_media_asset(media_asset_id)
    return {"deleted": True}


@router.post("/lessons/{lesson_id}/media/presign")
async def presign_lesson_media_upload(
    lesson_id: UUID,
    payload: schemas.LessonMediaPresignRequest,
    current: TeacherUser,
):
    upload_routes._raise_legacy_lesson_upload_disabled()

    # Ensure lesson exists and current user owns the course.
    lesson_id_str = str(lesson_id)
    lesson = await courses_service.fetch_studio_lesson(lesson_id_str)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    _, course_id = await courses_service.lesson_course_ids(lesson_id_str)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]), course_id=course_id, lesson_id=lesson_id_str
        )
        raise HTTPException(status_code=403, detail="Not course owner")

    detected_kind = _detect_kind(
        payload.content_type or mimetypes.guess_type(payload.filename or "")[0]
    )
    if (
        detected_kind == "audio"
        or (payload.media_type or "").strip().lower() == "audio"
    ):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Audio uploads must use the media pipeline",
        )

    bucket = "course-media"
    safe_name = Path(payload.filename or "").name.strip() or "media"
    path = upload_routes.media_paths.validate_new_upload_object_path(
        f"lessons/{lesson_id}/{safe_name}"
    )
    upload = await storage_service.storage_service.create_upload_url(
        path,
        content_type=payload.content_type,
        upsert=True,
        cache_seconds=settings.media_public_cache_seconds,
    )
    return {
        "method": "PUT",
        "url": upload.url,
        "headers": upload.headers,
        "storage_bucket": bucket,
        "storage_path": upload.path,
        "expires_in": upload.expires_in,
    }


@router.post("/lessons/{lesson_id}/media/complete")
async def complete_lesson_media_upload(
    request: Request,
    lesson_id: UUID,
    payload: schemas.LessonMediaUploadCompleteRequest,
    current: TeacherUser,
):
    upload_routes._raise_legacy_lesson_upload_disabled()

    # Ensure lesson exists and current user owns the course.
    lesson_id_str = str(lesson_id)
    lesson = await courses_service.fetch_studio_lesson(lesson_id_str)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    _, course_id = await courses_service.lesson_course_ids(lesson_id_str)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]), course_id=course_id, lesson_id=lesson_id_str
        )
        raise HTTPException(status_code=403, detail="Not course owner")

    kind = _detect_kind(payload.content_type)
    if kind not in {"image", "video", "audio", "document", "pdf"}:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported media type",
        )
    if kind == "audio":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Audio uploads must use the media pipeline",
        )
    expected_bucket = "course-media"
    if payload.storage_bucket != expected_bucket:
        raise HTTPException(
            status_code=400,
            detail={"storage_bucket": "must equal course-media"},
        )

    if payload.byte_size <= 0:
        raise HTTPException(status_code=422, detail="byte_size must be greater than 0")

    original_name = (payload.original_name or "").strip() or Path(
        payload.storage_path
    ).name
    row = await upload_routes._persist_lesson_media(
        owner_id=str(current["id"]),
        lesson_id=str(lesson_id),
        storage_path=payload.storage_path,
        original_name=original_name,
        content_type=payload.content_type,
        size=payload.byte_size,
        checksum=payload.checksum,
        storage_bucket=payload.storage_bucket,
        course_id=str(course_id),
    )
    row["content_type"] = payload.content_type
    row["byte_size"] = payload.byte_size
    row["original_name"] = original_name
    if kind in {"document", "pdf"}:
        row["media_state"] = "ready"
    media_signer.attach_media_links(row)
    absolutize_media_urls(row, base_url=str(request.base_url))
    return row


@router.get("/lessons/{lesson_id}/media")
async def list_lesson_media(request: Request, lesson_id: UUID, current: TeacherUser):
    lesson_id_str = str(lesson_id)
    _, course_id = await courses_service.lesson_course_ids(lesson_id_str)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]), course_id=course_id, lesson_id=lesson_id_str
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    items = list(
        await courses_service.list_lesson_media(
            str(lesson_id),
            mode="editor_preview",
        )
    )
    absolutize_media_url_items(items, base_url=str(request.base_url))
    return {"items": items}


@router.get(
    "/profile/media",
    response_model=schemas.TeacherProfileMediaListResponse,
)
async def studio_profile_media(request: Request, current: TeacherUser):
    teacher_id = str(current["id"])
    items = await repositories.list_teacher_profile_media(teacher_id)
    lesson_sources = await repositories.list_teacher_lesson_media_sources(teacher_id)
    recording_sources = await repositories.list_teacher_seminar_recording_sources(
        teacher_id
    )
    absolutize_media_url_items(items, base_url=str(request.base_url))
    absolutize_media_url_items(lesson_sources, base_url=str(request.base_url))
    absolutize_media_url_items(recording_sources, base_url=str(request.base_url))
    return schemas.TeacherProfileMediaListResponse(
        items=[schemas.TeacherProfileMediaItem(**row) for row in items],
        lesson_media_sources=[
            lesson_media_source_from_row(row) for row in lesson_sources
        ],
        seminar_recording_sources=[
            recording_source_from_row(row) for row in recording_sources
        ],
    )


@router.post(
    "/profile/media",
    response_model=schemas.TeacherProfileMediaItem,
    status_code=201,
)
async def studio_create_profile_media(
    request: Request,
    payload: schemas.TeacherProfileMediaCreate,
    current: TeacherUser,
):
    row = await repositories.create_teacher_profile_media(
        teacher_id=str(current["id"]),
        media_kind=payload.media_kind.value,
        lesson_media_id=(
            str(payload.lesson_media_id) if payload.lesson_media_id else None
        ),
        seminar_recording_id=(
            str(payload.seminar_recording_id)
            if payload.seminar_recording_id
            else None
        ),
        external_url=payload.external_url,
        title=payload.title,
        description=payload.description,
        cover_media_id=str(payload.cover_media_id) if payload.cover_media_id else None,
        cover_image_url=payload.cover_image_url,
        position=payload.position,
        is_published=payload.is_published,
        enabled_for_home_player=payload.enabled_for_home_player,
    )
    if not row:
        raise HTTPException(
            status_code=400, detail="Failed to create profile media item"
        )
    absolutize_media_url_items([row], base_url=str(request.base_url))
    return schemas.TeacherProfileMediaItem(**row)


@router.patch(
    "/profile/media/{item_id}",
    response_model=schemas.TeacherProfileMediaItem,
)
async def studio_update_profile_media(
    request: Request,
    item_id: UUID,
    payload: schemas.TeacherProfileMediaUpdate,
    current: TeacherUser,
):
    if payload.title is not None and not payload.title.strip():
        raise HTTPException(status_code=422, detail="title cannot be empty")

    previous_cover_media_id: str | None = None
    if payload.cover_media_id is not None:
        existing = await repositories.get_teacher_profile_media(
            item_id=str(item_id),
            teacher_id=str(current["id"]),
        )
        if not existing:
            raise HTTPException(status_code=404, detail="Profile media item not found")
        if existing.get("cover_media_id"):
            previous_cover_media_id = str(existing["cover_media_id"])

    fields: Dict[str, Any] = {}
    if payload.title is not None:
        fields["title"] = payload.title
    if payload.description is not None:
        fields["description"] = payload.description
    if payload.cover_media_id is not None:
        fields["cover_media_id"] = str(payload.cover_media_id)
    if payload.cover_image_url is not None:
        fields["cover_image_url"] = payload.cover_image_url
    if payload.position is not None:
        fields["position"] = payload.position
    if payload.is_published is not None:
        fields["is_published"] = payload.is_published
    if payload.enabled_for_home_player is not None:
        fields["enabled_for_home_player"] = payload.enabled_for_home_player

    row = await repositories.update_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
        fields=fields,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    current_cover_media_id = (
        str(row["cover_media_id"]) if row.get("cover_media_id") else None
    )
    if previous_cover_media_id and previous_cover_media_id != current_cover_media_id:
        await models.cleanup_media_object(previous_cover_media_id)
    absolutize_media_url_items([row], base_url=str(request.base_url))
    return schemas.TeacherProfileMediaItem(**row)


@router.delete("/profile/media/{item_id}", status_code=204)
async def studio_delete_profile_media(item_id: UUID, current: TeacherUser):
    existing = await repositories.get_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    cover_media_id = (
        str(existing["cover_media_id"]) if existing.get("cover_media_id") else None
    )
    deleted = await repositories.delete_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    if cover_media_id:
        await models.cleanup_media_object(cover_media_id)
    return Response(status_code=204)


@router.get(
    "/home-player/library",
    response_model=schemas.HomePlayerLibraryResponse,
)
async def studio_home_player_library(current: TeacherUser):
    teacher_id = str(current["id"])
    uploads = await repositories.list_home_player_uploads(teacher_id)
    links = await repositories.list_home_player_course_links(teacher_id)
    sources = await repositories.list_teacher_lesson_media_sources(teacher_id)
    course_media: list[dict[str, Any]] = []
    for source in sources:
        kind = str(source.get("kind") or "").lower()
        content_type = str(source.get("content_type") or "").lower()
        if kind.startswith("audio") or kind.startswith("video"):
            course_media.append(source)
        elif content_type.startswith("audio/") or content_type.startswith("video/"):
            course_media.append(source)

    return schemas.HomePlayerLibraryResponse(
        uploads=[schemas.HomePlayerUploadItem(**row) for row in uploads],
        course_links=[schemas.HomePlayerCourseLinkItem(**row) for row in links],
        course_media=[
            schemas.TeacherProfileLessonSource(**row) for row in course_media
        ],
    )


@router.post(
    "/home-player/uploads/upload-url",
    response_model=schemas.HomePlayerUploadUrlResponse,
)
async def studio_home_player_upload_url(
    payload: schemas.HomePlayerUploadUrlRequest,
    current: TeacherUser,
):
    teacher_id = str(current["id"])
    mime_type = str(payload.mime_type or "").strip().lower()
    if not mime_type:
        raise HTTPException(status_code=422, detail="mime_type is required")

    normalized_ext = Path(payload.filename).suffix.lower().lstrip(".")
    if normalized_ext == "wav" or mime_type in _HOME_PLAYER_WAV_MIME_TYPES:
        raise HTTPException(
            status_code=422,
            detail="WAV uploads must use the media pipeline",
        )

    is_mp3 = normalized_ext == "mp3" or mime_type in _HOME_PLAYER_MP3_MIME_TYPES
    is_mp4 = normalized_ext == "mp4" or mime_type == "video/mp4"
    if not (is_mp3 or is_mp4):
        raise HTTPException(status_code=415, detail="Unsupported media type")
    mime_type = "audio/mpeg" if is_mp3 else "video/mp4"

    max_bytes = int(settings.lesson_media_max_bytes)
    if payload.size_bytes > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    await _assert_storage_bucket_exists(_HOME_PLAYER_UPLOADS_STORAGE_BUCKET)
    storage_client = storage_service.get_storage_service(
        _HOME_PLAYER_UPLOADS_STORAGE_BUCKET
    )
    if not storage_client.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        )

    safe_name = Path(payload.filename).name.strip() or "media"
    token = uuid4().hex
    object_path = upload_routes.media_paths.validate_new_upload_object_path(
        (Path("home-player") / teacher_id / f"{token}_{safe_name}").as_posix()
    )

    try:
        upload = await storage_client.create_upload_url(
            object_path,
            content_type=mime_type,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Home upload signing failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    return schemas.HomePlayerUploadUrlResponse(
        upload_url=upload.url,
        object_path=upload.path,
        headers=dict(upload.headers),
        expires_at=expires_at,
    )


@router.post(
    "/home-player/uploads/upload-url/refresh",
    response_model=schemas.HomePlayerUploadUrlResponse,
)
async def studio_refresh_home_player_upload_url(
    payload: schemas.HomePlayerUploadUrlRefreshRequest,
    current: TeacherUser,
):
    teacher_id = str(current["id"])
    object_path = str(payload.object_path or "").strip().lstrip("/")
    if not object_path:
        raise HTTPException(status_code=422, detail="object_path is required")
    try:
        object_path = upload_routes.media_paths.validate_new_upload_object_path(
            object_path
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    expected_prefix = f"home-player/{teacher_id}/"
    if not object_path.startswith(expected_prefix):
        raise HTTPException(status_code=403, detail="Access denied")

    mime_type = str(payload.mime_type or "").strip().lower()
    if not mime_type:
        raise HTTPException(status_code=422, detail="mime_type is required")
    if mime_type in _HOME_PLAYER_WAV_MIME_TYPES:
        raise HTTPException(
            status_code=422,
            detail="WAV uploads must use the media pipeline",
        )

    normalized_ext = Path(object_path).suffix.lower().lstrip(".")
    is_mp3 = normalized_ext == "mp3" or mime_type in _HOME_PLAYER_MP3_MIME_TYPES
    is_mp4 = normalized_ext == "mp4" or mime_type == "video/mp4"
    if not (is_mp3 or is_mp4):
        raise HTTPException(status_code=415, detail="Unsupported media type")
    mime_type = "audio/mpeg" if is_mp3 else "video/mp4"

    await _assert_storage_bucket_exists(_HOME_PLAYER_UPLOADS_STORAGE_BUCKET)
    storage_client = storage_service.get_storage_service(
        _HOME_PLAYER_UPLOADS_STORAGE_BUCKET
    )
    if not storage_client.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        )

    try:
        upload = await storage_client.create_upload_url(
            object_path,
            content_type=mime_type,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        logger.warning("Home upload signing refresh failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in)
    return schemas.HomePlayerUploadUrlResponse(
        upload_url=upload.url,
        object_path=upload.path,
        headers=dict(upload.headers),
        expires_at=expires_at,
    )


@router.post(
    "/home-player/uploads",
    response_model=schemas.HomePlayerUploadItem,
    status_code=status.HTTP_201_CREATED,
)
async def studio_create_home_player_upload(
    payload: schemas.HomePlayerUploadCreate,
    current: TeacherUser,
):
    teacher_id = str(current["id"])
    normalized_title = (payload.title or "").strip()
    if not normalized_title:
        raise HTTPException(status_code=422, detail="title is required")

    if payload.media_asset_id is not None:
        media_asset = await repositories.get_media_asset(str(payload.media_asset_id))
        if not media_asset:
            raise HTTPException(status_code=404, detail="Media not found")
        if str(media_asset.get("owner_id") or "") != teacher_id:
            raise HTTPException(status_code=403, detail="Access denied")
        if str(media_asset.get("purpose") or "").lower() != "home_player_audio":
            raise HTTPException(status_code=422, detail="Invalid media purpose")
        if str(media_asset.get("media_type") or "").lower() != "audio":
            raise HTTPException(status_code=422, detail="Invalid media type")
        created = await repositories.create_home_player_upload(
            teacher_id=teacher_id,
            media_id=None,
            media_asset_id=str(payload.media_asset_id),
            title=normalized_title,
            kind="audio",
            active=bool(payload.active),
        )
        if not created:
            raise HTTPException(status_code=400, detail="Failed to create upload")
        return schemas.HomePlayerUploadItem(**created)

    storage_bucket = (
        payload.storage_bucket or ""
    ).strip() or _HOME_PLAYER_UPLOADS_STORAGE_BUCKET
    if storage_bucket != _HOME_PLAYER_UPLOADS_STORAGE_BUCKET:
        raise HTTPException(status_code=422, detail="Unsupported storage bucket")
    await _assert_storage_bucket_exists(storage_bucket)

    storage_path = (payload.storage_path or "").strip().lstrip("/")
    if not storage_path:
        raise HTTPException(status_code=422, detail="storage_path is required")
    try:
        storage_path = upload_routes.media_paths.validate_new_upload_object_path(
            storage_path
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    expected_prefix = f"home-player/{teacher_id}/"
    if not storage_path.startswith(expected_prefix):
        raise HTTPException(status_code=403, detail="Access denied")
    await upload_routes._assert_storage_object_exists(
        storage_bucket=storage_bucket,
        storage_path=storage_path,
    )

    content_type = (
        (payload.content_type or "").strip()
        or mimetypes.guess_type(storage_path)[0]
        or "application/octet-stream"
    )
    normalized_type = content_type.lower()
    normalized_ext = Path(storage_path).suffix.lower().lstrip(".")
    if normalized_ext == "wav" or normalized_type in _HOME_PLAYER_WAV_MIME_TYPES:
        raise HTTPException(
            status_code=422, detail="WAV uploads must use the media pipeline"
        )

    is_mp3 = normalized_ext == "mp3" or normalized_type in _HOME_PLAYER_MP3_MIME_TYPES
    is_mp4 = normalized_ext == "mp4" or normalized_type == "video/mp4"
    if not (is_mp3 or is_mp4):
        raise HTTPException(status_code=415, detail="Unsupported media type")
    kind = "audio" if is_mp3 else "video"
    content_type = "audio/mpeg" if is_mp3 else "video/mp4"

    max_bytes = int(settings.lesson_media_max_bytes)
    byte_size = int(payload.byte_size or 0)
    if byte_size <= 0:
        raise HTTPException(status_code=422, detail="byte_size is required")
    if byte_size > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large",
        )

    media_object = await models.create_media_object(
        owner_id=teacher_id,
        storage_path=storage_path,
        storage_bucket=storage_bucket,
        content_type=content_type,
        byte_size=byte_size,
        checksum=None,
        original_name=(payload.original_name or "").strip() or Path(storage_path).name,
    )
    if not media_object:
        raise HTTPException(status_code=500, detail="Failed to persist media")

    created = await repositories.create_home_player_upload(
        teacher_id=teacher_id,
        media_id=str(media_object["id"]),
        media_asset_id=None,
        title=normalized_title,
        kind=kind,
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
    current: TeacherUser,
):
    if payload.title is not None and not payload.title.strip():
        raise HTTPException(status_code=422, detail="title cannot be empty")
    fields: dict[str, Any] = {}
    if payload.title is not None:
        fields["title"] = payload.title
    if payload.active is not None:
        fields["active"] = payload.active
    row = await repositories.update_home_player_upload(
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
async def studio_delete_home_player_upload(upload_id: UUID, current: TeacherUser):
    deleted = await repositories.delete_home_player_upload(
        upload_id=str(upload_id),
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Home upload not found")
    media_id = deleted.get("media_id")
    if media_id:
        await models.cleanup_media_object(str(media_id))
    media_asset_id = deleted.get("media_asset_id")
    if media_asset_id:
        await media_cleanup.delete_media_asset_and_objects(media_id=str(media_asset_id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/home-player/course-links",
    response_model=schemas.HomePlayerCourseLinkItem,
    status_code=status.HTTP_201_CREATED,
)
async def studio_create_home_player_course_link(
    payload: schemas.HomePlayerCourseLinkCreate,
    current: TeacherUser,
):
    teacher_id = str(current["id"])
    title = (payload.title or "").strip()
    if not title:
        raise HTTPException(status_code=422, detail="title is required")

    resolved = await repositories.resolve_lesson_media_course_owner(
        str(payload.lesson_media_id),
    )
    if not resolved:
        raise HTTPException(status_code=404, detail="Lesson media not found")
    if str(resolved.get("teacher_id")) != teacher_id:
        raise HTTPException(status_code=403, detail="Not course owner")

    kind = str(resolved.get("kind") or "").lower()
    content_type = str(resolved.get("content_type") or "").lower()
    if not (
        kind.startswith("audio")
        or kind.startswith("video")
        or content_type.startswith("audio/")
        or content_type.startswith("video/")
    ):
        raise HTTPException(status_code=422, detail="Only audio/video can be linked")

    course_title_snapshot = str(resolved.get("course_title") or "").strip()
    row = await repositories.upsert_home_player_course_link(
        teacher_id=teacher_id,
        lesson_media_id=str(payload.lesson_media_id),
        title=title,
        course_title_snapshot=course_title_snapshot,
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
    current: TeacherUser,
):
    if payload.title is not None and not payload.title.strip():
        raise HTTPException(status_code=422, detail="title cannot be empty")

    fields: dict[str, Any] = {}
    if payload.enabled is not None:
        fields["enabled"] = payload.enabled
    if payload.title is not None:
        fields["title"] = payload.title

    row = await repositories.update_home_player_course_link(
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
async def studio_delete_home_player_course_link(link_id: UUID, current: TeacherUser):
    deleted = await repositories.delete_home_player_course_link(
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
async def studio_list_seminars(current: TeacherUser):
    rows = await repositories.list_host_seminars(str(current["id"]))
    items = [_seminar_from_row(row) for row in rows]
    return schemas.SeminarListResponse(items=items)


@router.post("/seminars", response_model=schemas.SeminarResponse)
async def studio_create_seminar(
    payload: schemas.SeminarCreateRequest,
    current: TeacherUser,
):
    row = await repositories.create_seminar(
        host_id=str(current["id"]),
        title=payload.title,
        description=payload.description,
        scheduled_at=payload.scheduled_at.isoformat() if payload.scheduled_at else None,
        duration_minutes=payload.duration_minutes,
    )
    return _seminar_from_row(row)


@router.get("/seminars/{seminar_id}", response_model=schemas.SeminarDetailResponse)
async def studio_get_seminar(seminar_id: UUID, current: TeacherUser):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))
    sessions = await repositories.list_seminar_sessions(str(seminar_id))
    attendees = await repositories.list_seminar_attendees(str(seminar_id))
    recordings = await repositories.list_seminar_recordings(str(seminar_id))
    return schemas.SeminarDetailResponse(
        seminar=_seminar_from_row(seminar),
        sessions=[_session_from_row(row) for row in sessions],
        attendees=[_attendee_from_row(row) for row in attendees],
        recordings=[_recording_from_row(row) for row in recordings],
    )


@router.post(
    "/seminars/{seminar_id}/attendees",
    response_model=schemas.SeminarRegistrationResponse,
    status_code=status.HTTP_201_CREATED,
)
async def studio_grant_seminar_access(
    seminar_id: UUID,
    payload: schemas.SeminarAttendeeGrantRequest,
    current: TeacherUser,
):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))
    row = await repositories.register_attendee(
        seminar_id=str(seminar_id),
        user_id=str(payload.user_id),
        role=payload.role or "participant",
        invite_status=payload.invite_status or "accepted",
    )
    return _attendee_from_row(row)


@router.delete(
    "/seminars/{seminar_id}/attendees/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def studio_revoke_seminar_access(
    seminar_id: UUID,
    user_id: UUID,
    current: TeacherUser,
):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))
    removed = await repositories.unregister_attendee(
        seminar_id=str(seminar_id),
        user_id=str(user_id),
    )
    if not removed:
        raise HTTPException(status_code=404, detail="Attendee not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/seminars/{seminar_id}", response_model=schemas.SeminarResponse)
async def studio_update_seminar(
    seminar_id: UUID,
    payload: schemas.SeminarUpdateRequest,
    current: TeacherUser,
):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))

    fields: Dict[str, Any] = {}
    if payload.title is not None:
        fields["title"] = payload.title
    if payload.description is not None:
        fields["description"] = payload.description
    if payload.scheduled_at is not None:
        fields["scheduled_at"] = payload.scheduled_at.isoformat()
    if payload.duration_minutes is not None:
        fields["duration_minutes"] = payload.duration_minutes

    row = await repositories.update_seminar(
        seminar_id=str(seminar_id),
        host_id=str(current["id"]),
        fields=fields,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Seminar not found")
    return _seminar_from_row(row)


@router.post("/seminars/{seminar_id}/publish", response_model=schemas.SeminarResponse)
async def studio_publish_seminar(seminar_id: UUID, current: TeacherUser):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))
    if seminar["status"] not in ("draft", "canceled"):
        raise HTTPException(status_code=409, detail="Seminar already published")
    row = await repositories.set_seminar_status(
        seminar_id=str(seminar_id),
        host_id=str(current["id"]),
        status="scheduled",
    )
    if not row:
        raise HTTPException(status_code=500, detail="Failed to update seminar status")
    return _seminar_from_row(row)


@router.post("/seminars/{seminar_id}/cancel", response_model=schemas.SeminarResponse)
async def studio_cancel_seminar(seminar_id: UUID, current: TeacherUser):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))
    if seminar["status"] == "canceled":
        return _seminar_from_row(seminar)
    row = await repositories.set_seminar_status(
        seminar_id=str(seminar_id),
        host_id=str(current["id"]),
        status="canceled",
    )
    if not row:
        raise HTTPException(status_code=500, detail="Failed to cancel seminar")
    return _seminar_from_row(row)


@router.post(
    "/seminars/{seminar_id}/sessions/start",
    response_model=schemas.SeminarSessionStartResponse,
)
async def studio_start_seminar_session(
    seminar_id: UUID,
    payload: schemas.SeminarSessionStartRequest,
    current: TeacherUser,
):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))

    session = None
    if payload.session_id:
        session = await repositories.get_seminar_session(str(payload.session_id))
        if not session or str(session["seminar_id"]) != str(seminar["id"]):
            raise HTTPException(status_code=404, detail="Seminar session not found")
        if session["status"] == "live":
            raise HTTPException(status_code=409, detail="Session already live")
    if session is None:
        metadata = {"created_by": str(current["id"])}
        session = await repositories.create_seminar_session(
            seminar_id=str(seminar_id),
            status="scheduled",
            scheduled_at=seminar.get("scheduled_at"),
            livekit_room=seminar.get("livekit_room"),
            livekit_sid=None,
            metadata=metadata,
        )

    livekit_room = (
        session.get("livekit_room")
        or seminar.get("livekit_room")
        or f"seminar-{seminar['id']}"
    )
    metadata = dict(session.get("metadata") or {})
    metadata.update(
        {
            "started_by": str(current["id"]),
            "started_at": datetime.now(timezone.utc).isoformat(),
        }
    )
    if payload.metadata:
        metadata.update(payload.metadata)

    try:
        await livekit_service.create_room(
            livekit_room,
            metadata={
                "seminar_id": str(seminar_id),
                "session_id": str(session["id"]),
                **(payload.metadata or {}),
            },
            max_participants=payload.max_participants,
        )
    except livekit_service.LiveKitRESTError as exc:
        logger.warning("LiveKit create_room failed: %s", exc)

    now = datetime.now(timezone.utc)
    updated_session = await repositories.update_seminar_session(
        session_id=str(session["id"]),
        fields={
            "status": "live",
            "started_at": now,
            "livekit_room": livekit_room,
            "metadata": metadata,
        },
    )

    if seminar.get("livekit_room") != livekit_room:
        await repositories.update_seminar(
            seminar_id=str(seminar_id),
            host_id=str(current["id"]),
            fields={"livekit_room": livekit_room},
        )

    if not settings.livekit_ws_url:
        raise HTTPException(status_code=503, detail="LiveKit configuration missing")

    try:
        token = build_token(
            seminar_id=seminar["id"],
            session_id=updated_session["id"],
            user_id=current["id"],
            identity=f"{current['id']}-host",
            display_name=current.get("display_name") or current.get("email"),
            avatar_url=current.get("photo_url"),
            role="host",
            room_name=livekit_room,
            can_create_room=True,
        )
    except LiveKitTokenConfigError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return schemas.SeminarSessionStartResponse(
        session=_session_from_row(updated_session),
        ws_url=settings.livekit_ws_url,
        token=token,
    )


@router.post(
    "/seminars/{seminar_id}/sessions/{session_id}/end",
    response_model=schemas.SeminarSessionResponse,
)
async def studio_end_seminar_session(
    seminar_id: UUID,
    session_id: UUID,
    current: TeacherUser,
    payload: schemas.SeminarSessionEndRequest | None = None,
):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))

    session = await repositories.get_seminar_session(str(session_id))
    if not session or str(session["seminar_id"]) != str(seminar["id"]):
        raise HTTPException(status_code=404, detail="Seminar session not found")

    livekit_room = session.get("livekit_room") or seminar.get("livekit_room")
    if livekit_room:
        try:
            await livekit_service.end_room(
                livekit_room,
                reason=payload.reason if payload else None,
            )
        except livekit_service.LiveKitRESTError as exc:
            logger.warning("LiveKit end_room failed: %s", exc)

    now = datetime.now(timezone.utc)
    metadata = dict(session.get("metadata") or {})
    metadata.update(
        {
            "ended_by": str(current["id"]),
            "ended_at": now.isoformat(),
        }
    )
    updated_session = await repositories.update_seminar_session(
        session_id=str(session_id),
        fields={
            "status": "ended",
            "ended_at": now,
            "metadata": metadata,
        },
    )
    return _session_from_row(updated_session)


@router.post(
    "/seminars/{seminar_id}/recordings/reserve",
    response_model=schemas.SeminarRecordingResponse,
)
async def studio_reserve_recording(
    seminar_id: UUID,
    payload: schemas.SeminarRecordingReserveRequest,
    current: TeacherUser,
):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(status_code=404, detail="Seminar not found")
    _ensure_host_access(seminar, str(current["id"]))

    session_row = None
    if payload.session_id:
        session_row = await repositories.get_seminar_session(str(payload.session_id))
        if session_row and str(session_row["seminar_id"]) != str(seminar["id"]):
            logger.warning(
                "Recording reserve: session %s does not belong to seminar %s",
                payload.session_id,
                seminar_id,
            )
            session_row = None
        if not session_row:
            logger.info(
                "Recording reserve: session %s not found, falling back to latest session",
                payload.session_id,
            )
    if session_row is None:
        session_row = await repositories.get_latest_session(str(seminar_id))

    recordings_dir = Path(settings.media_root) / _LIVE_RECORDINGS_ROOT / str(seminar_id)
    recordings_dir.mkdir(parents=True, exist_ok=True)

    extension = (payload.extension or "mp4").strip().lower()
    extension = extension.lstrip(".")
    if not extension or any(ch for ch in extension if not ch.isalnum()):
        extension = "mp4"

    filename = f"{uuid4().hex}.{extension}"
    disk_path = recordings_dir / filename
    if not disk_path.exists():
        try:
            disk_path.touch()
        except OSError as exc:
            logger.warning("Failed to create recording placeholder file: %s", exc)

    asset_relative_path = f"{_LIVE_RECORDINGS_ROOT}/{seminar_id}/{filename}"

    session_id_value = None
    if payload.session_id:
        session_id_value = str(payload.session_id)
    elif session_row:
        session_id_value = str(session_row["id"])

    metadata = {
        "placeholder": True,
        "created_by": str(current["id"]),
        "reserved_at": datetime.now(timezone.utc).isoformat(),
    }
    if session_id_value:
        metadata["session_id"] = session_id_value

    row = await repositories.upsert_recording(
        seminar_id=str(seminar_id),
        session_id=session_id_value,
        asset_url=asset_relative_path,
        status="pending",
        duration_seconds=None,
        byte_size=0,
        metadata=metadata,
    )

    return _recording_from_row(row)


@course_lesson_router.get("/courses", response_model=schemas.CourseListResponse)
async def studio_courses(current: StudioActor):
    del current
    rows = list(await courses_service.list_courses())
    return schemas.CourseListResponse(items=[schemas.Course(**row) for row in rows])


@course_lesson_router.get("/courses/{course_id}", response_model=schemas.Course)
async def course_meta(course_id: str, current: StudioActor):
    del current
    row = await courses_service.fetch_course(course_id=course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    return schemas.Course(**row)


@course_lesson_router.post(
    "/courses/{course_id}/public",
    response_model=schemas.CoursePublicContent,
)
async def upsert_course_public_content(
    course_id: str,
    payload: schemas.StudioCoursePublicContentUpsert,
    current: StudioActor,
):
    del current
    row = await courses_service.fetch_course(course_id=course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    public_content = await courses_service.upsert_course_public_content(
        course_id,
        short_description=payload.short_description,
    )
    return schemas.CoursePublicContent(**public_content)


@course_lesson_router.patch("/courses/{course_id}", response_model=schemas.Course)
async def update_course(
    course_id: str,
    payload: schemas.StudioCourseUpdate,
    current: StudioActor,
):
    del current
    try:
        row = await courses_service.update_course(
            course_id,
            payload.model_dump(exclude_unset=True),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    return schemas.Course(**row)


@course_lesson_router.delete("/courses/{course_id}")
async def delete_course(course_id: str, current: StudioActor):
    del current
    deleted = await courses_service.delete_course(course_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Course not found")
    return {"deleted": True}


@course_lesson_router.get(
    "/courses/{course_id}/lessons",
    response_model=schemas.StudioLessonListResponse,
)
async def course_lessons(course_id: str, current: StudioActor):
    del current
    course = await courses_service.fetch_course(course_id=course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    lessons = await courses_service.list_studio_course_lessons(course_id)
    return schemas.StudioLessonListResponse(
        items=[schemas.StudioLesson(**lesson) for lesson in lessons]
    )


@course_lesson_router.patch("/courses/{course_id}/lessons/reorder")
async def reorder_course_lessons(
    course_id: str,
    payload: schemas.LessonReorder,
    current: StudioActor,
):
    del current
    course = await courses_service.fetch_course(course_id=course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

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
        await courses_service.reorder_lessons(course_id, ordered_lesson_ids)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    return {"ok": True}


@course_lesson_router.post("/lessons", response_model=schemas.StudioLesson)
async def create_lesson(
    payload: schemas.StudioLessonCreate,
    current: StudioActor,
):
    del current
    course_id = str(payload.course_id)
    course = await courses_service.fetch_course(course_id=course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    lesson_id = str(payload.id) if payload.id else None
    try:
        row = await courses_service.create_lesson(
            course_id,
            lesson_title=payload.lesson_title,
            content_markdown=payload.content_markdown,
            position=payload.position,
            lesson_id=lesson_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create lesson")
    return schemas.StudioLesson(**row)


@course_lesson_router.patch("/lessons/{lesson_id}", response_model=schemas.StudioLesson)
async def update_lesson(
    lesson_id: str,
    payload: schemas.StudioLessonUpdate,
    current: StudioActor,
):
    del current
    existing = await courses_service.fetch_studio_lesson(lesson_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Lesson not found")
    patch = payload.model_dump(exclude_unset=True)

    if _LESSON_EDITOR_TRACE:
        incoming = patch.get("content_markdown")
        stored_before = existing.get("content_markdown")
        incoming_str = incoming if isinstance(incoming, str) else None
        stored_str = stored_before if isinstance(stored_before, str) else None
        logger.info(
            "[LessonTrace] update_lesson.before lesson_id=%s incoming_len=%s stored_len=%s "
            "equal=%s incoming=%s stored=%s",
            lesson_id,
            0 if incoming_str is None else len(incoming_str),
            0 if stored_str is None else len(stored_str),
            incoming_str == stored_str,
            _visible_lesson_text(incoming_str),
            _visible_lesson_text(stored_str),
        )

    lesson_payload = {"id": lesson_id, **patch}
    try:
        row = await courses_service.upsert_lesson(str(existing["course_id"]), lesson_payload)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=400, detail="Failed to update lesson")

    if _LESSON_EDITOR_TRACE:
        stored_after = row.get("content_markdown")
        stored_after_str = stored_after if isinstance(stored_after, str) else None
        logger.info(
            "[LessonTrace] update_lesson.after lesson_id=%s stored_len=%s stored=%s",
            lesson_id,
            0 if stored_after_str is None else len(stored_after_str),
            _visible_lesson_text(stored_after_str),
        )

    return schemas.StudioLesson(**row)


@course_lesson_router.delete("/lessons/{lesson_id}")
async def delete_lesson(lesson_id: str, current: StudioActor):
    del current
    deleted = await courses_service.delete_lesson(lesson_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return {"deleted": True}


@router.post("/lessons/{lesson_id}/media")
async def upload_media(
    lesson_id: str,
    current: TeacherUser,
    file: UploadFile = File(...),
):
    upload_routes._raise_legacy_lesson_upload_disabled()

    owner = current["id"]
    owner_id = str(owner)
    _, course_id = await courses_service.lesson_course_ids(lesson_id)
    if not course_id or not await models.is_course_owner(owner, course_id):
        _log_course_owner_denied(
            owner_id,
            course_id=str(course_id) if course_id else None,
        )
        raise HTTPException(status_code=403, detail="Not course owner")

    lesson_row = await courses_service.fetch_studio_lesson(lesson_id)
    if not lesson_row:
        raise HTTPException(status_code=404, detail="Lesson not found")
    storage_bucket = upload_routes._COURSE_MEDIA_BUCKET

    course_id_str = str(course_id)
    lesson_id_str = str(lesson_id)
    allowed_prefixes = upload_routes._LESSON_ALLOWED_PREFIXES + tuple(
        upload_routes._LESSON_ALLOWED_EXACT_TYPES
    )
    detected_kind = upload_routes._detect_kind(
        file.content_type or mimetypes.guess_type(file.filename or "")[0]
    )
    if detected_kind == "audio":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Audio uploads must use the media pipeline",
        )
    if detected_kind in {"image", "video", "audio", "document", "pdf"}:
        if detected_kind == "image":
            storage_path = (
                upload_routes.media_paths.build_lesson_passthrough_object_path(
                    course_id=course_id_str,
                    lesson_id=lesson_id_str,
                    media_kind=detected_kind,
                    filename=file.filename or "media",
                )
            )
        else:
            storage_path = (
                upload_routes.media_paths.build_lesson_passthrough_object_path(
                    course_id=course_id_str,
                    lesson_id=lesson_id_str,
                    media_kind=detected_kind,
                    filename=file.filename or "media",
                )
            )
    else:
        storage_path = (
            Path("courses")
            / course_id_str
            / "lessons"
            / lesson_id_str
            / f"{uuid4().hex}_{Path(file.filename or 'media').name}"
        ).as_posix()
    relative_dir = Path(storage_bucket) / Path(storage_path).parent

    destination_dir = upload_routes._safe_join(
        upload_routes.UPLOADS_ROOT, *relative_dir.parts
    )
    write_result = await upload_routes._write_upload(
        destination_dir,
        file,
        allowed_prefixes=allowed_prefixes,
        max_bytes=_MAX_MEDIA_BYTES,
    )
    storage_relative_path = (
        Path(storage_path).parent / write_result.filename
    ).as_posix()
    content_type = (
        file.content_type
        or mimetypes.guess_type(write_result.destination_path.name)[0]
        or "application/octet-stream"
    )

    row = await upload_routes._persist_lesson_media(
        owner_id=owner_id,
        lesson_id=lesson_id,
        storage_path=storage_relative_path,
        original_name=file.filename,
        content_type=content_type,
        size=write_result.size,
        checksum=write_result.checksum,
        storage_bucket=storage_bucket,
        course_id=course_id_str,
    )

    logger.info(
        "Media stored: lesson_id=%s course_id=%s media_id=%s storage_path=%s bucket=%s size_bytes=%s",
        lesson_id,
        course_id,
        row.get("id"),
        row.get("storage_path"),
        storage_bucket,
        write_result.size,
    )
    return row


@router.delete("/media/{media_id}")
async def delete_media(media_id: str, current: TeacherUser):
    row = await models.get_media(media_id)
    if not row:
        raise HTTPException(status_code=404, detail="Media not found")
    media_asset_id = row.get("media_asset_id")
    media_asset = (
        await repositories.get_media_asset(str(media_asset_id))
        if media_asset_id
        else None
    )
    _, course_id = await courses_service.lesson_course_ids(row.get("lesson_id"))
    if course_id and not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
            media_id=media_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    deleted_row = await models.delete_lesson_media_entry(media_id)

    if media_asset and deleted_row and deleted_row.get("media_asset_deleted"):
        delete_targets: set[tuple[str, str]] = set()
        original_path = media_asset.get("original_object_path")
        original_bucket = (
            media_asset.get("storage_bucket") or settings.media_source_bucket
        )
        if original_path and original_bucket:
            delete_targets.add((str(original_bucket), str(original_path)))
            if (media_asset.get("media_type") or "").lower() == "audio":
                normalized = str(original_path).lstrip("/")
                prefix = "media/source/audio/"
                if normalized.startswith(prefix):
                    normalized = "media/derived/audio/" + normalized[len(prefix) :]
                else:
                    normalized = "media/derived/audio/" + normalized
                derived_path = Path(normalized).with_suffix(".mp3").as_posix()
                delete_targets.add((str(original_bucket), derived_path))

        streaming_path = media_asset.get("streaming_object_path")
        if streaming_path:
            streaming_bucket = media_asset.get("streaming_storage_bucket")
            if streaming_bucket:
                delete_targets.add((str(streaming_bucket), str(streaming_path)))

        for bucket, path in sorted(delete_targets):
            try:
                service = storage_service.get_storage_service(bucket)
                await service.delete_object(path)
            except storage_service.StorageServiceError as exc:
                logger.warning(
                    "Storage delete failed bucket=%s path=%s: %s", bucket, path, exc
                )
    return {"deleted": True}


@router.patch("/lessons/{lesson_id}/media/reorder")
async def reorder_media(
    lesson_id: str,
    payload: schemas.MediaReorder,
    current: TeacherUser,
):
    _, course_id = await courses_service.lesson_course_ids(lesson_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    await models.reorder_media(lesson_id, payload.media_ids)
    return {"ok": True}


@router.get("/media/{media_id}")
async def media_file(
    media_id: str,
    request: Request,
    current: CurrentUser,
):
    if not settings.media_allow_legacy_media:
        raise HTTPException(status_code=410, detail="Legacy media endpoint disabled")
    row = await models.get_media(media_id)
    if not row:
        raise HTTPException(status_code=404, detail="Media not found")

    storage_path = row.get("storage_path")
    storage_bucket = row.get("storage_bucket")
    if not storage_path or not storage_bucket:
        raise HTTPException(status_code=404, detail="Media not found")

    access_row = await courses_repo.get_lesson_media_access_by_path(
        storage_path=storage_path,
        storage_bucket=storage_bucket,
    )
    if not access_row:
        raise HTTPException(status_code=404, detail="Media not found")

    user_id = str(current["id"])
    course_id = access_row.get("course_id")
    teacher_access = (
        await courses_service.is_course_teacher_or_instructor(user_id, str(course_id))
        if course_id
        else False
    )
    if not teacher_access:
        if not access_row.get("is_published"):
            raise HTTPException(status_code=403, detail="Course not published")
        if not course_id:
            raise HTTPException(status_code=403, detail="Access denied")
        access = await courses_service.read_canonical_course_access(
            user_id,
            str(course_id),
        )
        if access.get("can_access") is not True:
            raise HTTPException(status_code=403, detail="Access denied")
    logger.info(
        "LEGACY_MEDIA_ROUTE_HIT route=/studio/media/%s user_id=%s",
        media_id,
        user_id,
    )
    return await _build_streaming_response(row, request)


@router.post("/courses/{course_id}/quiz")
async def ensure_quiz(course_id: str, current: TeacherUser):
    if not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    quiz = await models.ensure_quiz_for_user(course_id, current["id"])
    if not quiz:
        raise HTTPException(status_code=400, detail="Failed to ensure quiz")
    return {"quiz": quiz}


@router.get("/quizzes/{quiz_id}/questions")
async def quiz_questions(quiz_id: str, current: TeacherUser):
    if not await models.quiz_belongs_to_user(quiz_id, current["id"]):
        _log_quiz_owner_denied(
            str(current["id"]),
            quiz_id,
        )
        raise HTTPException(status_code=403, detail="Not quiz owner")
    rows = await models.quiz_questions(quiz_id)
    return {"items": rows}


@router.post("/quizzes/{quiz_id}/questions")
async def create_question(
    quiz_id: str,
    payload: schemas.QuizQuestionUpsert,
    current: TeacherUser,
):
    if not await models.quiz_belongs_to_user(quiz_id, current["id"]):
        _log_quiz_owner_denied(
            str(current["id"]),
            quiz_id,
        )
        raise HTTPException(status_code=403, detail="Not quiz owner")
    row = await models.upsert_quiz_question(
        quiz_id,
        payload.model_dump(exclude_unset=True),
    )
    if not row:
        raise HTTPException(status_code=400, detail="Failed to upsert question")
    return row


@router.put("/quizzes/{quiz_id}/questions/{question_id}")
async def update_question(
    quiz_id: str,
    question_id: str,
    payload: schemas.QuizQuestionUpsert,
    current: TeacherUser,
):
    if not await models.quiz_belongs_to_user(quiz_id, current["id"]):
        _log_quiz_owner_denied(
            str(current["id"]),
            quiz_id,
        )
        raise HTTPException(status_code=403, detail="Not quiz owner")
    data = payload.model_dump(exclude_unset=True)
    data["id"] = question_id
    row = await models.upsert_quiz_question(quiz_id, data)
    if not row:
        raise HTTPException(status_code=404, detail="Question not found")
    return row


@router.delete("/quizzes/{quiz_id}/questions/{question_id}")
async def delete_question(quiz_id: str, question_id: str, current: TeacherUser):
    if not await models.quiz_belongs_to_user(quiz_id, current["id"]):
        _log_quiz_owner_denied(
            str(current["id"]),
            quiz_id,
        )
        raise HTTPException(status_code=403, detail="Not quiz owner")
    deleted = await models.delete_quiz_question(question_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Question not found")
    return {"deleted": True}
