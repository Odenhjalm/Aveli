from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest


pytestmark = pytest.mark.anyio("asyncio")


def _current_user(*, onboarding_state: str = "completed") -> dict[str, object]:
    return {
        "id": "entry-user-1",
        "email": "entry@example.com",
        "onboarding_state": onboarding_state,
        "role": "learner",
        "role_v2": "learner",
        "is_admin": False,
    }


async def _get_entry_state(
    async_client,
    monkeypatch,
    *,
    current_user: dict[str, object],
    membership: dict[str, object] | None,
):
    from app import auth
    from app.main import app
    from app.routes import entry_state

    async def _fake_get_current_user() -> dict[str, object]:
        return current_user

    async def _fake_get_membership(user_id: str) -> dict[str, object] | None:
        assert user_id == current_user["id"]
        return membership

    app.dependency_overrides[auth.get_current_user] = _fake_get_current_user
    monkeypatch.setattr(
        entry_state.memberships_repo,
        "get_membership",
        _fake_get_membership,
    )
    try:
        return await async_client.get("/entry-state")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)


async def test_entry_state_requires_authentication(async_client) -> None:
    response = await async_client.get("/entry-state")

    assert response.status_code == 401


async def test_entry_state_denies_incomplete_onboarding(async_client, monkeypatch):
    response = await _get_entry_state(
        async_client,
        monkeypatch,
        current_user=_current_user(onboarding_state="incomplete"),
        membership={"status": "active", "source": "purchase", "expires_at": None},
    )

    assert response.status_code == 200, response.text
    assert response.json() == {
        "can_enter_app": False,
        "onboarding_state": "incomplete",
        "onboarding_completed": False,
        "membership_active": True,
        "needs_onboarding": True,
        "needs_payment": False,
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }


@pytest.mark.parametrize(
    ("membership", "expected_needs_payment"),
    [
        (None, True),
        ({"status": "inactive", "source": "purchase", "expires_at": None}, True),
        ({"status": "unknown", "source": "purchase", "expires_at": None}, True),
    ],
)
async def test_entry_state_denies_missing_or_inactive_membership(
    async_client,
    monkeypatch,
    membership,
    expected_needs_payment: bool,
) -> None:
    response = await _get_entry_state(
        async_client,
        monkeypatch,
        current_user=_current_user(),
        membership=membership,
    )

    assert response.status_code == 200, response.text
    assert response.json() == {
        "can_enter_app": False,
        "onboarding_state": "completed",
        "onboarding_completed": True,
        "membership_active": False,
        "needs_onboarding": False,
        "needs_payment": expected_needs_payment,
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }


async def test_entry_state_allows_completed_onboarding_and_active_membership(
    async_client,
    monkeypatch,
) -> None:
    response = await _get_entry_state(
        async_client,
        monkeypatch,
        current_user=_current_user(),
        membership={"status": "active", "source": "purchase", "expires_at": None},
    )

    assert response.status_code == 200, response.text
    assert response.json() == {
        "can_enter_app": True,
        "onboarding_state": "completed",
        "onboarding_completed": True,
        "membership_active": True,
        "needs_onboarding": False,
        "needs_payment": False,
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }


async def test_entry_state_handles_referral_membership_without_payment_prompt(
    async_client,
    monkeypatch,
) -> None:
    response = await _get_entry_state(
        async_client,
        monkeypatch,
        current_user=_current_user(),
        membership={
            "status": "inactive",
            "source": "referral",
            "expires_at": datetime.now(timezone.utc) + timedelta(days=7),
        },
    )

    assert response.status_code == 200, response.text
    assert response.json() == {
        "can_enter_app": False,
        "onboarding_state": "completed",
        "onboarding_completed": True,
        "membership_active": False,
        "needs_onboarding": False,
        "needs_payment": True,
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }


def test_entry_state_route_is_read_only_and_not_profile_backed() -> None:
    source = Path("backend/app/routes/entry_state.py").read_text(encoding="utf-8")

    assert "can_enter_app" in source
    assert "get_profile" not in source
    assert "profiles" not in source
    assert "payload.get" not in source
    assert "token" not in source
    assert "upsert" not in source.lower()
    assert "insert" not in source.lower()
    assert "update" not in source.lower()
    assert "delete" not in source.lower()
