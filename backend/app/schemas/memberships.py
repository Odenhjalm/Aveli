from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class MembershipRecord(BaseModel):
    membership_id: Optional[str] = None
    user_id: Optional[str] = None
    status: Optional[str] = None
    source: Optional[str] = None
    effective_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    canceled_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class MembershipResponse(BaseModel):
    membership: Optional[MembershipRecord] = None
