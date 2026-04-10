from __future__ import annotations

from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class CourseBundleCreateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    title: str = Field(min_length=2)
    description: Optional[str] = None
    price_amount_cents: int = Field(ge=1)
    course_ids: List[str] = Field(default_factory=list)


class CourseBundleCourseRequest(BaseModel):
    course_id: str
    position: Optional[int] = Field(default=None, ge=0)


class CourseBundleCourse(BaseModel):
    course_id: UUID
    slug: Optional[str] = None
    title: Optional[str] = None
    position: int
    price_amount_cents: Optional[int] = None


class CourseBundleResponse(BaseModel):
    id: UUID
    teacher_id: UUID
    title: str
    description: Optional[str] = None
    price_amount_cents: Optional[int] = None
    courses: List[CourseBundleCourse] = Field(default_factory=list)


class CourseBundleListResponse(BaseModel):
    items: List[CourseBundleResponse]
