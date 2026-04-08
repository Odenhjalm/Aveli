from __future__ import annotations

from datetime import datetime, timezone
import uuid

import pytest

from app import schemas
from app.repositories import auth as auth_repo
from app.routes import profiles as profile_routes
from app.services import email_verification, onboarding_state, subscription_service

pytestmark = pytest.mark.anyio("asyncio")


async def test_create_user_initializes_canonical_auth_subject_and_profile_projection(
    monkeypatch,
):
    created_at = datetime.now(timezone.utc)
    executed_queries: list[str] = []
    ensured_subjects: list[dict[str, object]] = []
    upserted_profiles: list[dict[str, object]] = []

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
            else:
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

    async def fake_ensure_auth_subject(
        user_id: str,
        *,
        onboarding_state: str,
        role_v2: str,
        role: str,
        is_admin: bool,
    ):
        ensured_subjects.append(
            {
                "user_id": user_id,
                "onboarding_state": onboarding_state,
                "role_v2": role_v2,
                "role": role,
                "is_admin": is_admin,
            }
        )
        return ensured_subjects[-1]

    async def fake_upsert_profile_row(*, user_id: str, email: str, display_name: str | None):
        upserted_profiles.append(
            {
                "user_id": user_id,
                "email": email,
                "display_name": display_name,
            }
        )
        return None

    async def fake_get_profile(user_id: str):
        return {
            "user_id": user_id,
            "email": "unit@example.com",
            "display_name": "Unit User",
            "bio": None,
            "photo_url": None,
            "avatar_media_id": None,
            "created_at": created_at,
            "updated_at": created_at,
        }

    monkeypatch.setattr(auth_repo.pool, "connection", lambda: _Connection())
    monkeypatch.setattr(auth_repo, "ensure_auth_subject", fake_ensure_auth_subject)
    monkeypatch.setattr(auth_repo, "_upsert_profile_row", fake_upsert_profile_row)
    monkeypatch.setattr(auth_repo, "get_profile_for_user", fake_get_profile)

    result = await auth_repo.create_user(
        email=" Unit@Example.com ",
        hashed_password="hashed",
        display_name="Unit User",
    )

    assert result["profile"]["email"] == "unit@example.com"
    assert ensured_subjects == [
        {
            "user_id": result["user"]["id"],
            "onboarding_state": "incomplete",
            "role_v2": "learner",
            "role": "learner",
            "is_admin": False,
        }
    ]
    assert upserted_profiles == [
        {
            "user_id": result["user"]["id"],
            "email": "unit@example.com",
            "display_name": "Unit User",
        }
    ]
    assert any("INSERT INTO app.auth_subjects" in query for query in executed_queries)


async def test_derive_onboarding_state_returns_canonical_subject_state(monkeypatch):
    async def fake_get_auth_subject(user_id: str):
        return {
            "user_id": user_id,
            "onboarding_state": "completed",
            "role_v2": "learner",
            "role": "learner",
            "is_admin": False,
        }

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_auth_subject",
        fake_get_auth_subject,
    )

    state = await onboarding_state.derive_onboarding_state("user-1")
    assert state == "completed"


async def test_derive_onboarding_state_rejects_missing_subject(monkeypatch):
    async def fake_get_auth_subject(user_id: str):
        return None

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_auth_subject",
        fake_get_auth_subject,
    )

    with pytest.raises(ValueError, match="Auth subject missing"):
        await onboarding_state.derive_onboarding_state("user-2")


async def test_derive_onboarding_state_rejects_invalid_canonical_state(monkeypatch):
    async def fake_get_auth_subject(user_id: str):
        return {
            "user_id": user_id,
            "onboarding_state": "broken_state",
            "role_v2": "learner",
            "role": "learner",
            "is_admin": False,
        }

    monkeypatch.setattr(
        "app.services.onboarding_state.repositories.get_auth_subject",
        fake_get_auth_subject,
    )

    with pytest.raises(ValueError, match="Invalid canonical onboarding_state"):
        await onboarding_state.derive_onboarding_state("user-3")


async def test_sync_onboarding_state_returns_derived_canonical_state(monkeypatch):
    async def fake_derive_onboarding_state(user_id: str):
        assert user_id == "user-4"
        return "completed"

    monkeypatch.setattr(onboarding_state, "derive_onboarding_state", fake_derive_onboarding_state)

    state = await onboarding_state.sync_onboarding_state("user-4")
    assert state == "completed"


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
        return "completed"

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


async def test_profile_update_returns_projection_only_shape(monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_update_profile(user_id: str, **kwargs):
        return {
            "user_id": uuid.UUID("00000000-0000-0000-0000-000000000123"),
            "email": "profile@example.com",
            "display_name": kwargs["display_name"],
            "bio": kwargs.get("bio"),
            "photo_url": kwargs.get("photo_url"),
            "avatar_media_id": None,
            "created_at": now,
            "updated_at": now,
        }

    monkeypatch.setattr("app.routes.profiles.models.update_profile", fake_update_profile)

    response = await profile_routes.patch_me(
        schemas.ProfileUpdate(display_name="Updated Name"),
        current_user={"id": "profile-user"},
    )

    payload = response.model_dump()
    assert payload["display_name"] == "Updated Name"
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


async def test_profiles_me_response_excludes_legacy_auth_fields(monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_get_profile(user_id: str):
        return {
            "user_id": uuid.UUID("00000000-0000-0000-0000-000000000321"),
            "email": "teacher@example.com",
            "display_name": "Teacher",
            "bio": None,
            "photo_url": None,
            "avatar_media_id": None,
            "created_at": now,
            "updated_at": now,
        }

    monkeypatch.setattr("app.routes.profiles.models.get_profile", fake_get_profile)

    response = await profile_routes.get_me(current_user={"id": "teacher-user"})
    payload = response.model_dump()
    assert payload["email"] == "teacher@example.com"
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
        return "completed"

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
