from __future__ import annotations

from typing import Any, Mapping

from .. import schemas
from . import courses_service

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
_MISSING_COURSE_PUBLIC_CONTENT_ERROR = (
    "Invariant violation: missing course_public_content"
)


def _canonical_course_payload(course: Mapping[str, Any]) -> dict[str, Any]:
    courses_service.reject_legacy_course_cover_output_fields(course)
    courses_service.reject_legacy_course_progression_output_fields(course)
    normalized = dict(course)
    courses_service.attach_course_access_model(normalized)
    courses_service.attach_course_teacher_read_contract(normalized)
    return {field: normalized[field] for field in _CANONICAL_COURSE_FIELDS}


def _required_course_description(row: Mapping[str, Any]) -> str:
    description = row["description"]
    if not isinstance(description, str):
        raise RuntimeError(_MISSING_COURSE_PUBLIC_CONTENT_ERROR)
    return description


def _compose_course_detail_view(
    *,
    course: Mapping[str, Any],
    lessons: list[Mapping[str, Any]] | tuple[Mapping[str, Any], ...],
    description: str,
) -> schemas.CourseDetailResponse:
    return schemas.CourseDetailResponse(
        course=schemas.Course(**_canonical_course_payload(course)),
        lessons=[schemas.LessonStructureItem(**row) for row in lessons],
        description=description,
    )


def _lesson_payload_from_surface_row(row: Mapping[str, Any]) -> dict[str, Any] | None:
    lesson_id = row.get("lesson_id")
    if lesson_id is None:
        return None
    return {
        "id": lesson_id,
        "lesson_title": row.get("lesson_title"),
        "position": row.get("lesson_position"),
    }


async def _read_public_course_detail_rows(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> list[dict[str, Any]]:
    return list(
        await courses_service.fetch_public_course_detail_rows(
            course_id=course_id,
            slug=slug,
        )
    )


async def read_course_detail(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> schemas.CourseDetailResponse | None:
    rows = await _read_public_course_detail_rows(course_id=course_id, slug=slug)
    if not rows:
        return None

    course_row = dict(rows[0])
    course_row["cover"] = None
    course = dict(_canonical_course_payload(course_row))
    await courses_service.attach_course_cover_read_contract(course)
    lessons: list[dict[str, Any]] = []
    seen_lesson_ids: set[str] = set()
    for row in rows:
        lesson = _lesson_payload_from_surface_row(row)
        if lesson is None:
            continue
        lesson_id = str(lesson["id"])
        if lesson_id in seen_lesson_ids:
            continue
        seen_lesson_ids.add(lesson_id)
        lessons.append(lesson)

    return _compose_course_detail_view(
        course=course,
        lessons=lessons,
        description=_required_course_description(rows[0]),
    )


async def read_public_course_content(course_id: str) -> dict[str, Any] | None:
    rows = await _read_public_course_detail_rows(course_id=course_id)
    if not rows:
        return None
    return {
        "course_id": rows[0]["id"],
        "description": _required_course_description(rows[0]),
    }
