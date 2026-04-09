from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from jose import jwt

from app.config import settings
from app.main import app
from app.services.email_tokens import (
    EmailTokenError,
    create_email_token,
    verify_email_token,
)
from .utils import current_test_headers


def _unique_email(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:10]}@example.com"


@pytest.fixture
async def auth_client(anyio_backend):
    if anyio_backend != "asyncio":
        pytest.skip("Email flow tests require asyncio")

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://testserver",
        headers=current_test_headers(),
    ) as client:
        yield client


def test_verify_email_token_success():
    token = create_email_token("User@example.com", "verify", 15)

    assert verify_email_token(token, "verify") == "user@example.com"


def test_verify_email_token_expired():
    token = jwt.encode(
        {
            "sub": "expired@example.com",
            "type": "verify",
            "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )

    with pytest.raises(EmailTokenError):
        verify_email_token(token, "verify")


def test_verify_email_token_wrong_type():
    token = create_email_token("user@example.com", "reset", 10)

    with pytest.raises(EmailTokenError):
        verify_email_token(token, "verify")


@pytest.mark.anyio("asyncio")
async def test_verify_email_is_idempotent(auth_client, monkeypatch):
    email = _unique_email("verify")
    token = create_email_token(email, "verify", 15)
    confirmed_at = datetime.now(timezone.utc)
    state = {
        "user": {
            "id": "user-123",
            "email": email,
            "email_confirmed_at": None,
            "confirmed_at": None,
        }
    }

    async def fake_get_user_by_email(requested_email: str):
        assert requested_email == email
        return dict(state["user"])

    async def fake_mark_user_email_verified(requested_email: str):
        assert requested_email == email
        if state["user"]["email_confirmed_at"] is None:
            state["user"]["email_confirmed_at"] = confirmed_at
            state["user"]["confirmed_at"] = confirmed_at
        return dict(state["user"])

    monkeypatch.setattr(
        "app.services.email_verification.repositories.get_user_by_email",
        fake_get_user_by_email,
    )
    monkeypatch.setattr(
        "app.services.email_verification.repositories.mark_user_email_verified",
        fake_mark_user_email_verified,
    )
    async def fake_sync_onboarding_state(user_id: str):
        return user_id

    monkeypatch.setattr(
        "app.services.email_verification.sync_onboarding_state",
        fake_sync_onboarding_state,
    )

    first_verify = await auth_client.get(
        "/auth/verify-email",
        params={"token": token},
    )
    assert first_verify.status_code == 200, first_verify.text
    assert first_verify.json() == {"status": "verified"}

    second_verify = await auth_client.get(
        "/auth/verify-email",
        params={"token": token},
    )
    assert second_verify.status_code == 200, second_verify.text
    assert second_verify.json() == {"status": "already_verified"}
    assert state["user"]["email_confirmed_at"] is confirmed_at
    assert state["user"]["confirmed_at"] is confirmed_at


@pytest.mark.anyio("asyncio")
async def test_reset_password_flow(auth_client, monkeypatch):
    email = _unique_email("reset")
    new_password = "Changed456!"
    token = create_email_token(email, "reset", 10)
    updated_passwords: list[tuple[str, str]] = []
    revoked_users: list[str] = []

    async def fake_get_user_by_email(requested_email: str):
        assert requested_email == email
        return {"id": "user-456", "email": email}

    async def fake_update_user_password(user_id: str, password: str):
        updated_passwords.append((user_id, password))

    async def fake_revoke_refresh_tokens_for_user(user_id: str):
        revoked_users.append(user_id)

    monkeypatch.setattr(
        "app.services.email_verification.repositories.get_user_by_email",
        fake_get_user_by_email,
    )
    monkeypatch.setattr(
        "app.services.email_verification.models.update_user_password",
        fake_update_user_password,
    )
    monkeypatch.setattr(
        "app.services.email_verification.repositories.revoke_refresh_tokens_for_user",
        fake_revoke_refresh_tokens_for_user,
    )

    reset_resp = await auth_client.post(
        "/auth/reset-password",
        json={"token": token, "new_password": new_password},
    )
    assert reset_resp.status_code == 200, reset_resp.text
    assert reset_resp.json() == {"status": "password_reset"}
    assert updated_passwords == [("user-456", new_password)]
    assert revoked_users == ["user-456"]


@pytest.mark.anyio("asyncio")
async def test_invite_token_validation(auth_client):
    invited_email = _unique_email("invite")
    invited_token = create_email_token(invited_email, "invite", 24 * 60)

    validate_resp = await auth_client.get(
        "/auth/validate-invite",
        params={"token": invited_token},
    )
    assert validate_resp.status_code == 200, validate_resp.text
    assert validate_resp.json() == {"status": "valid", "email": invited_email}

    mismatch_resp = await auth_client.post(
        "/auth/register",
        json={
            "email": _unique_email("mismatch"),
            "password": "Secret123!",
            "display_name": "Mismatch",
            "invite_token": invited_token,
        },
    )
    assert mismatch_resp.status_code == 400, mismatch_resp.text
    assert mismatch_resp.json() == {
        "status": "error",
        "error_code": "invalid_or_expired_token",
        "message": "Lanken ar ogiltig eller har gatt ut.",
    }
