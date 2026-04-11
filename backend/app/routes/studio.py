import logging
import mimetypes
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict
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

from .. import models, repositories, schemas
from ..config import settings
from ..db import get_conn
from ..permissions import TeacherUser
from ..repositories import courses as courses_repo
from ..repositories import home_audio_sources as home_audio_sources_repo
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
_STUDIO_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)
_CANONICAL_COURSE_FIELDS = (
    "id",
    "slug",
    "title",
    "course_group_id",
    "step",
    "cover_media_id",
    "cover",
    "price_amount_cents",
    "drip_enabled",
    "drip_interval_days",
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


async def _require_canonical_lesson_media_authoring_context(
    *,
    lesson_id: str,
    current: TeacherUser,
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


async def _authorize_canonical_lesson_media_asset(
    *,
    media_asset_id: str,
    current: TeacherUser,
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


_MAX_MEDIA_BYTES = settings.lesson_media_max_bytes
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
    return {field: course.get(field) for field in _CANONICAL_COURSE_FIELDS}


def _course_response(course: Dict[str, Any]) -> schemas.Course:
    return schemas.Course(**_canonical_course_payload(course))


def _course_list_response(rows: list[dict[str, Any]]) -> schemas.CourseListResponse:
    return schemas.CourseListResponse(items=[_course_response(row) for row in rows])


async def _require_studio_lesson(lesson_id: str) -> dict[str, Any]:
    lesson = await courses_service.fetch_studio_lesson(lesson_id)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return lesson


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


@router.get("/courses")
async def studio_courses(current: TeacherUser):
    rows = list(await courses_service.list_courses(teacher_id=str(current["id"])))
    await _apply_course_read_contract(rows)
    return _course_list_response(rows)


@router.get("/status")
async def studio_status(current: TeacherUser):
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
async def studio_certificates(current: TeacherUser, verified_only: bool = False):
    rows = await models.user_certificates(current["id"], verified_only)
    return {"items": rows}


@router.post("/certificates")
async def studio_add_certificate(
    payload: schemas.StudioCertificateCreate,
    current: TeacherUser,
):
    try:
        row = await models.add_certificate(
            current["id"],
            title=payload.title,
            status=payload.status,
            notes=payload.notes,
            evidence_url=payload.evidence_url,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return row


@course_lesson_router.post("/courses", response_model=schemas.Course)
async def create_course(payload: schemas.StudioCourseCreate, current: TeacherUser):
    try:
        row = await courses_service.create_course(
            payload.model_dump(),
            teacher_id=str(current["id"]),
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create course")
    await _apply_course_read_contract(row)
    return _course_response(row)


@media_pipeline_router.post(
    "/lessons/{lesson_id}/media-assets/upload-url",
    response_model=schemas.CanonicalLessonMediaUploadUrlResponse,
)
async def canonical_issue_lesson_media_upload_url(
    lesson_id: UUID,
    payload: schemas.CanonicalLessonMediaUploadUrlRequest,
    current: TeacherUser,
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
    storage_client = storage_service.storage_service
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
        if normalized_media_type == "image":
            storage_client = storage_service.public_storage_service

    try:
        upload = await storage_client.create_upload_url(
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
    media_asset = await media_assets_repo.create_media_asset(
        media_asset_id=media_asset_id,
        media_type=normalized_media_type,
        purpose="lesson_media",
        original_object_path=upload.path,
        ingest_format=ingest_format,
        state="pending_upload",
    )
    return schemas.CanonicalLessonMediaUploadUrlResponse(
        media_asset_id=UUID(str(media_asset["id"])),
        asset_state="pending_upload",
        upload_url=upload.url,
        headers=dict(upload.headers),
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=upload.expires_in),
    )


@media_pipeline_router.post(
    "/media-assets/{media_asset_id}/upload-completion",
    response_model=schemas.CanonicalMediaAssetUploadCompletionResponse,
)
async def canonical_complete_lesson_media_upload(
    media_asset_id: UUID,
    payload: schemas.CanonicalMediaAssetUploadCompletionRequest,
    current: TeacherUser,
):
    del payload
    media_asset_id_str = str(media_asset_id)
    await _authorize_canonical_lesson_media_asset(
        media_asset_id=media_asset_id_str,
        current=current,
    )
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


@media_pipeline_router.post(
    "/lessons/{lesson_id}/media-placements",
    response_model=schemas.CanonicalLessonMediaPlacementResponse,
)
async def canonical_create_lesson_media_placement(
    lesson_id: UUID,
    payload: schemas.CanonicalLessonMediaPlacementCreate,
    current: TeacherUser,
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
    current: TeacherUser,
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
    current: TeacherUser,
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
    current: TeacherUser,
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
    response_model=schemas.StudioLessonMediaListResponse,
)
async def studio_list_lesson_media(
    lesson_id: UUID,
    current: TeacherUser,
):
    await _require_studio_lesson(str(lesson_id))
    rows = await courses_service.list_studio_lesson_media(str(lesson_id))
    items = [
        await _studio_lesson_media_item_from_row(
            row=dict(row),
            user_id=str(current["id"]),
        )
        for row in rows
    ]
    return schemas.StudioLessonMediaListResponse(items=items)


@lesson_media_router.get(
    "/{lesson_id}/{lesson_media_id}/preview",
    response_model=schemas.StudioLessonMediaPreviewResponse,
)
async def studio_preview_lesson_media(
    lesson_id: UUID,
    lesson_media_id: UUID,
    current: TeacherUser,
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
    resolved_url = str(playback.get("resolved_url") or "").strip()
    expires_at = playback.get("expires_at")
    if not resolved_url or not isinstance(expires_at, datetime):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Preview storage is unavailable",
        )
    return schemas.StudioLessonMediaPreviewResponse(
        lesson_media_id=lesson_media_id,
        preview_url=resolved_url,
        expires_at=expires_at,
    )


@lesson_media_router.post("/previews", response_model=schemas.MediaPreviewBatchResponse)
async def studio_request_lesson_media_previews(
    payload: schemas.MediaPreviewBatchRequest,
    current: TeacherUser,
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
async def studio_profile_media(current: TeacherUser):
    teacher_id = str(current["id"])
    rows = await repositories.list_teacher_profile_media(teacher_id)
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
    current: TeacherUser,
):
    row = await repositories.create_teacher_profile_media(
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
    current: TeacherUser,
):
    fields: Dict[str, Any] = {}
    if payload.media_asset_id is not None:
        fields["media_asset_id"] = str(payload.media_asset_id)
    if payload.visibility is not None:
        fields["visibility"] = payload.visibility.value

    row = await repositories.update_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
        fields=fields,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    return await profile_media_item_from_row(row)


@router.delete("/profile/media/{item_id}", status_code=204)
async def studio_delete_profile_media(item_id: UUID, current: TeacherUser):
    existing = await repositories.get_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    deleted = await repositories.delete_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    return Response(status_code=204)


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
    media_asset = await home_audio_sources_repo.get_home_audio_media_asset(
        str(payload.media_asset_id)
    )
    if not media_asset:
        raise HTTPException(status_code=404, detail="Media not found")
    if str(media_asset.get("owner_id") or "") != teacher_id:
        raise HTTPException(status_code=403, detail="Access denied")
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
    current: TeacherUser,
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
async def studio_delete_home_player_upload(upload_id: UUID, current: TeacherUser):
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
    current: TeacherUser,
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

    course_title_snapshot = str(resolved.get("course_title") or "").strip()
    row = await home_audio_sources_repo.upsert_home_player_course_link(
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
async def studio_delete_home_player_course_link(link_id: UUID, current: TeacherUser):
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
async def studio_courses(current: TeacherUser):
    rows = list(await courses_service.list_courses(teacher_id=str(current["id"])))
    await _apply_course_read_contract(rows)
    return _course_list_response(rows)


@course_lesson_router.get("/courses/{course_id}", response_model=schemas.Course)
async def course_meta(course_id: str, current: TeacherUser):
    del current
    row = await courses_service.fetch_course(course_id=course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    await _apply_course_read_contract(row)
    return _course_response(row)


@course_lesson_router.post(
    "/courses/{course_id}/public",
    response_model=schemas.CoursePublicContent,
)
async def upsert_course_public_content(
    course_id: str,
    payload: schemas.StudioCoursePublicContentUpsert,
    current: TeacherUser,
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
    current: TeacherUser,
):
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
async def delete_course(course_id: str, current: TeacherUser):
    del current
    deleted = await courses_service.delete_course(course_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Course not found")
    return {"deleted": True}


@course_lesson_router.get(
    "/courses/{course_id}/lessons",
    response_model=schemas.StudioLessonListResponse,
)
async def course_lessons(course_id: str, current: TeacherUser):
    del current
    course = await courses_service.fetch_course(course_id=course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
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
    current: TeacherUser,
):
    del current
    course = await courses_service.fetch_course(course_id=course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    try:
        row = await courses_service.create_lesson_structure(
            course_id,
            lesson_title=payload.lesson_title,
            position=payload.position,
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
    current: TeacherUser,
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


@course_lesson_router.patch(
    "/lessons/{lesson_id}/structure",
    response_model=schemas.StudioLessonStructure,
)
async def update_lesson_structure(
    lesson_id: str,
    payload: schemas.StudioLessonStructureUpdate,
    current: TeacherUser,
):
    del current
    patch = payload.model_dump(exclude_unset=True)
    try:
        row = await courses_service.update_lesson_structure(lesson_id, patch)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return schemas.StudioLessonStructure(**row)


@course_lesson_router.patch(
    "/lessons/{lesson_id}/content",
    response_model=schemas.StudioLessonContent,
)
async def update_lesson_content(
    lesson_id: str,
    payload: schemas.StudioLessonContentUpdate,
    current: TeacherUser,
):
    del current
    try:
        row = await courses_service.update_lesson_content(
            lesson_id,
            content_markdown=payload.content_markdown,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return schemas.StudioLessonContent(**row)


@course_lesson_router.delete("/lessons/{lesson_id}")
async def delete_lesson(lesson_id: str, current: TeacherUser):
    del current
    deleted = await courses_service.delete_lesson(lesson_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return {"deleted": True}


@router.get("/media/{media_id}")
async def media_file(
    media_id: str,
    request: Request,
    current: TeacherUser,
):
    del media_id, request, current
    raise HTTPException(
        status_code=410,
        detail="Legacy media endpoint removed from canonical runtime",
    )


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
