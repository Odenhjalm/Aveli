from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from jose import jwt
import pytest

from app.config import settings
from app.routes import api_auth as api_auth_routes
from app.routes import email_verification as email_verification_routes
from app.services.email_service import EmailDeliveryError
from app.services.email_tokens import (
    EmailTokenError,
    create_email_token,
    verify_email_token,
)


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def email_verification_client(anyio_backend):
    app = FastAPI()
    app.include_router(email_verification_routes.router)
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        yield client


@pytest.fixture
async def auth_client(anyio_backend):
    app = FastAPI()
    app.include_router(api_auth_routes.router)
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://testserver",
    ) as client:
        yield client


def test_create_email_token_and_verify_success():
    token = create_email_token("Test@Example.com", "verify", 15)
    assert verify_email_token(token, "verify") == "test@example.com"


def test_verify_email_token_rejects_wrong_type():
    token = create_email_token("user@example.com", "invite", 15)
    with pytest.raises(EmailTokenError):
        verify_email_token(token, "verify")


def test_verify_email_token_rejects_expired():
    token = jwt.encode(
        {
            "sub": "user@example.com",
            "type": "verify",
            "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    with pytest.raises(EmailTokenError):
        verify_email_token(token, "verify")


@pytest.mark.anyio("asyncio")
async def test_verify_email_endpoint_returns_success(
    email_verification_client,
    monkeypatch,
):
    async def fake_verify_email_token_and_mark_user(token: str) -> dict[str, str]:
        assert token == "valid-token"
        return {"status": "verified", "email": "user@example.com"}

    monkeypatch.setattr(
        email_verification_routes,
        "verify_email_token_and_mark_user",
        fake_verify_email_token_and_mark_user,
    )

    response = await email_verification_client.get(
        "/auth/verify-email",
        params={"token": "valid-token"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "verified"
    assert payload["redirect_after_login"] == "/resume-onboarding"
    assert payload["onboarding"] is None


@pytest.mark.anyio("asyncio")
async def test_verify_email_endpoint_returns_invalid_token_error(
    email_verification_client,
    monkeypatch,
):
    async def fake_verify_email_token_and_mark_user(_: str) -> dict[str, str]:
        raise email_verification_routes.InvalidEmailVerificationTokenError(
            "invalid_or_expired_token"
        )

    monkeypatch.setattr(
        email_verification_routes,
        "verify_email_token_and_mark_user",
        fake_verify_email_token_and_mark_user,
    )

    response = await email_verification_client.get(
        "/auth/verify-email",
        params={"token": "expired-token"},
    )

    assert response.status_code == 400
    assert response.json() == {"error": "invalid_or_expired_token"}


@pytest.mark.anyio("asyncio")
async def test_send_verification_endpoint_rate_limits_by_email(
    email_verification_client,
    monkeypatch,
):
    email_verification_routes._send_verification_attempts.clear()
    sent_to: list[str] = []

    async def fake_get_user_by_email(email: str) -> dict[str, str]:
        return {"email": email}

    async def fake_send_verification_email(email: str) -> None:
        sent_to.append(email)

    monkeypatch.setattr(
        email_verification_routes.repositories,
        "get_user_by_email",
        fake_get_user_by_email,
    )
    monkeypatch.setattr(
        email_verification_routes,
        "send_verification_email",
        fake_send_verification_email,
    )

    payload = {"email": "rate-limit@example.com"}

    for _ in range(5):
        response = await email_verification_client.post(
            "/auth/send-verification",
            json=payload,
        )
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    response = await email_verification_client.post(
        "/auth/send-verification",
        json=payload,
    )

    assert response.status_code == 429
    assert response.json() == {"error": "rate_limited"}
    assert sent_to == ["rate-limit@example.com"] * 5

    email_verification_routes._send_verification_attempts.clear()


@pytest.mark.anyio("asyncio")
async def test_signup_triggers_verification_email_and_ignores_delivery_failure(
    auth_client,
    monkeypatch,
):
    requested_email = f"verify_{uuid.uuid4().hex[:8]}@example.com"
    created_user_id = uuid.uuid4()
    delivery_attempts: list[str] = []

    async def fake_get_user_by_email(_: str) -> None:
        return None

    async def fake_create_user(
        *,
        email: str,
        hashed_password: str,
        display_name: str | None,
        referral_code: str | None = None,
    ) -> dict[str, object]:
        assert hashed_password
        assert display_name == "Verifier"
        assert referral_code is None
        return {
            "user": {"id": created_user_id, "email": email},
            "profile": {
                "user_id": created_user_id,
                "email": email,
                "display_name": display_name,
                "role_v2": "user",
                "is_admin": False,
            },
        }

    async def fake_is_teacher_user(_: str) -> bool:
        return False

    async def fake_upsert_refresh_token(**_: object) -> None:
        return None

    async def fake_insert_auth_event(**_: object) -> None:
        return None

    async def fake_ensure_onboarding_row(_: str) -> None:
        return None

    async def fake_send_verification_email(email: str) -> None:
        delivery_attempts.append(email)
        raise EmailDeliveryError("Failed to send email")

    monkeypatch.setattr(
        api_auth_routes.repositories,
        "get_user_by_email",
        fake_get_user_by_email,
    )
    monkeypatch.setattr(
        api_auth_routes.repositories,
        "create_user",
        fake_create_user,
    )
    monkeypatch.setattr(
        api_auth_routes.models,
        "is_teacher_user",
        fake_is_teacher_user,
    )
    monkeypatch.setattr(
        api_auth_routes.repositories,
        "upsert_refresh_token",
        fake_upsert_refresh_token,
    )
    monkeypatch.setattr(
        api_auth_routes.repositories,
        "insert_auth_event",
        fake_insert_auth_event,
    )
    monkeypatch.setattr(
        api_auth_routes.onboarding_service,
        "ensure_onboarding_row",
        fake_ensure_onboarding_row,
    )
    monkeypatch.setattr(
        api_auth_routes,
        "send_verification_email",
        fake_send_verification_email,
    )

    response = await auth_client.post(
        "/auth/register",
        json={
            "email": requested_email,
            "password": "Secret123!",
            "display_name": "Verifier",
        },
    )

    assert response.status_code == 201, response.text
    payload = response.json()
    assert payload["access_token"]
    assert payload["refresh_token"]
    assert payload["verification_email_status"] == "failed"
    assert delivery_attempts == [requested_email]
