from __future__ import annotations

from typing import Any, Mapping

from fastapi import status

from .. import models
from ..repositories import auth as auth_repo
from ..repositories import courses as courses_repo
from ..repositories import memberships as memberships_repo
from ..repositories import onboarding as onboarding_repo
from ..repositories import profiles as profiles_repo
from ..schemas.onboarding import OnboardingPayload, OnboardingState
from ..utils.membership_status import is_membership_row_active

VERIFY_ROUTE = "/verify"
SUBSCRIBE_ROUTE = "/subscribe"
CREATE_PROFILE_ROUTE = "/create-profile"
SELECT_INTRO_ROUTE = "/select-intro-course"
WELCOME_ROUTE = "/welcome"
HOME_ROUTE = "/home"
RESUME_ONBOARDING_ROUTE = "/resume-onboarding"

_PROFILE_FIELD_LABELS = {
    "display_name": "display_name",
    "bio": "bio",
    "avatar": "avatar",
}
_BILLING_PENDING_STATUSES = {"incomplete", "past_due", "unpaid", "trialing", "active"}


class OnboardingError(Exception):
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, detail: str, *, status_code: int | None = None) -> None:
        super().__init__(detail)
        if status_code is not None:
            self.status_code = status_code
        self.detail = detail


async def ensure_onboarding_row(user_id: str) -> None:
    await onboarding_repo.ensure_user_onboarding(user_id)


def _missing_profile_fields(profile: Mapping[str, Any] | None) -> list[str]:
    if not profile:
        return list(_PROFILE_FIELD_LABELS.values())

    missing: list[str] = []
    display_name = str(profile.get("display_name") or "").strip()
    if not display_name:
        missing.append(_PROFILE_FIELD_LABELS["display_name"])

    bio = str(profile.get("bio") or "").strip()
    if not bio:
        missing.append(_PROFILE_FIELD_LABELS["bio"])

    avatar_media_id = profile.get("avatar_media_id")
    if not avatar_media_id:
        missing.append(_PROFILE_FIELD_LABELS["avatar"])

    return missing


async def _resolve_selected_intro_course_id(course_id: str | None) -> str | None:
    if not course_id:
        return None
    course = await courses_repo.get_course(course_id=course_id)
    if not course:
        return None
    if not bool(course.get("is_free_intro")):
        return None
    if not bool(course.get("is_published")):
        return None
    return str(course.get("id") or course_id)


def _billing_pending(membership: Mapping[str, Any] | None) -> bool:
    if not membership:
        return False
    status_value = str(membership.get("status") or "").strip().lower()
    return bool(status_value) and status_value in _BILLING_PENDING_STATUSES


def _state_and_next_step(
    *,
    email_verified: bool,
    membership_active: bool,
    profile_complete: bool,
    intro_course_selected: bool,
    onboarding_complete: bool,
) -> tuple[OnboardingState, str]:
    if onboarding_complete:
        return OnboardingState.onboarding_complete, HOME_ROUTE
    if not email_verified:
        return OnboardingState.registered_unverified, VERIFY_ROUTE
    if not membership_active:
        return OnboardingState.verified_unpaid, SUBSCRIBE_ROUTE
    if not profile_complete:
        return OnboardingState.paid_profile_incomplete, CREATE_PROFILE_ROUTE
    if not intro_course_selected:
        return (
            OnboardingState.paid_profile_complete_intro_unselected,
            SELECT_INTRO_ROUTE,
        )
    return (
        OnboardingState.paid_profile_complete_intro_selected,
        WELCOME_ROUTE,
    )


async def get_onboarding_payload(user_id: str) -> OnboardingPayload:
    user = await auth_repo.get_user_by_id(user_id)
    if not user:
        raise OnboardingError("User not found", status_code=status.HTTP_404_NOT_FOUND)

    profile = await profiles_repo.get_profile(user_id)
    membership = await memberships_repo.get_latest_subscription(user_id)
    onboarding = await onboarding_repo.get_user_onboarding(user_id)

    profile_completed_at = onboarding.get("profile_completed_at") if onboarding else None
    missing_profile_fields = [] if profile_completed_at else _missing_profile_fields(profile)
    selected_intro_course_id = await _resolve_selected_intro_course_id(
        str(onboarding.get("selected_intro_course_id")) if onboarding and onboarding.get("selected_intro_course_id") else None
    )
    email_verified = bool(user.get("email_confirmed_at") or user.get("confirmed_at"))
    membership_active = is_membership_row_active(membership)
    profile_complete = bool(profile_completed_at) or not missing_profile_fields
    intro_course_selected = selected_intro_course_id is not None
    onboarding_complete = bool(onboarding and onboarding.get("onboarding_completed_at"))
    onboarding_state, next_step = _state_and_next_step(
        email_verified=email_verified,
        membership_active=membership_active,
        profile_complete=profile_complete,
        intro_course_selected=intro_course_selected,
        onboarding_complete=onboarding_complete,
    )
    return OnboardingPayload(
        onboarding_state=onboarding_state,
        next_step=next_step,
        email_verified=email_verified,
        membership_active=membership_active,
        profile_complete=profile_complete,
        intro_course_selected=intro_course_selected,
        onboarding_complete=onboarding_complete,
        missing_profile_fields=missing_profile_fields,
        selected_intro_course_id=selected_intro_course_id,
        billing_pending=_billing_pending(membership),
    )


async def mark_profile_completed_if_ready(user_id: str) -> OnboardingPayload:
    await onboarding_repo.ensure_user_onboarding(user_id)
    profile = await profiles_repo.get_profile(user_id)
    if not _missing_profile_fields(profile):
        await onboarding_repo.mark_profile_completed(user_id)
    return await get_onboarding_payload(user_id)


async def select_intro_course(
    user_id: str,
    *,
    course_id: str,
) -> OnboardingPayload:
    await onboarding_repo.ensure_user_onboarding(user_id)
    resolved_course_id = await _resolve_selected_intro_course_id(course_id)
    if not resolved_course_id:
        raise OnboardingError(
            "Selected course is not a published intro course",
            status_code=status.HTTP_400_BAD_REQUEST,
        )
    await onboarding_repo.set_selected_intro_course(
        user_id,
        course_id=resolved_course_id,
    )
    return await get_onboarding_payload(user_id)


async def complete_onboarding(user_id: str) -> OnboardingPayload:
    await onboarding_repo.ensure_user_onboarding(user_id)
    payload = await get_onboarding_payload(user_id)
    if not payload.email_verified:
        raise OnboardingError("Email verification is required")
    if not payload.membership_active:
        raise OnboardingError("Active membership is required")
    if not payload.profile_complete:
        raise OnboardingError("Profile is incomplete")
    if not payload.intro_course_selected:
        raise OnboardingError("Intro course selection is required")
    await onboarding_repo.mark_onboarding_completed(user_id)
    return await get_onboarding_payload(user_id)


async def list_intro_courses() -> list[dict[str, Any]]:
    rows = await models.list_intro_courses(limit=12)
    return [dict(row) for row in rows]


__all__ = [
    "CREATE_PROFILE_ROUTE",
    "HOME_ROUTE",
    "OnboardingError",
    "RESUME_ONBOARDING_ROUTE",
    "SELECT_INTRO_ROUTE",
    "SUBSCRIBE_ROUTE",
    "VERIFY_ROUTE",
    "WELCOME_ROUTE",
    "complete_onboarding",
    "ensure_onboarding_row",
    "get_onboarding_payload",
    "list_intro_courses",
    "mark_profile_completed_if_ready",
    "select_intro_course",
]
