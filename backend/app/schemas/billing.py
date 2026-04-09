from datetime import datetime
from enum import Enum

from pydantic import AliasChoices, BaseModel, Field


class SubscriptionInterval(str, Enum):
    month = "month"
    year = "year"


class SubscriptionSessionRequest(BaseModel):
    interval: SubscriptionInterval = Field(
        validation_alias=AliasChoices("interval", "plan_interval")
    )


class SubscriptionCheckoutResponse(BaseModel):
    url: str
    session_id: str
    order_id: str


class SubscriptionCancelRequest(BaseModel):
    subscription_id: str | None = None


class SubscriptionCancelResponse(BaseModel):
    subscription_id: str
    status: str
    cancel_at_period_end: bool = False
    current_period_end: datetime | None = None


class BillingPortalResponse(BaseModel):
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
