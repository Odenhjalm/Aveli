from enum import Enum

from pydantic import BaseModel, Field


class SubscriptionInterval(str, Enum):
    month = "month"
    year = "year"


class SubscriptionSessionRequest(BaseModel):
    interval: SubscriptionInterval = Field(...)


class SubscriptionCheckoutResponse(BaseModel):
    url: str
    session_id: str
    order_id: str


class SubscriptionCancelRequest(BaseModel):
    subscription_id: str | None = None
