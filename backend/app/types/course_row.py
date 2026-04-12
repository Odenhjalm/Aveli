from __future__ import annotations

from typing import TypedDict
from uuid import UUID


class CourseRow(TypedDict):
    id: UUID
    slug: str
    title: str
    course_group_id: UUID
    step: str
    price_amount_cents: int | None
    stripe_product_id: str | None
    active_stripe_price_id: str | None
    sellable: bool
    drip_enabled: bool
    drip_interval_days: int | None
    cover_media_id: UUID | None


class LessonRow(TypedDict):
    id: UUID
    course_id: UUID
    lesson_title: str
    position: int


__all__ = ["CourseRow", "LessonRow"]
