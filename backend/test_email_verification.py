from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from jose import jwt
import pytest

from app.config import settings
from app.routes import auth as auth_routes
from app.routes import email_verification as email_verification_routes
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
    app.include_router(auth_routes.router)
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
    assert response.json() == {"status": "verified"}


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
async def test_register_endpoint_uses_canonical_auth_route(
    auth_client,
    monkeypatch,
):
    requested_email = f"verify_{uuid.uuid4().hex[:8]}@example.com"
    created_user_id = uuid.uuid4()

    async def fake_get_user_by_email(_: str) -> None:
        return None

    async def fake_create_user(email: str, password: str, display_name: str) -> uuid.UUID:
        assert email == requested_email
        assert password == "Secret123!"
        assert display_name == "Verifier"
        return created_user_id

    async def fake_get_user_by_id(user_id: str):
        return {"id": user_id, "email": requested_email}

    async def fake_get_profile_row(user_id: str):
        return {
            "user_id": user_id,
            "onboarding_state": "completed",
            "role_v2": "learner",
            "role": "learner",
            "is_admin": False,
        }

    async def fake_is_teacher_user(_: str) -> bool:
        return False

    async def fake_register_refresh_token(*_: object) -> None:
        return None

    recorded_events: list[str] = []

    async def fake_record_auth_event(**kwargs: object) -> None:
        recorded_events.append(str(kwargs["event"]))
        return None

    auth_routes._login_attempts.clear()
    monkeypatch.setattr(auth_routes.models, "get_user_by_email", fake_get_user_by_email)
    monkeypatch.setattr(auth_routes.models, "create_user", fake_create_user)
    monkeypatch.setattr(auth_routes.models, "get_user_by_id", fake_get_user_by_id)
    monkeypatch.setattr(auth_routes.models, "get_profile_row", fake_get_profile_row)
    monkeypatch.setattr(auth_routes.models, "is_teacher_user", fake_is_teacher_user)
    monkeypatch.setattr(
        auth_routes.models,
        "register_refresh_token",
        fake_register_refresh_token,
    )
    monkeypatch.setattr(
        auth_routes.models,
        "record_auth_event",
        fake_record_auth_event,
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
    assert recorded_events[-1] == "register_success"
