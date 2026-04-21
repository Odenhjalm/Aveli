import pytest
from fastapi import HTTPException


pytestmark = pytest.mark.anyio("asyncio")

USER_ID = "00000000-0000-0000-0000-000000000123"


def _patch_canonical_auth_user(monkeypatch) -> None:
    async def _fake_get_user_by_id(user_id: str):
        assert user_id == USER_ID
        return {"id": USER_ID, "email": "user@example.com"}

    monkeypatch.setattr("app.repositories.auth.get_user_by_id", _fake_get_user_by_id)


async def test_build_current_user_prefers_auth_subject_over_payload_claims(
    monkeypatch,
) -> None:
    from app import auth as auth_module

    _patch_canonical_auth_user(monkeypatch)

    async def _fake_get_auth_subject(_: str, *, email: str | None = None):
        assert email == "user@example.com"
        return {
            "user_id": USER_ID,
            "onboarding_state": "completed",
            "role": "learner",
        }

    async def _fake_get_profile(_: str):
        return {
            "user_id": USER_ID,
            "email": "user@example.com",
            "display_name": "Canonical Profile Name",
            "bio": "Canonical bio",
            "photo_url": "/profiles/avatar/media-123",
            "avatar_media_id": "media-123",
            "created_at": None,
            "updated_at": None,
        }

    monkeypatch.setattr(
        "app.repositories.auth_subjects.ensure_authenticated_auth_subject",
        _fake_get_auth_subject,
    )
    monkeypatch.setattr(
        "app.repositories.profiles.get_profile",
        _fake_get_profile,
    )

    current_user = await auth_module._build_current_user(
        USER_ID,
        {
            "email": "user@example.com",
            "role": "teacher",
            "display_name": "Payload Name",
            "user_metadata": {
                "display_name": "User Metadata Name",
                "photo_url": "https://example.com/avatar.jpg",
            },
            "app_metadata": {
                "role": "teacher",
            },
        },
    )

    assert current_user == {
        "id": USER_ID,
        "email": "user@example.com",
        "onboarding_state": "completed",
        "role": "learner",
        "display_name": "Canonical Profile Name",
        "bio": "Canonical bio",
        "photo_url": "/profiles/avatar/media-123",
    }


async def test_build_current_user_does_not_fallback_to_supabase_metadata(
    monkeypatch,
) -> None:
    from app import auth as auth_module

    _patch_canonical_auth_user(monkeypatch)

    async def _fake_get_auth_subject(_: str, *, email: str | None = None):
        assert email == "user@example.com"
        return {
            "user_id": USER_ID,
            "onboarding_state": "completed",
            "role": "learner",
        }

    async def _fake_get_profile(_: str):
        return None

    monkeypatch.setattr(
        "app.repositories.auth_subjects.ensure_authenticated_auth_subject",
        _fake_get_auth_subject,
    )
    monkeypatch.setattr("app.repositories.profiles.get_profile", _fake_get_profile)

    current_user = await auth_module._build_current_user(
        USER_ID,
        {
            "email": "user@example.com",
            "display_name": "Payload Name",
            "avatar_url": "https://example.com/avatar.jpg",
            "user_metadata": {
                "display_name": "User Metadata Name",
                "photo_url": "https://example.com/avatar.jpg",
                "bio": "Metadata bio",
            },
            "app_metadata": {"role": "teacher"},
        },
    )

    assert current_user == {
        "id": USER_ID,
        "email": "user@example.com",
        "onboarding_state": "completed",
        "role": "learner",
        "display_name": None,
        "bio": None,
        "photo_url": None,
    }


async def test_build_current_user_rejects_invalid_canonical_subject(monkeypatch) -> None:
    from app import auth as auth_module

    _patch_canonical_auth_user(monkeypatch)

    async def _fake_get_auth_subject(_: str, *, email: str | None = None):
        assert email == "user@example.com"
        return {
            "user_id": USER_ID,
            "onboarding_state": "broken_state",
            "role": "learner",
        }

    monkeypatch.setattr(
        "app.repositories.auth_subjects.ensure_authenticated_auth_subject",
        _fake_get_auth_subject,
    )

    async def _fake_get_profile(_: str):
        return None

    monkeypatch.setattr("app.repositories.profiles.get_profile", _fake_get_profile)

    with pytest.raises(ValueError, match="Canonical onboarding_state invalid"):
        await auth_module._build_current_user(
            USER_ID,
            {"email": "user@example.com"},
        )


async def test_require_admin_ignores_current_user_role_when_canonical_is_false(
    monkeypatch,
) -> None:
    from app import permissions

    async def _fake_user_has_admin_role(_: str) -> bool:
        return False

    monkeypatch.setattr("app.models.user_has_admin_role", _fake_user_has_admin_role)

    with pytest.raises(HTTPException, match="admin_required") as exc_info:
        await permissions.require_admin({"id": "user-123", "role": "admin"})

    assert exc_info.value.status_code == 403


async def test_require_admin_allows_after_canonical_entry_when_canonical_admin_is_true(
    monkeypatch,
) -> None:
    from app import permissions

    async def _fake_user_has_admin_role(_: str) -> bool:
        return True

    monkeypatch.setattr("app.models.user_has_admin_role", _fake_user_has_admin_role)

    current = {"id": "user-123", "role": "learner"}
    assert await permissions.require_admin(current) is current


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


async def test_require_teacher_allows_after_canonical_entry_when_canonical_teacher_is_true(
    monkeypatch,
) -> None:
    from app import permissions

    async def _fake_is_teacher_user(_: str) -> bool:
        return True

    monkeypatch.setattr("app.models.is_teacher_user", _fake_is_teacher_user)

    current = {"id": "user-123", "role": "learner"}
    assert await permissions.require_teacher(current) is current
