from __future__ import annotations

from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class EventType(str, Enum):
    ceremony = "ceremony"
    live_class = "live_class"
    course = "course"


class EventStatus(str, Enum):
    draft = "draft"
    scheduled = "scheduled"
    live = "live"
    completed = "completed"
    cancelled = "cancelled"


class EventVisibility(str, Enum):
    public = "public"
    members = "members"
    invited = "invited"


class EventCreateRequest(BaseModel):
    type: EventType
    title: str = Field(min_length=1)
    description: str | None = None
    image_id: UUID | None = None
    start_at: datetime
    end_at: datetime
    timezone: str = Field(min_length=1)
    status: EventStatus = EventStatus.draft
    visibility: EventVisibility = EventVisibility.invited

    @field_validator("start_at", "end_at")
    @classmethod
    def _require_tz(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("Timestamp must include timezone (UTC recommended)")
        return value

    @model_validator(mode="after")
    def _validate_times(self) -> "EventCreateRequest":
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        return self


class EventUpdateRequest(BaseModel):
    type: EventType | None = None
    title: str | None = Field(default=None, min_length=1)
    description: str | None = None
    image_id: UUID | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    timezone: str | None = Field(default=None, min_length=1)
    status: EventStatus | None = None
    visibility: EventVisibility | None = None

    @field_validator("start_at", "end_at")
    @classmethod
    def _require_tz(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("Timestamp must include timezone (UTC recommended)")
        return value


class EventRecord(BaseModel):
    id: UUID
    type: EventType
    title: str
    description: str | None = None
    image_id: UUID | None = None
    start_at: datetime
    end_at: datetime
    timezone: str
    status: EventStatus
    visibility: EventVisibility
    created_by: UUID
    created_at: datetime
    updated_at: datetime


class EventListResponse(BaseModel):
    items: list[EventRecord]


class EventParticipantRole(str, Enum):
    host = "host"
    participant = "participant"


class EventParticipantStatus(str, Enum):
    registered = "registered"
    cancelled = "cancelled"
    attended = "attended"
    no_show = "no_show"


class EventParticipantCreateRequest(BaseModel):
    user_id: UUID | None = None
    role: EventParticipantRole = EventParticipantRole.participant


class EventParticipantRecord(BaseModel):
    id: UUID
    event_id: UUID
    user_id: UUID
    role: EventParticipantRole
    status: EventParticipantStatus
    registered_at: datetime

