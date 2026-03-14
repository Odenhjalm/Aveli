from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Mapping

from .. import repositories
from ..utils.membership_status import is_membership_row_active

REGISTERED_UNVERIFIED = "registered_unverified"
VERIFIED_UNPAID = "verified_unpaid"
ACCESS_ACTIVE_PROFILE_INCOMPLETE = "access_active_profile_incomplete"
ACCESS_ACTIVE_PROFILE_COMPLETE = "access_active_profile_complete"
WELCOMED = "welcomed"


async def derive_onboarding_state(user_id: str) -> str:
    profile = await repositories.get_profile(user_id)
    if not profile:
        raise ValueError("Profile missing")

    current_state = str(profile.get("onboarding_state") or "")
    if current_state == WELCOMED:
        return WELCOMED

    user = await repositories.get_user_by_id(user_id)
    if not _is_email_verified(user):
        return REGISTERED_UNVERIFIED

    membership = await repositories.get_membership(user_id)
    if not is_membership_row_active(membership):
        return VERIFIED_UNPAID

    if not _is_profile_complete(profile):
        return ACCESS_ACTIVE_PROFILE_INCOMPLETE

    return ACCESS_ACTIVE_PROFILE_COMPLETE


async def sync_onboarding_state(user_id: str) -> str:
    profile = await repositories.get_profile(user_id)
    if not profile:
        raise ValueError("Profile missing")

    next_state = await derive_onboarding_state(user_id)
    if profile.get("onboarding_state") == next_state:
        return next_state

    await repositories.set_onboarding_state(user_id, next_state)
    return next_state


def _is_email_verified(user: Mapping[str, Any] | None) -> bool:
    if not user:
        return False
    return bool(user.get("email_confirmed_at") or user.get("confirmed_at"))


def _is_profile_complete(profile: Mapping[str, Any]) -> bool:
    display_name = str(profile.get("display_name") or "").strip()
    if not display_name:
        return False

    # Signup already captures a name, but we only consider the onboarding profile
    # step complete after the user has explicitly saved the profile once.
    created_at = _normalize_datetime(profile.get("created_at"))
    updated_at = _normalize_datetime(profile.get("updated_at"))
    if created_at and updated_at:
        return updated_at > created_at
    return True


def _normalize_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None

