from __future__ import annotations

import json
from typing import Any

import pytest

from app.services import supabase_auth


@pytest.fixture(autouse=True)
def _local_supabase_registration_stub():
    yield


def _install_dummy_async_client(
    monkeypatch,
    *,
    payload: dict[str, object],
) -> dict[str, dict[str, Any]]:
    captured: dict[str, dict[str, Any]] = {}

    class DummyResponse:
        status_code = 200

        def json(self):
            return payload

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"] = {"args": args, "kwargs": kwargs}

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def request(self, method, url, headers=None, content=None):
            captured["request"] = {
                "method": method,
                "url": url,
                "headers": headers,
                "content": content,
            }
            return DummyResponse()

    monkeypatch.setattr(supabase_auth.httpx, "AsyncClient", DummyAsyncClient)
    monkeypatch.setattr(
        supabase_auth, "_auth_base_url", lambda: "https://example.supabase.co/auth/v1"
    )
    monkeypatch.setattr(supabase_auth, "_public_api_key", lambda: "public-key")
    monkeypatch.setattr(supabase_auth, "_admin_api_key", lambda: "service-role-key")
    return captured


def _assert_json_transport(
    request: dict[str, Any],
    *,
    expected_content: bytes,
    api_key: str,
) -> None:
    assert request["method"] == "POST"
    assert request["headers"]["Content-Type"] == "application/json; charset=utf-8"
    assert request["headers"]["Authorization"] == f"Bearer {api_key}"
    assert request["headers"]["apikey"] == api_key
    assert request["content"] == expected_content


@pytest.mark.anyio("asyncio")
async def test_login_password_sends_raw_utf8_password_bytes(monkeypatch):
    captured = _install_dummy_async_client(
        monkeypatch,
        payload={
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "token_type": "bearer",
            "expires_in": 3600,
            "user": {"id": "user-123", "email": "user@example.com"},
        },
    )

    password = "l\u00f6senord\u00c5\u00c4\u00d6123"
    session = await supabase_auth.login_password("User@example.com", password)

    request = captured["request"]
    body = request["content"]
    decoded = json.loads(body.decode("utf-8"))
    assert decoded["email"] == "user@example.com"
    assert decoded["password"] == password
    assert b"\xc3\xb6" in body
    assert b"\xc3\x85" in body
    assert b"\xc3\x84" in body
    assert b"\xc3\x96" in body
    assert b"\\u00f6" not in body
    assert b"\\u00c5" not in body
    assert b"\\u00c4" not in body
    assert b"\\u00d6" not in body
    _assert_json_transport(
        request,
        expected_content=(
            b'{"email":"user@example.com","password":"l\xc3\xb6senord'
            b'\xc3\x85\xc3\x84\xc3\x96123"}'
        ),
        api_key="public-key",
    )
    assert session.user_id == "user-123"
    assert session.email == "user@example.com"


@pytest.mark.anyio("asyncio")
async def test_signup_keeps_ascii_password_behavior(monkeypatch):
    captured = _install_dummy_async_client(
        monkeypatch,
        payload={
            "user": {"id": "user-456", "email": "ascii@example.com"},
            "session": None,
        },
    )

    password = "Plain123"
    identity = await supabase_auth.signup("Ascii@example.com", password)

    request = captured["request"]
    body = request["content"]
    decoded = json.loads(body.decode("utf-8"))
    assert decoded["email"] == "ascii@example.com"
    assert decoded["password"] == password
    assert b"\\u00" not in body
    _assert_json_transport(
        request,
        expected_content=b'{"email":"ascii@example.com","password":"Plain123"}',
        api_key="public-key",
    )
    assert identity.user_id == "user-456"
    assert identity.email == "ascii@example.com"


@pytest.mark.anyio("asyncio")
async def test_refresh_session_uses_shared_utf8_json_transport(monkeypatch):
    captured = _install_dummy_async_client(
        monkeypatch,
        payload={
            "access_token": "access-token",
            "refresh_token": "new-refresh-token",
            "token_type": "bearer",
            "expires_in": 3600,
            "user": {"id": "user-789", "email": "refresh@example.com"},
        },
    )

    session = await supabase_auth.refresh_session("refresh-token-123")

    request = captured["request"]
    _assert_json_transport(
        request,
        expected_content=b'{"refresh_token":"refresh-token-123"}',
        api_key="public-key",
    )
    assert session.user_id == "user-789"
    assert session.refresh_token == "new-refresh-token"
