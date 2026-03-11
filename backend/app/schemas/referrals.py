from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ReferralCodeCreateRequest(BaseModel):
    email: str
    free_days: int | None = Field(default=None, ge=1)
    free_months: int | None = Field(default=None, ge=1)

    @model_validator(mode="after")
    def _validate_duration(self) -> "ReferralCodeCreateRequest":
        has_days = self.free_days is not None
        has_months = self.free_months is not None
        if has_days == has_months:
            raise ValueError("Provide exactly one of free_days or free_months")
        return self


class ReferralCodeRecord(BaseModel):
    id: UUID
    code: str
    teacher_id: UUID
    email: str
    free_days: int | None = None
    free_months: int | None = None
    active: bool
    redeemed_by_user_id: UUID | None = None
    redeemed_at: datetime | None = None
    created_at: datetime


class ReferralCodeCreateResponse(BaseModel):
    referral: ReferralCodeRecord
    email_delivery: str
