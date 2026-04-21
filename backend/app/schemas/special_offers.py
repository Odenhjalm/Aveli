from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class SpecialOfferBase(BaseModel):
    model_config = ConfigDict(extra="forbid")

    price_amount_cents: int = Field(ge=1)


class SpecialOfferCreate(SpecialOfferBase):
    course_ids: list[UUID] = Field(default_factory=list)


class SpecialOfferUpdateCourses(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_ids: list[UUID] = Field(default_factory=list)


class SpecialOfferUpdatePrice(SpecialOfferBase):
    pass


class SpecialOfferCourse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_id: UUID
    position: int = Field(ge=1)


class SpecialOfferRead(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    teacher_id: UUID
    price_amount_cents: int = Field(ge=1)
    state_hash: str = Field(min_length=64, max_length=64)
    courses: list[SpecialOfferCourse] = Field(default_factory=list)


__all__ = [
    "SpecialOfferBase",
    "SpecialOfferCourse",
    "SpecialOfferCreate",
    "SpecialOfferRead",
    "SpecialOfferUpdateCourses",
    "SpecialOfferUpdatePrice",
]
