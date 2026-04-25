from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class DeviceRegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    push_token: str = Field(min_length=1)
    platform: str = Field(min_length=1)

    @field_validator("push_token", "platform")
    @classmethod
    def _strip_required_text(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("value must not be blank")
        return normalized


class DeviceRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    user_id: UUID
    push_token: str
    platform: str
    active: bool
    created_at: datetime


class NotificationHeaderItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    subtitle: str | None = None
    cta_label: str | None = None
    cta_url: str | None = None


class NotificationListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    show_notifications_bar: bool
    notifications: list[NotificationHeaderItem]


class NotificationPreferenceRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: str
    push_enabled: bool
    in_app_enabled: bool


class NotificationPreferenceListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[NotificationPreferenceRecord]


class NotificationPreferenceUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    push_enabled: bool
    in_app_enabled: bool
