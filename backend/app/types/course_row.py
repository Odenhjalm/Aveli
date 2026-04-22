from __future__ import annotations

from typing import NotRequired, TypedDict
from uuid import UUID


class CourseRow(TypedDict):
    id: UUID
    slug: str
    title: str
    course_group_id: UUID
    group_position: int
    price_amount_cents: int | None
    stripe_product_id: str | None
    active_stripe_price_id: str | None
    sellable: bool
    teacher_id: UUID
    teacher_display_name: NotRequired[str | None]
    teacher: NotRequired[dict[str, object] | None]
    drip_enabled: bool
    drip_interval_days: int | None
    drip_mode: NotRequired[str]
    schedule_locked: NotRequired[bool]
    drip_authoring: NotRequired[dict[str, object]]
    required_enrollment_source: NotRequired[str | None]
    enrollable: NotRequired[bool]
    purchasable: NotRequired[bool]
    cover_media_id: UUID | None
    cover: NotRequired[dict[str, object] | None]


class LessonRow(TypedDict):
    id: UUID
    course_id: UUID
    lesson_title: str
    position: int


__all__ = ["CourseRow", "LessonRow"]
