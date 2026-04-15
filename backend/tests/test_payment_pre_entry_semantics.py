from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import pytest
from fastapi import HTTPException

from app import auth
from app.routes import entry_state
from app.services import subscription_service

pytestmark = pytest.mark.anyio("asyncio")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


async def test_payment_state_creates_purchase_membership_without_existing_row(
    monkeypatch,
) -> None:
    captured: dict[str, Any] = {}
    now = datetime.now(timezone.utc)

    async def fake_get_membership(user_id: str):
        captured["lookup_user_id"] = user_id
        return None

    async def fake_upsert_membership_record(user_id: str, **kwargs):
        captured["membership_write"] = {"user_id": user_id, **kwargs}
        return {"membership_id": "membership_purchase_123", "user_id": user_id, **kwargs}

    monkeypatch.setattr(
        subscription_service.memberships_repo,
        "get_membership",
        fake_get_membership,
    )
    monkeypatch.setattr(
        subscription_service.memberships_repo,
        "upsert_membership_record",
        fake_upsert_membership_record,
    )

    membership, updated = await subscription_service._write_payment_membership_state(
        "user_purchase_123",
        status="active",
        effective_at=now,
        expires_at=now + timedelta(days=30),
        canceled_at=None,
        ended_at=None,
    )

    assert updated is True
    assert membership is not None
    assert captured["lookup_user_id"] == "user_purchase_123"
    assert captured["membership_write"]["source"] == "purchase"
    assert captured["membership_write"]["status"] == "active"
    assert captured["membership_write"]["expires_at"] == now + timedelta(days=30)


async def test_checkout_return_without_membership_cannot_enter_app(monkeypatch) -> None:
    async def fake_get_membership(user_id: str):
        assert user_id == "user_no_membership_123"
        return None

    monkeypatch.setattr(entry_state.memberships_repo, "get_membership", fake_get_membership)

    with pytest.raises(HTTPException) as excinfo:
        await auth.require_app_entry(
            {
                "id": "user_no_membership_123",
                "email": "member@example.com",
                "onboarding_state": "completed",
                "role": "learner",
                "role_v2": "learner",
                "is_admin": False,
            }
        )

    assert excinfo.value.status_code == 403


async def test_active_payment_membership_still_requires_onboarding(
    monkeypatch,
) -> None:
    async def fake_get_membership(user_id: str):
        assert user_id == "user_incomplete_123"
        return {
            "membership_id": "membership_purchase_123",
            "user_id": user_id,
            "status": "active",
            "source": "purchase",
            "expires_at": None,
        }

    monkeypatch.setattr(entry_state.memberships_repo, "get_membership", fake_get_membership)

    with pytest.raises(HTTPException) as excinfo:
        await auth.require_app_entry(
            {
                "id": "user_incomplete_123",
                "email": "member@example.com",
                "onboarding_state": "incomplete",
                "role": "learner",
                "role_v2": "learner",
                "is_admin": False,
            }
        )

    assert excinfo.value.status_code == 403


async def test_completed_onboarding_and_active_payment_membership_can_enter_app(
    monkeypatch,
) -> None:
    current = {
        "id": "user_complete_123",
        "email": "member@example.com",
        "onboarding_state": "completed",
        "role": "learner",
        "role_v2": "learner",
        "is_admin": False,
    }

    async def fake_get_membership(user_id: str):
        assert user_id == "user_complete_123"
        return {
            "membership_id": "membership_purchase_123",
            "user_id": user_id,
            "status": "active",
            "source": "purchase",
            "expires_at": None,
        }

    monkeypatch.setattr(entry_state.memberships_repo, "get_membership", fake_get_membership)

    assert await auth.require_app_entry(current) == current


async def test_payment_surfaces_do_not_return_entry_or_mutate_onboarding() -> None:
    root = _repo_root()
    payment_surfaces = [
        root / "backend/app/routes/billing.py",
        root / "backend/app/routes/api_checkout.py",
        root / "backend/app/routes/course_bundles.py",
        root / "backend/app/routes/stripe_webhooks.py",
        root / "backend/app/services/subscription_service.py",
        root / "backend/app/services/membership_grant_service.py",
    ]
    source = "\n".join(path.read_text(encoding="utf-8") for path in payment_surfaces)

    assert "require_app_entry" not in source
    assert "can_enter_app" not in source
    assert "access_granted" not in source
    assert "access granted" not in source.lower()
    assert "SET onboarding_state" not in source
    assert "onboarding_state = 'completed'" not in source
    assert "complete_onboarding" not in source
