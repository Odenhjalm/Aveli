import logging
import mimetypes
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict
from uuid import UUID, uuid4

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile, status

from .. import models, repositories, schemas
from ..auth import CurrentUser
from ..config import settings
from ..permissions import TeacherUser
from ..repositories import courses as courses_repo
from ..services import courses_service, livekit as livekit_service, storage_service
from ..services.livekit_tokens import LiveKitTokenConfigError, build_token
from ..utils import media_signer
from ..utils.profile_media import (
    lesson_media_source_from_row,
    profile_media_item_from_row,
    recording_source_from_row,
)
from .media import _build_streaming_response
from . import upload as upload_routes

router = APIRouter(prefix="/studio", tags=["studio"])
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
    module_id: str | None = None,
    lesson_id: str | None = None,
    media_id: str | None = None,
) -> None:
    logger.warning(
        "Permission denied: course owner required user_id=%s course_id=%s module_id=%s lesson_id=%s media_id=%s",
        user_id,
        course_id,
        module_id,
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


_MAX_MEDIA_BYTES = settings.lesson_media_max_bytes
_LIVE_RECORDINGS_ROOT = "live-recordings"


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


@router.get("/courses")
async def studio_courses(current: TeacherUser):
    rows = await models.teacher_courses(current["id"])
    for row in rows:
        media_signer.attach_cover_links(row)
    return {"items": rows}


@router.get("/status")
async def studio_status(current: CurrentUser):
    info = await models.teacher_status(current["id"])
    return info


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


@router.post("/courses")
async def create_course(payload: schemas.StudioCourseCreate, current: TeacherUser):
    row = await models.create_course_for_user(current["id"], payload.model_dump())
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create course")
    return row


@router.post("/lessons/{lesson_id}/media/presign")
async def presign_lesson_media_upload(
    lesson_id: UUID,
    payload: schemas.LessonMediaPresignRequest,
    current: TeacherUser,
):
    # Ensure lesson exists and current user owns the course.
    lesson_id_str = str(lesson_id)
    lesson = await models.get_lesson(lesson_id_str)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    _, course_id = await courses_service.lesson_course_ids(lesson_id_str)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(str(current["id"]), course_id=course_id, lesson_id=lesson_id_str)
        raise HTTPException(status_code=403, detail="Not course owner")

    bucket = "course-media"
    path = f"{bucket}/lessons/{lesson_id}/{payload.filename}"
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
    lesson_id: UUID,
    payload: schemas.LessonMediaUploadCompleteRequest,
    current: TeacherUser,
):
    # Ensure lesson exists and current user owns the course.
    lesson_id_str = str(lesson_id)
    lesson = await models.get_lesson(lesson_id_str)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    _, course_id = await courses_service.lesson_course_ids(lesson_id_str)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(str(current["id"]), course_id=course_id, lesson_id=lesson_id_str)
        raise HTTPException(status_code=403, detail="Not course owner")

    kind = _detect_kind(payload.content_type)
    expected_bucket = "course-media"
    if payload.storage_bucket != expected_bucket:
        raise HTTPException(
            status_code=400,
            detail={"storage_bucket": "must equal course-media"},
        )

    row = await models.add_lesson_media_entry(
        lesson_id=str(lesson_id),
        kind=kind,
        storage_path=payload.storage_path,
        storage_bucket=payload.storage_bucket,
        media_id=None,
        position=0,
        duration_seconds=None,
    )
    if not row:
        raise HTTPException(status_code=400, detail="Failed to record lesson media")
    row["content_type"] = payload.content_type
    row["byte_size"] = payload.byte_size
    row["original_name"] = payload.original_name
    media_signer.attach_media_links(row)
    return row


@router.get("/lessons/{lesson_id}/media")
async def list_lesson_media(lesson_id: UUID, current: TeacherUser):
    lesson_id_str = str(lesson_id)
    _, course_id = await courses_service.lesson_course_ids(lesson_id_str)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(str(current["id"]), course_id=course_id, lesson_id=lesson_id_str)
        raise HTTPException(status_code=403, detail="Not course owner")
    items = await models.list_lesson_media(str(lesson_id))
    return {"items": items}


