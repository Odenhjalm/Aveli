from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

import pytest
from fastapi import HTTPException


pytestmark = pytest.mark.anyio("asyncio")


def _current_user(*, onboarding_state: str = "completed") -> dict[str, object]:
    return {
        "id": "user-1",
        "email": "user@example.com",
        "onboarding_state": onboarding_state,
        "role": "learner",
        "role_v2": "learner",
        "is_admin": False,
    }


def _teacher_current_user(*, onboarding_state: str = "completed") -> dict[str, object]:
    return {
        "id": "teacher-1",
        "email": "teacher@example.com",
        "onboarding_state": onboarding_state,
        "role": "teacher",
        "role_v2": "teacher",
        "is_admin": False,
    }


def _admin_current_user(*, onboarding_state: str = "completed") -> dict[str, object]:
    return {
        "id": "admin-1",
        "email": "admin@example.com",
        "onboarding_state": onboarding_state,
        "role": "learner",
        "role_v2": "learner",
        "is_admin": True,
    }


async def _set_membership(monkeypatch, membership: dict[str, object] | None) -> None:
    async def _fake_get_membership(user_id: str) -> dict[str, object] | None:
        assert user_id == "user-1"
        return membership

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _fake_get_membership,
    )


async def test_app_entry_denies_incomplete_onboarding(monkeypatch) -> None:
    from app import auth

    async def _unexpected_get_membership(_: str) -> None:
        raise AssertionError("membership must not be checked before onboarding")

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _unexpected_get_membership,
    )

    with pytest.raises(HTTPException) as exc_info:
        await auth.require_app_entry(_current_user(onboarding_state="incomplete"))

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "canonical_app_entry_required"


async def _with_current_user_override(user: dict[str, object]):
    from app import auth
    from app.main import app

    async def _fake_get_current_user() -> dict[str, object]:
        return user

    app.dependency_overrides[auth.get_current_user] = _fake_get_current_user
    return app, auth


async def test_teacher_route_denies_incomplete_onboarding_before_role_check(
    async_client,
    monkeypatch,
) -> None:
    app, auth = await _with_current_user_override(
        _teacher_current_user(onboarding_state="incomplete")
    )

    async def _unexpected_get_membership(_: str) -> None:
        raise AssertionError("membership must not be checked before onboarding")

    async def _unexpected_is_teacher_user(_: str) -> None:
        raise AssertionError("teacher role must not be checked before app-entry")

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _unexpected_get_membership,
    )
    monkeypatch.setattr("app.models.is_teacher_user", _unexpected_is_teacher_user)

    try:
        response = await async_client.get("/studio/status")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)

    assert response.status_code == 403
    assert response.json()["detail"] == "canonical_app_entry_required"


async def test_teacher_route_denies_missing_membership_before_role_check(
    async_client,
    monkeypatch,
) -> None:
    app, auth = await _with_current_user_override(_teacher_current_user())

    async def _fake_get_membership(_: str) -> None:
        return None

    async def _unexpected_is_teacher_user(_: str) -> None:
        raise AssertionError("teacher role must not be checked before app-entry")

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _fake_get_membership,
    )
    monkeypatch.setattr("app.models.is_teacher_user", _unexpected_is_teacher_user)

    try:
        response = await async_client.get("/studio/status")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)

    assert response.status_code == 403
    assert response.json()["detail"] == "canonical_app_entry_required"


async def test_admin_route_denies_incomplete_onboarding_before_role_check(
    async_client,
    monkeypatch,
) -> None:
    app, auth = await _with_current_user_override(
        _admin_current_user(onboarding_state="incomplete")
    )

    async def _unexpected_get_membership(_: str) -> None:
        raise AssertionError("membership must not be checked before onboarding")

    async def _unexpected_is_admin_user(_: str) -> None:
        raise AssertionError("admin role must not be checked before app-entry")

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _unexpected_get_membership,
    )
    monkeypatch.setattr("app.models.is_admin_user", _unexpected_is_admin_user)

    try:
        response = await async_client.get("/admin/settings")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)

    assert response.status_code == 403
    assert response.json()["detail"] == "canonical_app_entry_required"


