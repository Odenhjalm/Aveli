from __future__ import annotations

from fastapi import APIRouter

from .. import schemas
from ..auth import CurrentUser, is_app_entry_allowed
from ..repositories import memberships as memberships_repo
from ..utils.membership_status import is_membership_row_active

router = APIRouter(tags=["entry-state"])


@router.get("/entry-state", response_model=schemas.EntryStateResponse)
async def get_entry_state(current: CurrentUser) -> schemas.EntryStateResponse:
    membership = await memberships_repo.get_membership(str(current["id"]))
    onboarding_completed = current.get("onboarding_state") == "completed"
    membership_active = is_membership_row_active(membership)
    is_invite = bool(
        membership and str(membership.get("source") or "").strip().lower() == "invite"
    )

    return schemas.EntryStateResponse(
        can_enter_app=is_app_entry_allowed(current, membership),
        onboarding_completed=onboarding_completed,
        membership_active=membership_active,
        needs_onboarding=not onboarding_completed,
        needs_payment=not membership_active and not is_invite,
        is_invite=is_invite,
    )