@router.get(
    "/profile/media",
    response_model=schemas.TeacherProfileMediaListResponse,
)
async def studio_profile_media(current: TeacherUser):
    teacher_id = str(current["id"])
    items = await repositories.list_teacher_profile_media(teacher_id)
    lesson_sources = await repositories.list_teacher_lesson_media_sources(teacher_id)
    recording_sources = await repositories.list_teacher_seminar_recording_sources(
        teacher_id
    )
    return schemas.TeacherProfileMediaListResponse(
        items=[profile_media_item_from_row(row) for row in items],
        lesson_media=[lesson_media_source_from_row(row) for row in lesson_sources],
        seminar_recordings=[
            recording_source_from_row(row) for row in recording_sources
        ],
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
    media_kind = payload.media_kind
    if media_kind in {
        schemas.TeacherProfileMediaKind.lesson_media,
        schemas.TeacherProfileMediaKind.seminar_recording,
    } and payload.media_id is None:
        raise HTTPException(
            status_code=422, detail="media_id is required for selected media kind"
        )
    if (
        media_kind == schemas.TeacherProfileMediaKind.external
        and not payload.external_url
    ):
        raise HTTPException(
            status_code=422, detail="external_url is required for external media"
        )
    if media_kind in {
        schemas.TeacherProfileMediaKind.lesson_media,
        schemas.TeacherProfileMediaKind.seminar_recording,
    }:
        title = (payload.title or "").strip()
        if not title:
            raise HTTPException(status_code=422, detail="title is required for selected media kind")

    row = await repositories.create_teacher_profile_media(
        teacher_id=str(current["id"]),
        media_kind=media_kind.value,
        media_id=str(payload.media_id) if payload.media_id else None,
        external_url=payload.external_url,
        title=payload.title,
        description=payload.description,
        cover_media_id=str(payload.cover_media_id)
        if payload.cover_media_id
        else None,
        cover_image_url=payload.cover_image_url,
        position=payload.position,
        is_published=payload.is_published,
        metadata=payload.metadata,
    )
    if not row:
        raise HTTPException(
            status_code=400, detail="Failed to create profile media item"
        )
    return profile_media_item_from_row(row)


@router.patch(
    "/profile/media/{item_id}",
    response_model=schemas.TeacherProfileMediaItem,
)
async def studio_update_profile_media(
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
    if payload.metadata is not None:
        fields["metadata"] = payload.metadata

    row = await repositories.update_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
        fields=fields,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    current_cover_media_id = str(row["cover_media_id"]) if row.get("cover_media_id") else None
    if previous_cover_media_id and previous_cover_media_id != current_cover_media_id:
        await models.cleanup_media_object(previous_cover_media_id)
    return profile_media_item_from_row(row)


@router.delete("/profile/media/{item_id}", status_code=204)
async def studio_delete_profile_media(item_id: UUID, current: TeacherUser):
    existing = await repositories.get_teacher_profile_media(
        item_id=str(item_id),
        teacher_id=str(current["id"]),
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Profile media item not found")
    cover_media_id = str(existing["cover_media_id"]) if existing.get("cover_media_id") else None
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
        course_media=[schemas.TeacherProfileLessonSource(**row) for row in course_media],
    )


@router.post(
    "/home-player/uploads",
    response_model=schemas.HomePlayerUploadItem,
    status_code=status.HTTP_201_CREATED,
)
async def studio_create_home_player_upload(
    current: TeacherUser,
    file: UploadFile = File(...),
    title: str = Form(...),
    active: bool = Form(True),
):
    teacher_id = str(current["id"])
    normalized_title = (title or "").strip()
    if not normalized_title:
        raise HTTPException(status_code=422, detail="title is required")

    content_type = (
        file.content_type
        or mimetypes.guess_type(file.filename or "")[0]
        or "application/octet-stream"
    )
    normalized_type = content_type.lower()
    if not (normalized_type.startswith("audio/") or normalized_type.startswith("video/")):
        raise HTTPException(status_code=415, detail="Unsupported media type")
    kind = "video" if normalized_type.startswith("video/") else "audio"

    relative_dir = Path("home-media") / teacher_id
    destination_dir = upload_routes._safe_join(
        upload_routes.UPLOADS_ROOT,
        *relative_dir.parts,
    )
    write_result = await upload_routes._write_upload(
        destination_dir,
        file,
        allowed_prefixes=("audio/", "video/"),
        max_bytes=settings.lesson_media_max_bytes,
    )
    relative_path = relative_dir / write_result.filename
    final_content_type = (
        file.content_type
        or mimetypes.guess_type(write_result.destination_path.name)[0]
        or "application/octet-stream"
    )

    media_object = await models.create_media_object(
        owner_id=teacher_id,
        storage_path=relative_path.as_posix(),
        storage_bucket="home-media",
        content_type=final_content_type,
        byte_size=write_result.size,
        checksum=write_result.checksum,
        original_name=file.filename,
    )
    if not media_object:
        raise HTTPException(status_code=500, detail="Failed to persist media")

    created = await repositories.create_home_player_upload(
        teacher_id=teacher_id,
        media_id=str(media_object["id"]),
        title=normalized_title,
        kind=kind,
        active=bool(active),
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


@router.delete("/home-player/uploads/{upload_id}", status_code=status.HTTP_204_NO_CONTENT)
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


@router.delete("/home-player/course-links/{link_id}", status_code=status.HTTP_204_NO_CONTENT)
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


@router.get("/courses/{course_id}")
async def course_meta(course_id: str, current: TeacherUser):
    if not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    row = await models.get_course(course_id=course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    return row


@router.patch("/courses/{course_id}")
async def update_course(
    course_id: str,
    payload: schemas.StudioCourseUpdate,
    current: TeacherUser,
):
    row = await models.update_course_for_user(
        current["id"], course_id, payload.model_dump(exclude_unset=True)
    )
    if not row:
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    return row


@router.delete("/courses/{course_id}")
async def delete_course(course_id: str, current: TeacherUser):
    deleted = await models.delete_course_for_user(current["id"], course_id)
    if not deleted:
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    return {"deleted": True}


@router.get("/courses/{course_id}/lessons")
async def course_lessons(course_id: str, current: TeacherUser):
    if not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    lessons = await courses_service.list_course_lessons(course_id)
    return {"items": lessons}


@router.get("/courses/{course_id}/modules")
async def course_modules(course_id: str, current: TeacherUser):
    if not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    modules_raw = await courses_service.list_modules(course_id)
    modules = [dict(module) for module in modules_raw]
    for module in modules:
        lessons_raw = await courses_service.list_lessons(module["id"])
        lessons = [dict(lesson) for lesson in lessons_raw]
        for lesson in lessons:
            lesson["media"] = await models.list_lesson_media(lesson["id"])
        module["lessons"] = lessons
    return {"items": modules}


@router.get("/modules/{module_id}/lessons")
async def module_lessons(module_id: str, current: TeacherUser):
    course_id = await courses_service.get_module_course_id(module_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    lessons_raw = await courses_service.list_lessons(module_id)
    lessons = [dict(lesson) for lesson in lessons_raw]
    for lesson in lessons:
        lesson["media"] = await models.list_lesson_media(lesson["id"])
    return {"items": lessons}


@router.post("/modules")
async def create_module(
    payload: schemas.StudioModuleCreate,
    current: TeacherUser,
):
    if not await models.is_course_owner(current["id"], payload.course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=payload.course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    module_id = str(payload.id) if payload.id else None
    row = await courses_service.create_module(
        payload.course_id,
        title=payload.title,
        position=payload.position,
        module_id=module_id,
    )
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create module")
    return row


@router.patch("/modules/{module_id}")
async def update_module(
    module_id: str,
    payload: schemas.StudioModuleUpdate,
    current: TeacherUser,
):
    course_id = await courses_service.get_module_course_id(module_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    patch = payload.model_dump(exclude_unset=True)
    if not patch:
        row = await courses_service.fetch_module(module_id)
    else:
        patch_payload = {"id": module_id, **patch}
        row = await courses_service.upsert_module(course_id, patch_payload)
    if not row:
        raise HTTPException(status_code=404, detail="Module not found")
    return row


@router.delete("/modules/{module_id}")
async def delete_module(module_id: str, current: TeacherUser):
    course_id = await courses_service.get_module_course_id(module_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    deleted = await courses_service.delete_module(module_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Module not found")
    return {"deleted": True}


@router.post("/lessons")
async def create_lesson(
    payload: schemas.StudioLessonCreate,
    current: TeacherUser,
):
    course_id = payload.course_id
    if not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    lesson_id = str(payload.id) if payload.id else None
    row = await courses_service.create_lesson(
        course_id,
        title=payload.title,
        content_markdown=payload.content_markdown,
        position=payload.position,
        is_intro=payload.is_intro,
        lesson_id=lesson_id,
    )
    if not row:
        raise HTTPException(status_code=400, detail="Failed to create lesson")
    return row


@router.patch("/lessons/{lesson_id}")
async def update_lesson(
    lesson_id: str,
    payload: schemas.StudioLessonUpdate,
    current: TeacherUser,
):
    _, course_id = await courses_service.lesson_course_ids(lesson_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    existing = await courses_service.fetch_lesson(lesson_id)
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
    row = await courses_service.upsert_lesson(str(course_id), lesson_payload)
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

    return row


@router.delete("/lessons/{lesson_id}")
async def delete_lesson(lesson_id: str, current: TeacherUser):
    _, course_id = await courses_service.lesson_course_ids(lesson_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    deleted = await courses_service.delete_lesson(lesson_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return {"deleted": True}


@router.patch("/lessons/{lesson_id}/intro")
async def set_intro(
    lesson_id: str, payload: schemas.LessonIntroUpdate, current: TeacherUser
):
    _, course_id = await courses_service.lesson_course_ids(lesson_id)
    if not course_id or not await models.is_course_owner(current["id"], course_id):
        _log_course_owner_denied(
            str(current["id"]),
            course_id=course_id,
        )
        raise HTTPException(status_code=403, detail="Not course owner")
    row = await models.set_lesson_intro(lesson_id, payload.is_intro)
    if not row:
        raise HTTPException(status_code=404, detail="Lesson not found")
    return row


@router.post("/lessons/{lesson_id}/media")
async def upload_media(
    lesson_id: str,
    current: TeacherUser,
    file: UploadFile = File(...),
    is_intro: bool = Form(False),
):
    owner = current["id"]
    owner_id = str(owner)
    _, course_id = await courses_service.lesson_course_ids(lesson_id)
    if not course_id or not await models.is_course_owner(owner, course_id):
        _log_course_owner_denied(
            owner_id,
            course_id=str(course_id) if course_id else None,
        )
        raise HTTPException(status_code=403, detail="Not course owner")

    lesson_row = await courses_service.fetch_lesson(lesson_id)
    if not lesson_row:
        raise HTTPException(status_code=404, detail="Lesson not found")
    lesson_is_intro = bool(lesson_row.get("is_intro"))
    effective_intro = is_intro or lesson_is_intro

    storage_bucket = (
        upload_routes._PUBLIC_MEDIA_BUCKET if effective_intro else upload_routes._COURSE_MEDIA_BUCKET
    )

    course_id_str = str(course_id)
    lesson_id_str = str(lesson_id)
    relative_dir = Path(storage_bucket) / course_id_str / lesson_id_str
    allowed_prefixes = upload_routes._LESSON_ALLOWED_PREFIXES + tuple(
        upload_routes._LESSON_ALLOWED_EXACT_TYPES
    )
    detected_kind = upload_routes._detect_kind(file.content_type or mimetypes.guess_type(file.filename or "")[0])
    if detected_kind in {"image", "video", "audio", "pdf"}:
        relative_dir /= detected_kind

    destination_dir = upload_routes._safe_join(upload_routes.UPLOADS_ROOT, *relative_dir.parts)
    write_result = await upload_routes._write_upload(
        destination_dir,
        file,
        allowed_prefixes=allowed_prefixes,
        max_bytes=_MAX_MEDIA_BYTES,
    )
    relative_path = relative_dir / write_result.filename
    content_type = (
        file.content_type
        or mimetypes.guess_type(write_result.destination_path.name)[0]
        or "application/octet-stream"
    )

    row = await upload_routes._persist_lesson_media(
        owner_id=owner_id,
        lesson_id=lesson_id,
        relative_path=relative_path,
        original_name=file.filename,
        content_type=content_type,
        size=write_result.size,
        checksum=write_result.checksum,
        storage_bucket=storage_bucket,
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
            streaming_bucket = media_asset.get("streaming_storage_bucket") or original_bucket
            if streaming_bucket:
                delete_targets.add((str(streaming_bucket), str(streaming_path)))

        for bucket, path in sorted(delete_targets):
            try:
                service = storage_service.get_storage_service(bucket)
                await service.delete_object(path)
            except storage_service.StorageServiceError as exc:
                logger.warning("Storage delete failed bucket=%s path=%s: %s", bucket, path, exc)
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
    if str(access_row.get("created_by")) != user_id:
        if not access_row.get("is_published"):
            raise HTTPException(status_code=403, detail="Course not published")
        if not (access_row.get("is_intro") or access_row.get("is_free_intro")):
            course_id = access_row.get("course_id")
            if not course_id:
                raise HTTPException(status_code=403, detail="Access denied")
            snapshot = await models.course_access_snapshot(user_id, str(course_id))
            if not snapshot.get("has_access"):
                raise HTTPException(status_code=403, detail="Access denied")
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
