import pytest
from datetime import datetime, timezone
from uuid import uuid4


pytestmark = pytest.mark.anyio("asyncio")


async def test_profile_response_reports_membership_as_sole_app_entry_authority(
    monkeypatch,
) -> None:
    from app.routes import profiles as profile_routes

    user_id = str(uuid4())
    now = datetime.now(timezone.utc)

    async def _fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "email": "teacher@example.com",
            "display_name": "Teacher",
            "bio": None,
            "photo_url": None,
            "avatar_media_id": None,
            "created_at": now,
            "updated_at": now,
        }

    monkeypatch.setattr(profile_routes.models, "get_profile", _fake_get_profile)

    profile = await profile_routes.get_me(current_user={"id": user_id})
    payload = profile.model_dump()

    assert set(payload) == {
        "user_id",
        "email",
        "display_name",
        "bio",
        "photo_url",
        "avatar_media_id",
        "created_at",
        "updated_at",
    }


async def test_domain_observability_keeps_enrollment_separate_from_app_entry(
    monkeypatch,
) -> None:
    from app.services.domain_observability import user_inspection

    async def _fake_get_user_by_id(_: str):
        return {
            "id": "user-123",
            "email": "learner@example.com",
            "email_confirmed_at": "2026-04-07T12:00:00+00:00",
        }

    async def _fake_get_auth_subject(_: str):
        return {
            "user_id": "user-123",
            "onboarding_state": "completed",
            "role_v2": "learner",
            "role": "learner",
            "is_admin": False,
        }

    async def _fake_get_profile(_: str):
        return {
            "user_id": "user-123",
            "email": "learner@example.com",
            "display_name": "Learner",
        }

    async def _fake_get_membership(_: str):
        return None

    async def _fake_list_courses(**_: object):
        return []

    async def _fake_list_my_courses(_: str):
        return [{"id": "course-enrolled"}]

    async def _fake_derive_onboarding_state(_: str) -> str:
        return "completed"

    monkeypatch.setattr(
        user_inspection.auth_repo, "get_user_by_id", _fake_get_user_by_id
    )
    monkeypatch.setattr(
        user_inspection.auth_subjects_repo, "get_auth_subject", _fake_get_auth_subject
    )
    monkeypatch.setattr(
        user_inspection.profiles_repo, "get_profile", _fake_get_profile
    )
    monkeypatch.setattr(
        user_inspection.memberships_repo, "get_membership", _fake_get_membership
    )
    monkeypatch.setattr(user_inspection.courses_repo, "list_courses", _fake_list_courses)
    monkeypatch.setattr(
        user_inspection.courses_repo, "list_my_courses", _fake_list_my_courses
    )
    monkeypatch.setattr(
        user_inspection.onboarding_state,
        "derive_onboarding_state",
        _fake_derive_onboarding_state,
    )

    result = await user_inspection.inspect_user("user-123")

    assert result["truth_sources"]["app_entry"]["authority"] == "memberships"
    assert result["truth_sources"]["app_entry"]["membership_active"] is False
    assert result["truth_sources"]["auth_subject"]["authority"] == "auth_subjects"
    assert result["truth_sources"]["courses"]["enrolled_course_ids"] == [
        "course-enrolled"
    ]
    assert result["state_summary"]["app_entry_state"] == "missing"
