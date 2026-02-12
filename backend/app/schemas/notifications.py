from __future__ import annotations

from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class NotificationType(str, Enum):
    manual = "manual"
    scheduled = "scheduled"
    system = "system"


class NotificationChannel(str, Enum):
    in_app = "in_app"
    email = "email"


class NotificationStatus(str, Enum):
    pending = "pending"
    sent = "sent"
    failed = "failed"


class NotificationAudienceType(str, Enum):
    all_members = "all_members"
    event_participants = "event_participants"
    course_participants = "course_participants"
    course_members = "course_members"


class NotificationAudienceCreate(BaseModel):
    audience_type: NotificationAudienceType
    event_id: UUID | None = None
    course_id: UUID | None = None

    @model_validator(mode="after")
    def _validate_target(self) -> "NotificationAudienceCreate":
        if self.audience_type == NotificationAudienceType.event_participants:
            if self.event_id is None:
                raise ValueError("event_id is required when audience_type=event_participants")
            if self.course_id is not None:
                raise ValueError("course_id must be null when audience_type=event_participants")
        elif self.audience_type in {
            NotificationAudienceType.course_participants,
            NotificationAudienceType.course_members,
        }:
            if self.course_id is None:
                raise ValueError("course_id is required when audience_type is a course audience")
            if self.event_id is not None:
                raise ValueError("event_id must be null when audience_type is a course audience")
        elif self.audience_type == NotificationAudienceType.all_members:
            if self.event_id is not None or self.course_id is not None:
                raise ValueError("event_id/course_id must be null when audience_type=all_members")
        return self


class NotificationCreateRequest(BaseModel):
    type: NotificationType = NotificationType.manual
    channel: NotificationChannel = NotificationChannel.in_app
    title: str = Field(min_length=1)
    body: str = Field(min_length=1)
    send_at: datetime | None = None
    audiences: list[NotificationAudienceCreate] = Field(min_length=1)

    @field_validator("send_at")
    @classmethod
    def _require_tz(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("send_at must include timezone (UTC recommended)")
        return value


class NotificationAudienceRecord(BaseModel):
    id: UUID
    notification_id: UUID
    audience_type: NotificationAudienceType
    event_id: UUID | None = None
    course_id: UUID | None = None


class NotificationRecord(BaseModel):
    id: UUID
    type: NotificationType
    channel: NotificationChannel
    title: str
    body: str
    send_at: datetime
    created_by: UUID
    status: NotificationStatus
    created_at: datetime
    audiences: list[NotificationAudienceRecord] = []
    recipient_count: int = 0


class NotificationCreateResponse(BaseModel):
    notification: NotificationRecord


class NotificationListResponse(BaseModel):
    items: list[NotificationRecord]
