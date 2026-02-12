import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app import db


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
    access_token = tokens["access_token"]

    profile_resp = await client.get("/profiles/me", headers=auth_header(access_token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    return access_token, user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.profiles
                SET role_v2 = 'teacher',
                    updated_at = now()
                WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def test_events_and_notifications_flow(async_client):
    teacher_email = f"teacher_events_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"student_events_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    teacher_id = None
    student_id = None
    try:
        teacher_token, teacher_id = await register_user(
            async_client, teacher_email, password, "Teacher"
        )
        student_token, student_id = await register_user(
            async_client, student_email, password, "Student"
        )

        await promote_to_teacher(teacher_id)

        now = datetime.now(timezone.utc)
        start_at = now + timedelta(days=1)
        end_at = start_at + timedelta(hours=1)

        # Teacher creates a public scheduled event.
        create_event = await async_client.post(
            "/api/events",
            json={
                "type": "live_class",
                "title": "Test Event",
                "description": "Hello",
                "start_at": start_at.isoformat(),
                "end_at": end_at.isoformat(),
                "timezone": "Europe/Stockholm",
                "status": "scheduled",
                "visibility": "public",
            },
            headers=auth_header(teacher_token),
        )
        assert create_event.status_code == 201, create_event.text
        event = create_event.json()
        event_id = event["id"]
        assert event["created_by"] == teacher_id
        assert event["visibility"] == "public"
        assert event["status"] == "scheduled"

        # Student can see the public event.
        student_list = await async_client.get(
            "/api/events",
            headers=auth_header(student_token),
        )
        assert student_list.status_code == 200, student_list.text
        items = student_list.json()["items"]
        assert any(row["id"] == event_id for row in items)

        student_get = await async_client.get(
            f"/api/events/{event_id}",
            headers=auth_header(student_token),
        )
        assert student_get.status_code == 200, student_get.text

        # Status cannot move backwards.
        back_status = await async_client.patch(
            f"/api/events/{event_id}",
            json={"status": "draft"},
            headers=auth_header(teacher_token),
        )
        assert back_status.status_code == 400, back_status.text

        # Teacher creates an invited event and registers student explicitly.
        invited_resp = await async_client.post(
            "/api/events",
            json={
                "type": "ceremony",
                "title": "Invited Only",
                "start_at": start_at.isoformat(),
                "end_at": end_at.isoformat(),
                "timezone": "UTC",
                "status": "scheduled",
                "visibility": "invited",
            },
            headers=auth_header(teacher_token),
        )
        assert invited_resp.status_code == 201, invited_resp.text
        invited_event_id = invited_resp.json()["id"]

        invited_self_register = await async_client.post(
            f"/api/events/{invited_event_id}/participants",
            json={},
            headers=auth_header(student_token),
        )
        assert invited_self_register.status_code == 403, invited_self_register.text

        invited_register = await async_client.post(
            f"/api/events/{invited_event_id}/participants",
            json={"user_id": student_id, "role": "participant"},
            headers=auth_header(teacher_token),
        )
        assert invited_register.status_code == 201, invited_register.text

        invited_get = await async_client.get(
            f"/api/events/{invited_event_id}",
            headers=auth_header(student_token),
        )
        assert invited_get.status_code == 200, invited_get.text

        # Teacher sends an in-app notification to event participants.
        notif_resp = await async_client.post(
            "/api/notifications",
            json={
                "type": "manual",
                "channel": "in_app",
                "title": "Welcome",
                "body": "See you soon",
                "audiences": [
                    {"audience_type": "event_participants", "event_id": invited_event_id}
                ],
            },
            headers=auth_header(teacher_token),
        )
        assert notif_resp.status_code == 201, notif_resp.text
        notification = notif_resp.json()["notification"]
        assert notification["title"] == "Welcome"
        assert notification["recipient_count"] >= 2  # host + student

        # Event owner can list event notifications.
        list_notifs = await async_client.get(
            f"/api/events/{invited_event_id}/notifications",
            headers=auth_header(teacher_token),
        )
        assert list_notifs.status_code == 200, list_notifs.text
        notif_items = list_notifs.json()["items"]
        assert any(row["id"] == notification["id"] for row in notif_items)
    finally:
        if student_id:
            await cleanup_user(student_id)
        if teacher_id:
            await cleanup_user(teacher_id)


async def test_notifications_require_teacher(async_client):
    student_email = f"student_notify_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    token, user_id = await register_user(async_client, student_email, password, "Student")
    try:
        resp = await async_client.post(
            "/api/notifications",
            json={
                "type": "manual",
                "channel": "in_app",
                "title": "Nope",
                "body": "Nope",
                "audiences": [{"audience_type": "all_members"}],
            },
            headers=auth_header(token),
        )
        assert resp.status_code == 403, resp.text
    finally:
        await cleanup_user(user_id)
