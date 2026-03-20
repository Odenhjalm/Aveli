from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

import pytest

from app import schemas
from app.repositories import auth as auth_repo
from app.routes import api_auth, api_me
from app.services import email_verification, onboarding_state, subscription_service

pytestmark = pytest.mark.anyio("asyncio")


async def test_create_user_initializes_registered_unverified(monkeypatch):
    created_at = datetime.now(timezone.utc)
    executed_queries: list[str] = []

    class _Cursor:
        def __init__(self) -> None:
            self._current_row = None

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def execute(self, query, params):
            executed_queries.append(query)
            if "INSERT INTO auth.users" in query:
                self._current_row = {
                    "id": uuid.uuid4(),
                    "email": params[1],
                    "created_at": created_at,
                    "updated_at": created_at,
                }
            elif "INSERT INTO app.profiles" in query:
                assert "onboarding_state" in query
                assert "'registered_unverified'" in query
                self._current_row = {
                    "user_id": params[0],
                    "email": params[1],
                    "display_name": params[2],
                    "onboarding_state": "registered_unverified",
                    "role_v2": "user",
                    "is_admin": False,
                    "created_at": created_at,
                    "updated_at": created_at,
                }
            else:  # pragma: no cover - defensive for unexpected queries
                self._current_row = None

        async def fetchone(self):
            return self._current_row

    class _Connection:
        def cursor(self, row_factory=None):
            return _Cursor()

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def commit(self):
            return None

        async def rollback(self):
            return None

    monkeypatch.setattr(
        auth_repo.pool,
        "connection",
        lambda: _Connection(),
    )

    result = await auth_repo.create_user(
        email="unit@example.com",
        hashed_password="hashed",
        display_name="Unit User",
    )

    assert result["profile"]["onboarding_state"] == "registered_unverified"
    assert any("INSERT INTO app.profiles" in query for query in executed_queries)


async def test_derive_onboarding_state_returns_registered_unverified(monkeypatch):
    async def fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "display_name": None,
            "onboarding_state": None,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        }

    async def fake_get_user_by_id(user_id: str):
        return {"id": user_id, "email_confirmed_at": None, "confirmed_at": None}

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_profile",
        fake_get_profile,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_user_by_id",
        fake_get_user_by_id,
    )

    state = await onboarding_state.derive_onboarding_state("user-1")
    assert state == "registered_unverified"


async def test_derive_onboarding_state_returns_verified_unpaid(monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "display_name": "Verified User",
            "onboarding_state": None,
            "created_at": now,
            "updated_at": now,
        }

    async def fake_get_user_by_id(user_id: str):
        return {"id": user_id, "email_confirmed_at": now, "confirmed_at": now}

    async def fake_get_membership(user_id: str):
        return None

    async def fake_is_teacher_user(user_id: str) -> bool:
        return False

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_profile",
        fake_get_profile,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_user_by_id",
        fake_get_user_by_id,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.models.is_teacher_user",
        fake_is_teacher_user,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_membership",
        fake_get_membership,
    )

    state = await onboarding_state.derive_onboarding_state("user-2")
    assert state == "verified_unpaid"


async def test_derive_onboarding_state_bypasses_subscription_for_teacher(monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "display_name": "Teacher User",
            "onboarding_state": None,
            "created_at": now,
            "updated_at": now + timedelta(seconds=1),
        }

    async def fake_get_user_by_id(user_id: str):
        return {"id": user_id, "email_confirmed_at": now, "confirmed_at": now}

    async def fake_get_membership(user_id: str):
        return None

    async def fake_is_teacher_user(user_id: str) -> bool:
        return True

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_profile",
        fake_get_profile,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_user_by_id",
        fake_get_user_by_id,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.models.is_teacher_user",
        fake_is_teacher_user,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_membership",
        fake_get_membership,
    )

    state = await onboarding_state.derive_onboarding_state("teacher-1")
    assert state == "access_active_profile_complete"


async def test_derive_onboarding_state_returns_profile_incomplete(monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "display_name": "Paid User",
            "onboarding_state": None,
            "created_at": now,
            "updated_at": now,
        }

    async def fake_get_user_by_id(user_id: str):
        return {"id": user_id, "email_confirmed_at": now, "confirmed_at": now}

    async def fake_get_membership(user_id: str):
        return {"status": "active", "end_date": None}

    async def fake_is_teacher_user(user_id: str) -> bool:
        return False

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_profile",
        fake_get_profile,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_user_by_id",
        fake_get_user_by_id,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.models.is_teacher_user",
        fake_is_teacher_user,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_membership",
        fake_get_membership,
    )

    state = await onboarding_state.derive_onboarding_state("user-3")
    assert state == "access_active_profile_incomplete"


