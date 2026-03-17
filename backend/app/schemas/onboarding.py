from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


class OnboardingState(str, Enum):
    registered_unverified = "registered_unverified"
    verified_unpaid = "verified_unpaid"
    paid_profile_incomplete = "paid_profile_incomplete"
    paid_profile_complete_intro_unselected = (
        "paid_profile_complete_intro_unselected"
    )
    paid_profile_complete_intro_selected = "paid_profile_complete_intro_selected"
    onboarding_complete = "onboarding_complete"


class OnboardingPayload(BaseModel):
    onboarding_state: OnboardingState
    next_step: str
    email_verified: bool
    membership_active: bool
    profile_complete: bool
    intro_course_selected: bool
    onboarding_complete: bool
    missing_profile_fields: list[str] = Field(default_factory=list)
    selected_intro_course_id: str | None = None
    billing_pending: bool = False


class IntroCourseSelectionRequest(BaseModel):
    course_id: str


class VerifyEmailResponse(BaseModel):
    status: str
    onboarding: OnboardingPayload | None = None
    redirect_after_login: str | None = None
