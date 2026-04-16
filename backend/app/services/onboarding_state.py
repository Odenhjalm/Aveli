from __future__ import annotations

from .. import repositories

_VALID_ONBOARDING_STATES = frozenset({"incomplete", "welcome_pending", "completed"})


async def derive_onboarding_state(user_id: str) -> str:
    auth_subject = await repositories.get_auth_subject(user_id)
    if not auth_subject:
        raise ValueError("Auth subject missing")
    current_state = str(auth_subject.get("onboarding_state") or "").strip().lower()
    if current_state not in _VALID_ONBOARDING_STATES:
        raise ValueError("Invalid canonical onboarding_state")
    return current_state


async def sync_onboarding_state(user_id: str) -> str:
    return await derive_onboarding_state(user_id)