async def test_sync_onboarding_state_persists_new_state(monkeypatch):
    now = datetime.now(timezone.utc)
    set_calls: list[tuple[str, str]] = []

    async def fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "display_name": "Verified User",
            "onboarding_state": "registered_unverified",
            "created_at": now,
            "updated_at": now,
        }

    async def fake_get_user_by_id(user_id: str):
        return {"id": user_id, "email_confirmed_at": now, "confirmed_at": now}

    async def fake_get_membership(user_id: str):
        return None

    async def fake_set_onboarding_state(user_id: str, state: str):
        set_calls.append((user_id, state))
        return {"user_id": user_id, "onboarding_state": state}

    async def fake_is_teacher_user(user_id: str) -> bool:
        return False

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_profile",
        fake_get_profile,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_user_by_id",
        fake_get_user_by_id,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.models.is_teacher_user",
        fake_is_teacher_user,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_membership",
        fake_get_membership,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.set_onboarding_state",
        fake_set_onboarding_state,
    )

    state = await onboarding_state.sync_onboarding_state("user-4")
    assert state == "verified_unpaid"
    assert set_calls == [("user-4", "verified_unpaid")]


async def test_sync_onboarding_state_keeps_welcomed_terminal(monkeypatch):
    async def fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "display_name": "Welcomed User",
            "onboarding_state": "welcomed",
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        }

    async def fake_set_onboarding_state(user_id: str, state: str):  # pragma: no cover
        raise AssertionError("welcomed should be terminal")

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_profile",
        fake_get_profile,
    )
    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.set_onboarding_state",
        fake_set_onboarding_state,
    )

    state = await onboarding_state.sync_onboarding_state("user-5")
    assert state == "welcomed"


async def test_verify_email_marks_user_and_syncs_state(monkeypatch):
    synced_users: list[str] = []

    async def fake_get_user_by_email(email: str):
        return {
            "id": "verify-user",
            "email": email,
            "email_confirmed_at": None,
            "confirmed_at": None,
        }

    async def fake_mark_user_email_verified(email: str):
        return {
            "id": "verify-user",
            "email": email,
            "email_confirmed_at": datetime.now(timezone.utc),
            "confirmed_at": datetime.now(timezone.utc),
        }

    async def fake_sync_onboarding_state(user_id: str):
        synced_users.append(user_id)
        return "verified_unpaid"

    monkeypatch.setattr(
        "app.services.email_verification.repositories.get_user_by_email",
        fake_get_user_by_email,
    )
    monkeypatch.setattr(
        "app.services.email_verification.repositories.mark_user_email_verified",
        fake_mark_user_email_verified,
    )
    monkeypatch.setattr(
        "app.services.email_verification.sync_onboarding_state",
        fake_sync_onboarding_state,
    )

    token = email_verification.create_email_token("verify@example.com", "verify", 15)
    result = await email_verification.verify_email_token_and_mark_user(token)

    assert result["status"] == "verified"
    assert synced_users == ["verify-user"]


async def test_profile_update_syncs_onboarding_state(monkeypatch):
    async def fake_update_profile(user_id: str, **kwargs):
        return {
            "user_id": user_id,
            "email": "profile@example.com",
            "display_name": kwargs["display_name"],
            "bio": kwargs.get("bio"),
            "photo_url": kwargs.get("photo_url"),
            "avatar_media_id": None,
            "onboarding_state": "access_active_profile_incomplete",
            "role_v2": "user",
            "is_admin": False,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        }

    async def fake_sync_onboarding_state(user_id: str):
        assert user_id == "profile-user"
        return "access_active_profile_complete"

    async def fake_profile_response(user_id: str):
        return schemas.Profile(
            user_id=uuid.UUID("00000000-0000-0000-0000-000000000123"),
            email="profile@example.com",
            display_name="Updated Name",
            onboarding_state="access_active_profile_complete",
            email_verified=True,
            membership_active=True,
            role_v2="user",
            is_admin=False,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )

    monkeypatch.setattr(
        "app.routes.api_auth.repositories.update_profile",
        fake_update_profile,
    )
    monkeypatch.setattr(
        "app.routes.api_auth.sync_onboarding_state",
        fake_sync_onboarding_state,
    )
    monkeypatch.setattr(
        "app.routes.api_auth._profile_response",
        fake_profile_response,
    )

    response = await api_auth.update_me(
        schemas.ProfileUpdate(display_name="Updated Name"),
        current={"id": "profile-user"},
    )

    assert response.onboarding_state == "access_active_profile_complete"


