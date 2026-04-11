import pytest
from fastapi import HTTPException


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

    async def _fake_get_profile(_: str):
        return {
            "user_id": "user-123",
            "email": "user@example.com",
            "display_name": "Canonical Profile Name",
            "bio": "Canonical bio",
            "photo_url": "/profiles/avatar/media-123",
            "avatar_media_id": "media-123",
            "created_at": None,
            "updated_at": None,
        }

    monkeypatch.setattr(
        "app.repositories.auth_subjects.get_auth_subject",
        _fake_get_auth_subject,
    )
    monkeypatch.setattr(
        "app.repositories.profiles.get_profile",
        _fake_get_profile,
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

    assert current_user == {
        "id": "user-123",
        "email": "user@example.com",
        "onboarding_state": "completed",
        "role": "learner",
        "role_v2": "learner",
        "is_admin": False,
        "display_name": "Canonical Profile Name",
        "bio": "Canonical bio",
        "photo_url": "/profiles/avatar/media-123",
    }


async def test_build_current_user_does_not_fallback_to_supabase_metadata(
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

    async def _fake_get_profile(_: str):
        return None

    monkeypatch.setattr(
        "app.repositories.auth_subjects.get_auth_subject",
        _fake_get_auth_subject,
    )
    monkeypatch.setattr("app.repositories.profiles.get_profile", _fake_get_profile)

    current_user = await auth_module._build_current_user(
        "user-123",
        {
            "email": "user@example.com",
            "display_name": "Payload Name",
            "avatar_url": "https://example.com/avatar.jpg",
            "user_metadata": {
                "display_name": "User Metadata Name",
                "photo_url": "https://example.com/avatar.jpg",
                "bio": "Metadata bio",
            },
            "app_metadata": {"role": "teacher", "is_admin": True},
        },
    )

    assert current_user == {
        "id": "user-123",
        "email": "user@example.com",
        "onboarding_state": "completed",
        "role": "learner",
        "role_v2": "learner",
        "is_admin": False,
        "display_name": None,
        "bio": None,
        "photo_url": None,
    }


async def test_build_current_user_rejects_invalid_canonical_subject(monkeypatch) -> None:
    from app import auth as auth_module

    async def _fake_get_auth_subject(_: str):
        return {
            "user_id": "user-123",
            "onboarding_state": "broken_state",
            "role_v2": "teacher",
            "role": "learner",
            "is_admin": False,
        }

    monkeypatch.setattr(
        "app.repositories.auth_subjects.get_auth_subject",
        _fake_get_auth_subject,
    )

    async def _fake_get_profile(_: str):
        return None

    monkeypatch.setattr("app.repositories.profiles.get_profile", _fake_get_profile)

    with pytest.raises(ValueError, match="Canonical onboarding_state invalid"):
        await auth_module._build_current_user(
            "user-123",
            {"email": "user@example.com"},
        )


async def test_require_admin_ignores_current_user_is_admin_flag_when_canonical_is_false(
    monkeypatch,
) -> None:
    from app import permissions

    async def _fake_is_admin_user(_: str) -> bool:
        return False

    monkeypatch.setattr("app.models.is_admin_user", _fake_is_admin_user)

    with pytest.raises(HTTPException, match="admin_required") as exc_info:
        await permissions.require_admin({"id": "user-123", "is_admin": True})

    assert exc_info.value.status_code == 403


async def test_require_admin_denies_role_only_entry_even_when_canonical_admin_is_true(
    monkeypatch,
) -> None:
    from app import permissions

    async def _fake_is_admin_user(_: str) -> bool:
        return True

    monkeypatch.setattr("app.models.is_admin_user", _fake_is_admin_user)

    current = {"id": "user-123", "is_admin": False}
    with pytest.raises(HTTPException, match="canonical_app_entry_required") as exc_info:
        await permissions.require_admin(current)

    assert exc_info.value.status_code == 403


async def test_require_teacher_ignores_current_user_role_when_canonical_is_false(
    monkeypatch,
) -> None:
    from app import permissions

    async def _fake_is_teacher_user(_: str) -> bool:
        return False

    monkeypatch.setattr("app.models.is_teacher_user", _fake_is_teacher_user)

    with pytest.raises(HTTPException, match="forbidden") as exc_info:
        await permissions.require_teacher({"id": "user-123", "role": "teacher"})

    assert exc_info.value.status_code == 403


async def test_require_teacher_denies_role_only_entry_even_when_canonical_teacher_is_true(
    monkeypatch,
) -> None:
    from app import permissions

    async def _fake_is_teacher_user(_: str) -> bool:
        return True

    monkeypatch.setattr("app.models.is_teacher_user", _fake_is_teacher_user)

    current = {"id": "user-123", "role": "learner"}
    with pytest.raises(HTTPException, match="canonical_app_entry_required") as exc_info:
        await permissions.require_teacher(current)

    assert exc_info.value.status_code == 403
