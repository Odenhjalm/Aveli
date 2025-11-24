import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock

import pytest
from psycopg.types.json import Jsonb

from app import db, repositories
from app.config import settings
from app.services import livekit as livekit_service

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(client, email: str, password: str, display_name: str):
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    assert register_resp.status_code == 201, register_resp.text

    login_resp = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, login_resp.text
    tokens = login_resp.json()
    profile_resp = await client.get("/profiles/me", headers=auth_header(tokens["access_token"]))
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


def patch_session_metadata_handling(monkeypatch: pytest.MonkeyPatch):
    original_create_session = repositories.create_seminar_session
    original_update_session = repositories.update_seminar_session

    async def _patched_create_session(*, metadata=None, **kwargs):
        json_metadata = Jsonb(metadata or {})
        return await original_create_session(metadata=json_metadata, **kwargs)

    async def _patched_update_session(*, fields=None, **kwargs):
        dict_fields = dict(fields or {})
        if "metadata" in dict_fields:
            dict_fields["metadata"] = Jsonb(dict_fields["metadata"] or {})
        return await original_update_session(fields=dict_fields, **kwargs)

    monkeypatch.setattr(repositories, "create_seminar_session", _patched_create_session)
    monkeypatch.setattr(repositories, "update_seminar_session", _patched_update_session)


async def test_seminar_session_lifecycle(async_client, monkeypatch):
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(async_client, teacher_email, password, "Teacher")
    await promote_to_teacher(teacher_id)

    student_email = f"student_{uuid.uuid4().hex[:6]}@wisdom.dev"
    student_token, student_id = await register_user(async_client, student_email, password, "Student")

    # Mock LiveKit REST calls so tests do not rely on external service
    monkeypatch.setattr(livekit_service, "create_room", AsyncMock(return_value=None))
    monkeypatch.setattr(livekit_service, "end_room", AsyncMock(return_value=None))

    patch_session_metadata_handling(monkeypatch)

    # Ensure LiveKit token generation succeeds in the test environment
    configure_livekit_settings()

    seminar_id = None
    session_id = None

    try:
        scheduled_at = datetime.now(timezone.utc) + timedelta(hours=1)
        create_resp = await async_client.post(
            "/studio/seminars",
            json={
                "title": "Lifecycle Seminar",
                "description": "Testing seminar lifecycle",
                "scheduled_at": scheduled_at.isoformat(),
                "duration_minutes": 45,
            },
            headers=auth_header(teacher_token),
        )
        assert create_resp.status_code == 200, create_resp.text
        seminar_id = str(create_resp.json()["id"])

        await repositories.set_seminar_status(
            seminar_id=seminar_id,
            host_id=teacher_id,
            status="scheduled",
        )
        await repositories.update_seminar(
            seminar_id=seminar_id,
            host_id=teacher_id,
            fields={"livekit_metadata": Jsonb({"is_free": True})},
        )

        # Student cannot start sessions
        resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/start",
            headers=auth_header(student_token),
        )
        assert resp.status_code == 403

        # Teacher starts a session
        start_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/start",
            json={},
            headers=auth_header(teacher_token),
        )
        assert start_resp.status_code == 200, start_resp.text
        payload = start_resp.json()
        session = payload["session"]
        session_id = session["id"]
        assert session["status"] == "live"
        assert session["started_at"] is not None

        # Fetch seminar detail to confirm session is live
        detail_resp = await async_client.get(
            f"/studio/seminars/{seminar_id}",
            headers=auth_header(teacher_token),
        )
        assert detail_resp.status_code == 200
        detail = detail_resp.json()
        assert any(item["id"] == session_id and item["status"] == "live" for item in detail["sessions"])

        # Starting same session again should yield conflict
        conflict_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/start",
            json={"session_id": session_id},
            headers=auth_header(teacher_token),
        )
        assert conflict_resp.status_code == 409

        # Student joins via register endpoint
        register_resp = await async_client.post(
            f"/seminars/{seminar_id}/register",
            headers=auth_header(student_token),
        )
        assert register_resp.status_code == 201

        # End the session
        end_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/{session_id}/end",
            headers=auth_header(teacher_token),
            json={"reason": "Testing complete"},
        )
        assert end_resp.status_code == 200, end_resp.text
        ended_session = end_resp.json()
        assert ended_session["status"] == "ended"
        assert ended_session["ended_at"] is not None

        # Public seminar detail should reflect ended session
        public_detail_resp = await async_client.get(
            f"/seminars/{seminar_id}",
            headers=auth_header(student_token),
        )
        assert public_detail_resp.status_code == 200
        public_detail = public_detail_resp.json()
        assert any(item["id"] == session_id and item["status"] == "ended" for item in public_detail["sessions"])
    finally:
        await cleanup_user(teacher_id)
        await cleanup_user(student_id)


