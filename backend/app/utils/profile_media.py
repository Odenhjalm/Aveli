from __future__ import annotations

from typing import Any, Dict
from uuid import UUID

from .. import schemas


def _require_uuid(value: Any, field: str) -> UUID:
    if isinstance(value, UUID):
        return value
    if value is None:
        raise ValueError(f"Missing UUID for {field}")
    return UUID(str(value))


def _optional_uuid(value: Any | None) -> UUID | None:
    if value is None:
        return None
    if isinstance(value, UUID):
        return value
    return UUID(str(value))


def _optional_str(value: Any | None) -> str | None:
    if value is None:
        return None
    return str(value)


def lesson_media_source_from_row(
    row: Dict[str, Any],
) -> schemas.TeacherProfileLessonSource:
    data = dict(row)
    storage_bucket = data.get("storage_bucket") or "lesson-media"
    data["storage_bucket"] = storage_bucket
    return schemas.TeacherProfileLessonSource(
        id=_require_uuid(data.get("id"), "lesson_media.id"),
        lesson_id=_require_uuid(data.get("lesson_id"), "lesson_media.lesson_id"),
        lesson_title=data.get("lesson_title"),
        course_id=_optional_uuid(data.get("course_id")),
        course_title=data.get("course_title"),
        course_slug=data.get("course_slug"),
        kind=str(data.get("kind") or "lesson_media"),
        storage_path=_optional_str(data.get("storage_path")),
        storage_bucket=storage_bucket,
        content_type=_optional_str(data.get("content_type")),
        duration_seconds=data.get("duration_seconds"),
        position=data.get("position"),
        created_at=data.get("created_at"),
        download_url=_optional_str(data.get("download_url")),
        signed_url=_optional_str(data.get("signed_url")),
        signed_url_expires_at=_optional_str(data.get("signed_url_expires_at")),
    )


def recording_source_from_row(
    row: Dict[str, Any],
) -> schemas.TeacherProfileRecordingSource:
    data = dict(row)
    metadata = data.get("metadata") or {}
    return schemas.TeacherProfileRecordingSource(
        id=_require_uuid(data.get("id"), "recording.id"),
        seminar_id=_require_uuid(data.get("seminar_id"), "recording.seminar_id"),
        seminar_title=data.get("seminar_title"),
        session_id=_optional_uuid(data.get("session_id")),
        asset_url=_optional_str(data.get("asset_url")) or "",
        status=_optional_str(data.get("status")) or "unknown",
        duration_seconds=data.get("duration_seconds"),
        byte_size=data.get("byte_size"),
        published=bool(data.get("published")),
        metadata=metadata,
        created_at=data.get("created_at"),
        updated_at=data.get("updated_at"),
    )


def profile_media_item_from_row(
    row: Dict[str, Any],
) -> schemas.TeacherProfileMediaItem:
    data = dict(row)
    metadata = data.get("metadata") or {}
    media_kind = schemas.TeacherProfileMediaKind(data["media_kind"])
    source = schemas.TeacherProfileMediaSource()

    if (
        media_kind == schemas.TeacherProfileMediaKind.lesson_media
        and data.get("lesson_media_id")
    ):
        lesson_source = lesson_media_source_from_row(
            {
                "id": data["lesson_media_id"],
                "lesson_id": data.get("lesson_id"),
                "lesson_title": data.get("lesson_title"),
                "course_id": data.get("course_id"),
                "course_title": data.get("course_title"),
                "course_slug": data.get("course_slug"),
                "kind": data.get("lesson_media_kind"),
                "storage_path": data.get("lesson_media_storage_path"),
                "storage_bucket": data.get("lesson_media_storage_bucket"),
                "content_type": data.get("lesson_media_content_type"),
                "duration_seconds": data.get("lesson_media_duration_seconds"),
                "position": data.get("lesson_media_position"),
                "created_at": data.get("lesson_media_created_at"),
                "download_url": data.get("lesson_media_download_url"),
                "signed_url": data.get("lesson_media_signed_url"),
                "signed_url_expires_at": data.get(
                    "lesson_media_signed_url_expires_at"
                ),
            }
        )
        source.lesson_media = lesson_source

    if (
        media_kind == schemas.TeacherProfileMediaKind.seminar_recording
        and data.get("seminar_recording_id")
    ):
        recording_source = recording_source_from_row(
            {
                "id": data["seminar_recording_id"],
                "seminar_id": data.get("seminar_id"),
                "seminar_title": data.get("seminar_title"),
                "session_id": data.get("seminar_session_id"),
                "asset_url": data.get("seminar_recording_asset_url"),
                "status": data.get("seminar_recording_status"),
                "duration_seconds": data.get("seminar_recording_duration_seconds"),
                "byte_size": data.get("seminar_recording_byte_size"),
                "published": data.get("seminar_recording_published", False),
                "metadata": data.get("seminar_recording_metadata") or {},
                "created_at": data.get("seminar_recording_created_at"),
                "updated_at": data.get("seminar_recording_updated_at"),
            }
        )
        source.seminar_recording = recording_source

    return schemas.TeacherProfileMediaItem(
        id=data["id"],
        teacher_id=data["teacher_id"],
        media_kind=media_kind,
        media_id=data.get("media_id"),
        external_url=data.get("external_url"),
        title=data.get("title"),
        description=data.get("description"),
        cover_media_id=data.get("cover_media_id"),
        cover_image_url=data.get("cover_image_url"),
        position=data.get("position", 0),
        is_published=data.get("is_published", True),
        metadata=metadata,
        created_at=data["created_at"],
        updated_at=data["updated_at"],
        source=source,
    )
