from __future__ import annotations

from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class CourseBundleCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=2)
    price_amount_cents: int = Field(ge=1)
    course_ids: List[str] = Field(default_factory=list)


class CourseBundleUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: Optional[str] = Field(default=None, min_length=2)
    price_amount_cents: Optional[int] = Field(default=None, ge=1)
    course_ids: Optional[List[str]] = None


class CourseBundleCourseRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_id: str
    position: Optional[int] = Field(default=None, ge=1)


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
    price_amount_cents: Optional[int] = None
    courses: List[CourseBundleCourse] = Field(default_factory=list)


class CourseBundleListResponse(BaseModel):
    items: List[CourseBundleResponse]