async def test_admin_route_denies_missing_membership_before_role_check(
    async_client,
    monkeypatch,
) -> None:
    app, auth = await _with_current_user_override(_admin_current_user())

    async def _fake_get_membership(_: str) -> None:
        return None

    async def _unexpected_is_admin_user(_: str) -> None:
        raise AssertionError("admin role must not be checked before app-entry")

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _fake_get_membership,
    )
    monkeypatch.setattr("app.models.is_admin_user", _unexpected_is_admin_user)

    try:
        response = await async_client.get("/admin/settings")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)

    assert response.status_code == 403
    assert response.json()["detail"] == "canonical_app_entry_required"


async def test_teacher_route_allows_after_app_entry_and_teacher_role(
    async_client,
    monkeypatch,
) -> None:
    app, auth = await _with_current_user_override(_teacher_current_user())

    async def _fake_get_membership(_: str) -> dict[str, object]:
        return {"status": "active", "expires_at": None}

    async def _fake_is_teacher_user(_: str) -> bool:
        return True

    async def _fake_teacher_status(_: str) -> dict[str, Any]:
        return {
            "role": "teacher",
            "is_admin": False,
            "verified_certificates": 0,
        }

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _fake_get_membership,
    )
    monkeypatch.setattr("app.models.is_teacher_user", _fake_is_teacher_user)
    monkeypatch.setattr("app.routes.studio.models.teacher_status", _fake_teacher_status)

    try:
        response = await async_client.get("/studio/status")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)

    assert response.status_code == 200
    assert response.json() == {
        "role": "teacher",
        "is_admin": False,
        "verified_certificates": 0,
    }


async def test_admin_route_allows_after_app_entry_and_admin_role(
    async_client,
    monkeypatch,
) -> None:
    app, auth = await _with_current_user_override(_admin_current_user())

    async def _fake_get_membership(_: str) -> dict[str, object]:
        return {"status": "active", "expires_at": None}

    async def _fake_is_admin_user(_: str) -> bool:
        return True

    async def _fake_priorities() -> list[dict[str, object]]:
        return []

    async def _fake_metrics() -> dict[str, object]:
        return {}

    monkeypatch.setattr(
        "app.auth.memberships_repo.get_membership",
        _fake_get_membership,
    )
    monkeypatch.setattr("app.models.is_admin_user", _fake_is_admin_user)
    monkeypatch.setattr(
        "app.routes.admin.models.list_teacher_course_priorities",
        _fake_priorities,
    )
    monkeypatch.setattr("app.routes.admin.models.fetch_admin_metrics", _fake_metrics)

    try:
        response = await async_client.get("/admin/settings")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)

    assert response.status_code == 200
    payload = response.json()
    assert payload["priorities"] == []
    assert payload["metrics"]["total_users"] == 0
    assert payload["metrics"]["total_teachers"] == 0


async def test_app_entry_denies_missing_membership(monkeypatch) -> None:
    from app import auth

    await _set_membership(monkeypatch, None)

    with pytest.raises(HTTPException) as exc_info:
        await auth.require_app_entry(_current_user())

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "canonical_app_entry_required"


async def test_app_entry_denies_inactive_membership(monkeypatch) -> None:
    from app import auth

    await _set_membership(monkeypatch, {"status": "inactive", "expires_at": None})

    with pytest.raises(HTTPException) as exc_info:
        await auth.require_app_entry(_current_user())

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "canonical_app_entry_required"


async def test_app_entry_allows_active_membership(monkeypatch) -> None:
    from app import auth

    current = _current_user()
    await _set_membership(monkeypatch, {"status": "active", "expires_at": None})

    assert await auth.require_app_entry(current) is current


async def test_app_entry_allows_canceled_membership_before_expiry(monkeypatch) -> None:
    from app import auth

    current = _current_user()
    await _set_membership(
        monkeypatch,
        {
            "status": "canceled",
            "expires_at": datetime.now(timezone.utc) + timedelta(days=1),
        },
    )

    assert await auth.require_app_entry(current) is current


async def test_app_entry_denies_canceled_membership_after_expiry(monkeypatch) -> None:
    from app import auth

    await _set_membership(
        monkeypatch,
        {
            "status": "canceled",
            "expires_at": datetime.now(timezone.utc) - timedelta(seconds=1),
        },
    )

    with pytest.raises(HTTPException) as exc_info:
        await auth.require_app_entry(_current_user())

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "canonical_app_entry_required"
