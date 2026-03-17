from __future__ import annotations

import pytest

from app.schemas.onboarding import OnboardingState
from app.services import onboarding_service

pytestmark = pytest.mark.anyio("asyncio")


async def _stub_onboarding_state(
    monkeypatch,
    *,
    email_verified: bool,
    membership: dict | None,
    profile: dict | None,
    onboarding_row: dict | None,
    selected_course: dict | None = None,
):
    async def fake_get_user_by_id(_: str):
        return {
            "id": "user-1",
            "email_confirmed_at": "2026-03-16T10:00:00Z" if email_verified else None,
            "confirmed_at": None,
        }

    async def fake_get_profile(_: str):
        return profile

    async def fake_get_latest_subscription(_: str):
        return membership

    async def fake_get_user_onboarding(_: str):
        return onboarding_row

    async def fake_get_course(course_id: str):
        if selected_course is None:
            return None
        if selected_course.get("id") == course_id:
            return selected_course
        return None

    monkeypatch.setattr(onboarding_service.auth_repo, "get_user_by_id", fake_get_user_by_id)
    monkeypatch.setattr(onboarding_service.profiles_repo, "get_profile", fake_get_profile)
    monkeypatch.setattr(
        onboarding_service.memberships_repo,
        "get_latest_subscription",
        fake_get_latest_subscription,
    )
    monkeypatch.setattr(
        onboarding_service.onboarding_repo,
        "get_user_onboarding",
        fake_get_user_onboarding,
    )
    monkeypatch.setattr(onboarding_service.courses_repo, "get_course", fake_get_course)


@pytest.mark.parametrize(
    ("name", "email_verified", "membership", "profile", "onboarding_row", "selected_course", "expected_state", "expected_step"),
    [
        (
            "registered_unverified",
            False,
            None,
            {"display_name": "", "bio": "", "avatar_media_id": None},
            None,
            None,
            OnboardingState.registered_unverified,
            onboarding_service.VERIFY_ROUTE,
        ),
        (
            "verified_unpaid",
            True,
            None,
            {"display_name": "", "bio": "", "avatar_media_id": None},
            None,
            None,
            OnboardingState.verified_unpaid,
            onboarding_service.SUBSCRIBE_ROUTE,
        ),
        (
            "paid_profile_incomplete",
            True,
            {"status": "active", "end_date": None},
            {"display_name": "Aveli", "bio": "Hej", "avatar_media_id": None},
            None,
            None,
            OnboardingState.paid_profile_incomplete,
            onboarding_service.CREATE_PROFILE_ROUTE,
        ),
        (
            "paid_profile_complete_intro_unselected",
            True,
            {"status": "active", "end_date": None},
            {"display_name": "Aveli", "bio": "Hej", "avatar_media_id": "avatar-1"},
            {"profile_completed_at": "2026-03-16T10:00:00Z"},
            None,
            OnboardingState.paid_profile_complete_intro_unselected,
            onboarding_service.SELECT_INTRO_ROUTE,
        ),
        (
            "paid_profile_complete_intro_selected",
            True,
            {"status": "active", "end_date": None},
            {"display_name": "Aveli", "bio": "Hej", "avatar_media_id": "avatar-1"},
            {
                "profile_completed_at": "2026-03-16T10:00:00Z",
                "selected_intro_course_id": "course-1",
            },
            {"id": "course-1", "is_free_intro": True, "is_published": True},
            OnboardingState.paid_profile_complete_intro_selected,
            onboarding_service.WELCOME_ROUTE,
        ),
        (
            "onboarding_complete",
            True,
            {"status": "active", "end_date": None},
            {"display_name": "Aveli", "bio": "Hej", "avatar_media_id": "avatar-1"},
            {
                "profile_completed_at": "2026-03-16T10:00:00Z",
                "selected_intro_course_id": "course-1",
                "onboarding_completed_at": "2026-03-16T10:05:00Z",
            },
            {"id": "course-1", "is_free_intro": True, "is_published": True},
            OnboardingState.onboarding_complete,
            onboarding_service.HOME_ROUTE,
        ),
    ],
)
async def test_get_onboarding_payload_derives_all_states(
    monkeypatch,
    *,
    name: str,
    email_verified: bool,
    membership: dict | None,
    profile: dict | None,
    onboarding_row: dict | None,
    selected_course: dict | None,
    expected_state: OnboardingState,
    expected_step: str,
):
    del name
    await _stub_onboarding_state(
        monkeypatch,
        email_verified=email_verified,
        membership=membership,
        profile=profile,
        onboarding_row=onboarding_row,
        selected_course=selected_course,
    )

    payload = await onboarding_service.get_onboarding_payload("user-1")

    assert payload.onboarding_state is expected_state
    assert payload.next_step == expected_step


