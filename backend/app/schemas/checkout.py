from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel, model_validator

from .billing import SubscriptionInterval


class CheckoutType(str, Enum):
    course = "course"
    service = "service"
    subscription = "subscription"


class CheckoutCreateRequest(BaseModel):
    type: CheckoutType
    slug: Optional[str] = None
    interval: Optional[SubscriptionInterval] = None

    @model_validator(mode="after")
    def _validate_fields(self):
        if self.type in {CheckoutType.course, CheckoutType.service} and not self.slug:
            raise ValueError("slug is required for course and service checkouts")
        if self.type is CheckoutType.subscription and not self.interval:
            raise ValueError("interval is required for subscriptions")
        return self


class CheckoutCreateResponse(BaseModel):
    url: str
    session_id: Optional[str] = None
    order_id: Optional[str] = None


class CheckoutVerifyResponse(BaseModel):
    ok: bool = True
    session_id: str
    success: bool
    status: str
    mode: Optional[str] = None
    session_status: Optional[str] = None
    payment_status: Optional[str] = None
    checkout_type: Optional[str] = None
    order_id: Optional[str] = None
    course_slug: Optional[str] = None
    service_slug: Optional[str] = None
    customer_id: Optional[str] = None
