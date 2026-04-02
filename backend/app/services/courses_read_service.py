from __future__ import annotations

from typing import Any, Mapping

from .. import schemas
from . import courses_service

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


def _canonical_course_payload(course: Mapping[str, Any]) -> dict[str, Any]:
    return {field: course.get(field) for field in _CANONICAL_COURSE_FIELDS}


def _compose_course_detail_view(
    *,
    course: Mapping[str, Any],
    lessons: list[Mapping[str, Any]] | tuple[Mapping[str, Any], ...],
    public_content: Mapping[str, Any] | None,
) -> schemas.CourseDetailResponse:
    return schemas.CourseDetailResponse(
        course=schemas.Course(**_canonical_course_payload(course)),
        lessons=[schemas.LessonStructureItem(**row) for row in lessons],
        short_description=(
            public_content.get("short_description")
            if public_content is not None
            else None
        ),
    )


async def read_course_detail(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> schemas.CourseDetailResponse | None:
    course = await courses_service.fetch_course(course_id=course_id, slug=slug)
    if not course:
        return None

    normalized_course_id = str(course["id"])

    await courses_service.attach_course_cover_read_contract(course)
    lessons = await courses_service.list_course_lessons(normalized_course_id)
    public_content = await courses_service.fetch_course_public_content(
        normalized_course_id
    )

    return _compose_course_detail_view(
        course=course,
        lessons=list(lessons),
        public_content=public_content,
    )
