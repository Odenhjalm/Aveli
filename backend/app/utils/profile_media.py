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


def _require_str(value: Any | None, field: str) -> str:
    if value is None:
        raise ValueError(f"Missing string for {field}")
    return str(value)


def _require_bool(value: Any | None, field: str) -> bool:
    if value is None:
        raise ValueError(f"Missing bool for {field}")
    if isinstance(value, bool):
        return value
    raise ValueError(f"Invalid bool for {field}")


def lesson_media_source_from_row(
    row: Dict[str, Any],
) -> schemas.TeacherProfileLessonSource:
    data = dict(row)
    return schemas.TeacherProfileLessonSource(
        id=_require_uuid(data.get("id"), "lesson_media.id"),
        lesson_id=_require_uuid(data.get("lesson_id"), "lesson_media.lesson_id"),
        lesson_title=data.get("lesson_title"),
        course_id=_optional_uuid(data.get("course_id")),
        course_title=data.get("course_title"),
        course_slug=data.get("course_slug"),
        kind=_require_str(data.get("kind"), "lesson_media.kind"),
        storage_path=_optional_str(data.get("storage_path")),
        storage_bucket=_optional_str(data.get("storage_bucket")),
        content_type=_optional_str(data.get("content_type")),
        duration_seconds=data.get("duration_seconds"),
        position=data.get("position"),
        created_at=data.get("created_at"),
        media=data.get("media"),
    )


def recording_source_from_row(
    row: Dict[str, Any],
) -> schemas.TeacherProfileRecordingSource:
    data = dict(row)
    return schemas.TeacherProfileRecordingSource(
        id=_require_uuid(data.get("id"), "recording.id"),
        seminar_id=_require_uuid(data.get("seminar_id"), "recording.seminar_id"),
        seminar_title=data.get("seminar_title"),
        session_id=_optional_uuid(data.get("session_id")),
        asset_url=_require_str(data.get("asset_url"), "recording.asset_url"),
        status=_require_str(data.get("status"), "recording.status"),
        duration_seconds=data.get("duration_seconds"),
        byte_size=data.get("byte_size"),
        published=_require_bool(data.get("published"), "recording.published"),
        created_at=data.get("created_at"),
        updated_at=data.get("updated_at"),
    )