async def test_mark_profile_completed_only_marks_when_required_fields_exist(monkeypatch):
    marked: list[str] = []

    async def fake_ensure(_: str):
        return None

    async def fake_get_profile(_: str):
        return {"display_name": "Aveli", "bio": "Hej", "avatar_media_id": "avatar-1"}

    async def fake_mark_profile_completed(user_id: str):
        marked.append(user_id)
        return {"profile_completed_at": "2026-03-16T10:00:00Z"}

    async def fake_get_payload(_: str):
        return "payload"

    monkeypatch.setattr(onboarding_service.onboarding_repo, "ensure_user_onboarding", fake_ensure)
    monkeypatch.setattr(onboarding_service.profiles_repo, "get_profile", fake_get_profile)
    monkeypatch.setattr(
        onboarding_service.onboarding_repo,
        "mark_profile_completed",
        fake_mark_profile_completed,
    )
    monkeypatch.setattr(onboarding_service, "get_onboarding_payload", fake_get_payload)

    payload = await onboarding_service.mark_profile_completed_if_ready("user-1")

    assert payload == "payload"
    assert marked == ["user-1"]


async def test_select_intro_course_rejects_invalid_course(monkeypatch):
    async def fake_ensure(_: str):
        return None

    async def fake_get_course(*, course_id: str):
        assert course_id == "course-1"
        return {"id": "course-1", "is_free_intro": False, "is_published": True}

    monkeypatch.setattr(onboarding_service.onboarding_repo, "ensure_user_onboarding", fake_ensure)
    monkeypatch.setattr(onboarding_service.courses_repo, "get_course", fake_get_course)

    with pytest.raises(onboarding_service.OnboardingError) as excinfo:
        await onboarding_service.select_intro_course("user-1", course_id="course-1")

    assert excinfo.value.detail == "Selected course is not a published intro course"


async def test_complete_onboarding_requires_all_prerequisites(monkeypatch):
    async def fake_ensure(_: str):
        return None

    async def fake_get_payload(_: str):
        return type(
            "Payload",
            (),
            {
                "email_verified": True,
                "membership_active": True,
                "profile_complete": True,
                "intro_course_selected": False,
            },
        )()

    monkeypatch.setattr(onboarding_service.onboarding_repo, "ensure_user_onboarding", fake_ensure)
    monkeypatch.setattr(onboarding_service, "get_onboarding_payload", fake_get_payload)

    with pytest.raises(onboarding_service.OnboardingError) as excinfo:
        await onboarding_service.complete_onboarding("user-1")

    assert excinfo.value.detail == "Intro course selection is required"


async def test_complete_onboarding_marks_terminal_state(monkeypatch):
    state = {"completed": False}

    async def fake_ensure(_: str):
        return None

    async def fake_mark_completed(_: str):
        state["completed"] = True
        return {"onboarding_completed_at": "2026-03-16T10:05:00Z"}

    async def fake_get_payload(_: str):
        if not state["completed"]:
            return type(
                "Payload",
                (),
                {
                    "email_verified": True,
                    "membership_active": True,
                    "profile_complete": True,
                    "intro_course_selected": True,
                    "onboarding_complete": False,
                },
            )()
        return type(
            "Payload",
            (),
            {
                "email_verified": True,
                "membership_active": True,
                "profile_complete": True,
                "intro_course_selected": True,
                "onboarding_complete": True,
            },
        )()

    monkeypatch.setattr(onboarding_service.onboarding_repo, "ensure_user_onboarding", fake_ensure)
    monkeypatch.setattr(
        onboarding_service.onboarding_repo,
        "mark_onboarding_completed",
        fake_mark_completed,
    )
    monkeypatch.setattr(onboarding_service, "get_onboarding_payload", fake_get_payload)

    payload = await onboarding_service.complete_onboarding("user-1")

    assert state["completed"] is True
    assert payload.onboarding_complete is True