async def test_auth_me_response_includes_computed_teacher_access(monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_get_profile(user_id: str):
        return {
            "user_id": uuid.UUID("00000000-0000-0000-0000-000000000321"),
            "email": "teacher@example.com",
            "display_name": "Teacher",
            "bio": None,
            "photo_url": None,
            "avatar_media_id": None,
            "onboarding_state": "welcomed",
            "role_v2": "user",
            "is_admin": False,
            "created_at": now,
            "updated_at": now,
        }

    async def fake_sync_onboarding_state(user_id: str):
        return "welcomed"

    async def fake_is_teacher_user(user_id: str) -> bool:
        return True

    async def fake_get_user_by_id(user_id: str):
        return {"id": user_id, "email_confirmed_at": now, "confirmed_at": now}

    async def fake_get_membership(user_id: str):
        return None

    monkeypatch.setattr(
        "app.routes.api_auth.repositories.get_profile",
        fake_get_profile,
    )
    monkeypatch.setattr(
        "app.routes.api_auth.sync_onboarding_state",
        fake_sync_onboarding_state,
    )
    monkeypatch.setattr(
        "app.routes.api_auth.models.is_teacher_user",
        fake_is_teacher_user,
    )
    monkeypatch.setattr(
        "app.routes.api_auth.repositories.get_user_by_id",
        fake_get_user_by_id,
    )
    monkeypatch.setattr(
        "app.routes.api_auth.repositories.get_membership",
        fake_get_membership,
    )

    response = await api_auth._profile_response("teacher-user")
    assert response.is_teacher is True
    assert response.membership_active is False


async def test_welcome_completion_sets_terminal_state(monkeypatch):
    async def fake_set_onboarding_state(user_id: str, state: str):
        assert user_id == "welcome-user"
        assert state == "welcomed"
        return {"user_id": user_id, "onboarding_state": state}

    monkeypatch.setattr(
        "app.routes.api_me.repositories.set_onboarding_state",
        fake_set_onboarding_state,
    )

    response = await api_me.complete_welcome(current={"id": "welcome-user"})
    assert response.onboarding_state == "welcomed"


async def test_subscription_webhook_syncs_state_and_skips_duplicates(monkeypatch):
    upsert_calls: list[tuple[str, str]] = []
    sync_calls: list[str] = []

    async def fake_insert_payment_event(event_id: str, payload: dict):
        return event_id != "evt_duplicate"

    async def fake_upsert_membership_record(user_id: str, **kwargs):
        upsert_calls.append((user_id, kwargs["status"]))
        return {"user_id": user_id, **kwargs}

    async def fake_sync_onboarding_state(user_id: str):
        sync_calls.append(user_id)
        return "access_active_profile_incomplete"

    monkeypatch.setattr(
        "app.services.subscription_service.memberships_repo.insert_payment_event",
        fake_insert_payment_event,
    )
    monkeypatch.setattr(
        "app.services.subscription_service.memberships_repo.upsert_membership_record",
        fake_upsert_membership_record,
    )
    monkeypatch.setattr(
        "app.services.subscription_service.sync_onboarding_state",
        fake_sync_onboarding_state,
    )

    event = {
        "id": "evt_subscription_created",
        "type": "customer.subscription.created",
        "data": {
            "object": {
                "id": "sub_123",
                "customer": "cus_123",
                "status": "active",
                "metadata": {"user_id": "subscription-user"},
                "items": {
                    "data": [
                        {
                            "price": {
                                "id": "price_month",
                                "recurring": {"interval": "month"},
                            }
                        }
                    ]
                },
                "current_period_start": 1,
                "current_period_end": 2,
            }
        },
    }

    await subscription_service.process_event(event)

    assert upsert_calls == [("subscription-user", "active")]
    assert sync_calls == ["subscription-user"]

    duplicate_event = dict(event)
    duplicate_event["id"] = "evt_duplicate"
    await subscription_service.process_event(duplicate_event)

    assert upsert_calls == [("subscription-user", "active")]
    assert sync_calls == ["subscription-user"]
