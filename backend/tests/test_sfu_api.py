import uuid
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock

import pytest

from app import db
from app.config import settings
from app.services import livekit as livekit_service

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(client, email: str, password: str, display_name: str):
    base_email = email
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    if register_resp.status_code == 409:
        # Avoid collisions across test runs by regenerating a unique address.
        unique_email = f"{base_email.split('@')[0]}+{uuid.uuid4().hex[:6]}@{base_email.split('@')[1]}"
        register_resp = await client.post(
            "/auth/register",
            json={
                "email": unique_email,
                "password": password,
                "display_name": display_name,
            },
        )
        assert register_resp.status_code == 201, register_resp.text
        email = unique_email
    else:
        assert register_resp.status_code == 201, register_resp.text

    login_resp = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, login_resp.text
    tokens = login_resp.json()
    profile_resp = await client.get(
        "/profiles/me", headers=auth_header(tokens["access_token"])
    )
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    return tokens["access_token"], user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


def configure_livekit_settings():
    settings.livekit_api_key = "test_key"
    settings.livekit_api_secret = "test_secret"
    settings.livekit_ws_url = "wss://test.example.com"
    settings.livekit_api_url = "https://api.test"


def patch_session_metadata_handling(monkeypatch: pytest.MonkeyPatch):
    # Metadata conversion now handled within repository implementation.
    pass


async def _create_live_session(
    async_client,
    monkeypatch: pytest.MonkeyPatch,
    teacher_token: str,
    teacher_id: str,
    *,
    create_room_mock: AsyncMock | None = None,
) -> tuple[str, str]:
    configure_livekit_settings()
    patch_session_metadata_handling(monkeypatch)
    monkeypatch.setattr(
        livekit_service,
        "create_room",
        create_room_mock or AsyncMock(return_value=None),
    )
    monkeypatch.setattr(livekit_service, "end_room", AsyncMock(return_value=None))

    scheduled_at = datetime.now(timezone.utc) + timedelta(hours=1)
    create_resp = await async_client.post(
        "/studio/seminars",
        json={
            "title": "SFU Negative Tests",
            "description": "Token endpoint checks",
            "scheduled_at": scheduled_at.isoformat(),
            "duration_minutes": 30,
        },
        headers=auth_header(teacher_token),
    )
    assert create_resp.status_code == 200, create_resp.text
    seminar_id = str(create_resp.json()["id"])

    start_resp = await async_client.post(
        f"/studio/seminars/{seminar_id}/sessions/start",
        json={},
        headers=auth_header(teacher_token),
    )
    assert start_resp.status_code == 200, start_resp.text
    session_id = start_resp.json()["session"]["id"]
    return seminar_id, session_id


async def test_start_session_survives_livekit_rest_error(async_client, monkeypatch):
    teacher_token, teacher_id = await register_user(
        async_client, "sfu_rest_error@wisdom.dev", "Passw0rd!", "Host Rest"
    )
    await promote_to_teacher(teacher_id)
    try:
        create_room_mock = AsyncMock(
            side_effect=livekit_service.LiveKitRESTError("network down"),
        )
        await _create_live_session(
            async_client,
            monkeypatch,
            teacher_token,
            teacher_id,
            create_room_mock=create_room_mock,
        )
        assert create_room_mock.await_count == 1
    finally:
        await cleanup_user(teacher_id)


async def test_sfu_token_requires_livekit_configuration(async_client, monkeypatch):
    token, user_id = await register_user(
        async_client, "sfu_config@wisdom.dev", "Passw0rd!", "Config"
    )
    original_key = settings.livekit_api_key
    original_secret = settings.livekit_api_secret
    original_ws = settings.livekit_ws_url
    try:
        monkeypatch.setattr(settings, "livekit_api_key", None, raising=False)
        monkeypatch.setattr(settings, "livekit_api_secret", None, raising=False)
        monkeypatch.setattr(settings, "livekit_ws_url", None, raising=False)

        resp = await async_client.post(
            "/sfu/token",
            headers=auth_header(token),
            json={"seminar_id": str(uuid.uuid4())},
        )
        assert resp.status_code == 503
        assert resp.json()["detail"] == "LiveKit configuration missing"
    finally:
        settings.livekit_api_key = original_key
        settings.livekit_api_secret = original_secret
        settings.livekit_ws_url = original_ws
        await cleanup_user(user_id)


async def test_sfu_token_seminar_not_found(async_client):
    configure_livekit_settings()
    token, user_id = await register_user(
        async_client, "sfu_404@wisdom.dev", "Passw0rd!", "Missing Seminar"
    )
    try:
        resp = await async_client.post(
            "/sfu/token",
            headers=auth_header(token),
            json={"seminar_id": str(uuid.uuid4())},
        )
        assert resp.status_code == 404
        assert resp.json()["detail"] == "Seminar not found"
    finally:
        await cleanup_user(user_id)


async def test_sfu_token_denied_without_registration(async_client, monkeypatch):
    teacher_token, teacher_id = await register_user(
        async_client, "sfu_host@wisdom.dev", "Passw0rd!", "Host"
    )
    student_token, student_id = await register_user(
        async_client, "sfu_student@wisdom.dev", "Passw0rd!", "Student"
    )
    await promote_to_teacher(teacher_id)

    seminar_id = session_id = None
    try:
        seminar_id, session_id = await _create_live_session(
            async_client, monkeypatch, teacher_token, teacher_id
        )

        resp = await async_client.post(
            "/sfu/token",
            headers=auth_header(student_token),
            json={
                "seminar_id": seminar_id,
                "session_id": session_id,
            },
        )
        assert resp.status_code == 403
        assert resp.json()["detail"] == "No access to seminar"
    finally:
        await cleanup_user(teacher_id)
        await cleanup_user(student_id)


async def test_sfu_token_rejects_ended_session(async_client, monkeypatch):
    teacher_token, teacher_id = await register_user(
        async_client, "sfu_end_host@wisdom.dev", "Passw0rd!", "Host End"
    )
    await promote_to_teacher(teacher_id)

    seminar_id = session_id = None
    try:
        seminar_id, session_id = await _create_live_session(
            async_client, monkeypatch, teacher_token, teacher_id
        )

        end_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/{session_id}/end",
            headers=auth_header(teacher_token),
            json={"reason": "end test"},
        )
        assert end_resp.status_code == 200, end_resp.text

        resp = await async_client.post(
            "/sfu/token",
            headers=auth_header(teacher_token),
            json={"seminar_id": seminar_id, "session_id": session_id},
        )
        assert resp.status_code == 409
        assert resp.json()["detail"] == "Session already ended"
    finally:
        await cleanup_user(teacher_id)


async def test_sfu_webhook_missing_event_returns_400(async_client):
    resp = await async_client.post(
        "/sfu/webhooks/livekit",
        json={"room": {"name": "missing-event"}},
    )
    assert resp.status_code == 400
    assert resp.json()["detail"] == "Missing event type"


async def test_sfu_webhook_invalid_signature(async_client, monkeypatch):
    monkeypatch.setattr(settings, "livekit_webhook_secret", "topsecret", raising=False)
    resp = await async_client.post(
        "/sfu/webhooks/livekit",
        headers={"X-Livekit-Signature": "wrong"},
        json={"event": "room_started"},
    )
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Invalid signature"
