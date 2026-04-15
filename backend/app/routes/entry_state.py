from __future__ import annotations

from typing import Any, Mapping

from fastapi import APIRouter

from .. import schemas
from ..auth import CurrentUser
from ..repositories import memberships as memberships_repo
from ..utils.membership_status import is_membership_row_active

router = APIRouter(tags=["entry-state"])


async def build_entry_state(
    current: Mapping[str, Any],
) -> schemas.EntryStateResponse:
    membership = await memberships_repo.get_membership(str(current["id"]))
    onboarding_state = current.get("onboarding_state")
    onboarding_completed = onboarding_state == "completed"
    membership_active = is_membership_row_active(membership)
    can_enter_app = onboarding_completed and membership_active

    return schemas.EntryStateResponse(
        can_enter_app=can_enter_app,
        onboarding_state=onboarding_state,
        onboarding_completed=onboarding_completed,
        membership_active=membership_active,
        needs_onboarding=not onboarding_completed,
        needs_payment=not membership_active,
        role_v2=current.get("role_v2"),
        role=current.get("role"),
        is_admin=current.get("is_admin"),
    )


@router.get("/entry-state", response_model=schemas.EntryStateResponse)
async def get_entry_state(current: CurrentUser) -> schemas.EntryStateResponse:
    return await build_entry_state(current)