async def test_start_session_merges_metadata_and_uses_existing_room(async_client, monkeypatch):
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher Metadata"
    )
    await promote_to_teacher(teacher_id)

    monkeypatch.setattr(livekit_service, "create_room", AsyncMock(return_value=None))
    monkeypatch.setattr(livekit_service, "end_room", AsyncMock(return_value=None))
    patch_session_metadata_handling(monkeypatch)
    configure_livekit_settings()

    try:
        scheduled_at = datetime.now(timezone.utc) + timedelta(hours=2)
        create_resp = await async_client.post(
            "/studio/seminars",
            json={
                "title": "Metadata Seminar",
                "description": "Testing metadata merge",
                "scheduled_at": scheduled_at.isoformat(),
                "duration_minutes": 30,
            },
            headers=auth_header(teacher_token),
        )
        assert create_resp.status_code == 200, create_resp.text
        seminar_id = str(create_resp.json()["id"])

        session_row = await repositories.create_seminar_session(
            seminar_id=seminar_id,
            status="scheduled",
            scheduled_at=scheduled_at,
            livekit_room="pre-existing-room",
            livekit_sid=None,
            metadata={"source": "precreate"},
        )
        session_id = str(session_row["id"])

        payload_metadata = {"custom_note": "host provided"}
        start_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/start",
            json={"session_id": session_id, "metadata": payload_metadata, "max_participants": 32},
            headers=auth_header(teacher_token),
        )
        assert start_resp.status_code == 200, start_resp.text
        data = start_resp.json()
        session = data["session"]
        assert session["id"] == session_id
        assert session["status"] == "live"
        assert session["livekit_room"] == "pre-existing-room"
        assert session["metadata"]["source"] == "precreate"
        assert session["metadata"]["custom_note"] == "host provided"
        assert session["metadata"]["started_by"] == teacher_id
        assert session["metadata"]["started_at"] is not None
        assert session["started_at"] is not None

        create_room_mock: AsyncMock = livekit_service.create_room  # type: ignore[assignment]
        await_args = create_room_mock.await_args
        assert await_args.args[0] == "pre-existing-room"
        assert await_args.kwargs["metadata"]["session_id"] == session_id
        assert await_args.kwargs["metadata"]["seminar_id"] == seminar_id
        assert await_args.kwargs["metadata"]["custom_note"] == "host provided"
        assert await_args.kwargs["max_participants"] == 32
    finally:
        await cleanup_user(teacher_id)


async def test_end_session_updates_metadata_and_calls_livekit(async_client, monkeypatch):
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher End Flow"
    )
    await promote_to_teacher(teacher_id)

    create_room_mock = AsyncMock(return_value=None)
    end_room_mock = AsyncMock(return_value=None)
    monkeypatch.setattr(livekit_service, "create_room", create_room_mock)
    monkeypatch.setattr(livekit_service, "end_room", end_room_mock)
    patch_session_metadata_handling(monkeypatch)
    configure_livekit_settings()

    try:
        scheduled_at = datetime.now(timezone.utc) + timedelta(minutes=45)
        create_resp = await async_client.post(
            "/studio/seminars",
            json={
                "title": "End Flow Seminar",
                "description": "Ensure ending works",
                "scheduled_at": scheduled_at.isoformat(),
                "duration_minutes": 60,
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

        reason = "Wrap up for QA"
        end_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/{session_id}/end",
            json={"reason": reason},
            headers=auth_header(teacher_token),
        )
        assert end_resp.status_code == 200, end_resp.text
        session = end_resp.json()
        assert session["status"] == "ended"
        assert session["ended_at"] is not None
        assert session["metadata"]["ended_by"] == teacher_id
        assert session["metadata"]["ended_at"] is not None

        await_args = end_room_mock.await_args
        assert await_args.args[0] == session["livekit_room"]
        assert await_args.kwargs["reason"] == reason

        # Fetch studio detail to ensure session is marked ended
        detail_resp = await async_client.get(
            f"/studio/seminars/{seminar_id}",
            headers=auth_header(teacher_token),
        )
        assert detail_resp.status_code == 200
        detail = detail_resp.json()
        assert any(item["id"] == session_id and item["status"] == "ended" for item in detail["sessions"])
    finally:
        await cleanup_user(teacher_id)
