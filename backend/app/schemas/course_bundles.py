from __future__ import annotations

from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, Field


class CourseBundleCreateRequest(BaseModel):
    title: str = Field(min_length=2)
    description: Optional[str] = None
    price_amount_cents: int = Field(ge=1)
    currency: str = Field(default="sek", min_length=3, max_length=10)
    course_ids: List[str] = Field(default_factory=list)
    is_active: bool = True


class CourseBundleCourseRequest(BaseModel):
    course_id: str
    position: Optional[int] = Field(default=None, ge=0)


class CourseBundleCourse(BaseModel):
    course_id: UUID
    slug: Optional[str] = None
    title: Optional[str] = None
    position: int
    price_amount_cents: Optional[int] = None
    currency: Optional[str] = None


class CourseBundleResponse(BaseModel):
    id: UUID
    teacher_id: UUID
    title: str
    description: Optional[str] = None
    price_amount_cents: int
    currency: str
    stripe_product_id: Optional[str] = None
    stripe_price_id: Optional[str] = None
    is_active: bool
    courses: List[CourseBundleCourse] = Field(default_factory=list)
    payment_link: Optional[str] = None


class CourseBundleListResponse(BaseModel):
    items: List[CourseBundleResponse]
