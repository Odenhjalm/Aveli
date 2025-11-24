from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class MembershipRecord(BaseModel):
    status: Optional[str] = None
    plan_interval: Optional[str] = None
    price_id: Optional[str] = None
    stripe_customer_id: Optional[str] = None
    stripe_subscription_id: Optional[str] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class MembershipResponse(BaseModel):
    membership: Optional[MembershipRecord] = None
