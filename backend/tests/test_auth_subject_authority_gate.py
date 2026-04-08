import pytest


pytestmark = pytest.mark.anyio("asyncio")


async def test_build_current_user_prefers_auth_subject_over_payload_claims(
    monkeypatch,
) -> None:
    from app import auth as auth_module

    async def _fake_get_auth_subject(_: str):
        return {
            "user_id": "user-123",
            "onboarding_state": "completed",
            "role_v2": "learner",
            "role": "learner",
            "is_admin": False,
        }

    monkeypatch.setattr(
        "app.repositories.auth_subjects.get_auth_subject",
        _fake_get_auth_subject,
    )

    current_user = await auth_module._build_current_user(
        "user-123",
        {
            "email": "user@example.com",
            "role": "teacher",
            "is_admin": True,
            "display_name": "Payload Name",
            "user_metadata": {
                "display_name": "User Metadata Name",
                "photo_url": "https://example.com/avatar.jpg",
            },
            "app_metadata": {
                "role": "teacher",
                "is_admin": True,
            },
        },
    )

    assert current_user["role"] == "learner"
    assert current_user["role_v2"] == "learner"
    assert current_user["onboarding_state"] == "completed"
    assert current_user["is_admin"] is False
    assert current_user["display_name"] == "Payload Name"


async def test_profiles_set_onboarding_state_delegates_to_auth_subject_authority(
    monkeypatch,
) -> None:
    from app.repositories import profiles as profiles_repo

    calls: list[tuple[str, str]] = []

    async def _fake_set_onboarding_state(user_id: str, onboarding_state: str):
        calls.append((user_id, onboarding_state))
        return {"user_id": user_id}

    async def _fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "email": "teacher@example.com",
            "display_name": "Teacher",
            "bio": None,
            "photo_url": None,
            "avatar_media_id": None,
            "created_at": None,
            "updated_at": None,
        }

    monkeypatch.setattr(
        profiles_repo.auth_subjects_repo,
        "set_onboarding_state",
        _fake_set_onboarding_state,
    )
    monkeypatch.setattr(profiles_repo, "get_profile", _fake_get_profile)

    result = await profiles_repo.set_onboarding_state("teacher-123", "completed")

    assert calls == [("teacher-123", "completed")]
    assert result is not None
    assert result["display_name"] == "Teacher"
    assert "onboarding_state" not in result
    assert "role_v2" not in result
