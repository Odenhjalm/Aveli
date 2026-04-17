import uuid
from datetime import datetime, timedelta, timezone

import pytest
from psycopg.types.json import Jsonb

from app import db, repositories

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
                """
                UPDATE app.auth_subjects
                   SET role_v2 = 'teacher',
                       role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


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


async def test_seminar_session_livekit_start_is_paused(async_client, monkeypatch):
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(async_client, teacher_email, password, "Teacher")
    await promote_to_teacher(teacher_id)

    student_email = f"student_{uuid.uuid4().hex[:6]}@wisdom.dev"
    student_token, student_id = await register_user(async_client, student_email, password, "Student")

    patch_session_metadata_handling(monkeypatch)

    seminar_id = None

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

        # Teacher start is fail-closed while LiveKit is paused.
        start_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/start",
            json={},
            headers=auth_header(teacher_token),
        )
        assert start_resp.status_code == 503, start_resp.text
        assert start_resp.json()["detail"] == "LiveKit är pausat."

        # Fetch seminar detail to confirm no LiveKit session was started.
        detail_resp = await async_client.get(
            f"/studio/seminars/{seminar_id}",
            headers=auth_header(teacher_token),
        )
        assert detail_resp.status_code == 200
        detail = detail_resp.json()
        assert not any(item["status"] == "live" for item in detail["sessions"])

        # Student joins via register endpoint
        register_resp = await async_client.post(
            f"/seminars/{seminar_id}/register",
            headers=auth_header(student_token),
        )
        assert register_resp.status_code == 201
    finally:
        await cleanup_user(teacher_id)
        await cleanup_user(student_id)


async def test_start_session_does_not_mutate_existing_room_while_livekit_paused(
    async_client,
    monkeypatch,
):
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher Metadata"
    )
    await promote_to_teacher(teacher_id)

    patch_session_metadata_handling(monkeypatch)

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
        assert start_resp.status_code == 503, start_resp.text
        assert start_resp.json()["detail"] == "LiveKit är pausat."

        session = await repositories.get_seminar_session(session_id)
        assert session is not None
        assert session["status"] == "scheduled"
        assert session["livekit_room"] == "pre-existing-room"
        assert session["metadata"] == {"source": "precreate"}
    finally:
        await cleanup_user(teacher_id)


async def test_end_session_does_not_mutate_while_livekit_paused(
    async_client,
    monkeypatch,
):
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher End Flow"
    )
    await promote_to_teacher(teacher_id)

    patch_session_metadata_handling(monkeypatch)

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

        session_row = await repositories.create_seminar_session(
            seminar_id=seminar_id,
            status="live",
            scheduled_at=scheduled_at,
            livekit_room="paused-room",
            livekit_sid=None,
            metadata={"source": "precreate"},
        )
        session_id = str(session_row["id"])

        reason = "Wrap up for QA"
        end_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/{session_id}/end",
            json={"reason": reason},
            headers=auth_header(teacher_token),
        )
        assert end_resp.status_code == 503, end_resp.text
        assert end_resp.json()["detail"] == "LiveKit är pausat."

        session = await repositories.get_seminar_session(session_id)
        assert session is not None
        assert session["status"] == "live"
        assert session["metadata"] == {"source": "precreate"}
        assert session["ended_at"] is None
        assert session["livekit_room"] == "paused-room"

        # Fetch studio detail to ensure session was not marked ended.
        detail_resp = await async_client.get(
            f"/studio/seminars/{seminar_id}",
            headers=auth_header(teacher_token),
        )
        assert detail_resp.status_code == 200
        detail = detail_resp.json()
        assert any(item["id"] == session_id and item["status"] == "live" for item in detail["sessions"])
    finally:
        await cleanup_user(teacher_id)


async def test_end_session_rejects_missing_session_before_livekit_pause(
    async_client,
    monkeypatch,
):
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher Missing Session"
    )
    await promote_to_teacher(teacher_id)

    patch_session_metadata_handling(monkeypatch)

    try:
        scheduled_at = datetime.now(timezone.utc) + timedelta(minutes=45)
        create_resp = await async_client.post(
            "/studio/seminars",
            json={
                "title": "Missing Session Seminar",
                "description": "Ensure lookup still fails first",
                "scheduled_at": scheduled_at.isoformat(),
                "duration_minutes": 60,
            },
            headers=auth_header(teacher_token),
        )
        assert create_resp.status_code == 200, create_resp.text
        seminar_id = str(create_resp.json()["id"])

        end_resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/sessions/{uuid.uuid4()}/end",
            json={"reason": "No session"},
            headers=auth_header(teacher_token),
        )
        assert end_resp.status_code == 404, end_resp.text
    finally:
        await cleanup_user(teacher_id)
