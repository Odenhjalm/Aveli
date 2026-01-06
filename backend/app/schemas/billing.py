from datetime import datetime
from enum import Enum

from pydantic import AliasChoices, BaseModel, Field, field_validator


class SubscriptionInterval(str, Enum):
    month = "month"
    year = "year"


class SubscriptionSessionRequest(BaseModel):
    interval: SubscriptionInterval = Field(
        validation_alias=AliasChoices("interval", "plan_interval")
    )


class SubscriptionCheckoutResponse(BaseModel):
    checkout_url: str


class SubscriptionCancelRequest(BaseModel):
    subscription_id: str | None = None


class SubscriptionCancelResponse(BaseModel):
    subscription_id: str
    status: str
    cancel_at_period_end: bool = False
    current_period_end: datetime | None = None


class BillingPortalResponse(BaseModel):
    url: str


class CheckoutSessionRequest(BaseModel):
    plan: SubscriptionInterval = Field(validation_alias=AliasChoices("plan", "interval"))

    @field_validator("plan", mode="before")
    @classmethod
    def _normalize_plan(cls, value):
        if isinstance(value, str):
            lowered = value.lower()
            if lowered in {"monthly", "month"}:
                return SubscriptionInterval.month
            if lowered in {"yearly", "annual", "year"}:
                return SubscriptionInterval.year
        return value


class CheckoutSessionResponse(BaseModel):
    url: str


class SessionStatusResponse(BaseModel):
    ok: bool = True
    session_id: str
    mode: str | None = None
    payment_status: str | None = None
    subscription_status: str | None = None
    membership_status: str | None = None
    updated_at: datetime | None = None
    poll_after_ms: int = 2000

