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

    tokens = register_resp.json()
    access_token = tokens["access_token"]
    profile_resp = await client.get("/profiles/me", headers=auth_header(access_token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    return access_token, user_id


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


async def test_teacher_can_manage_sessions_and_slots(async_client):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("select to_regclass('app.sessions')")
            row = await cur.fetchone()
    if not row or row[0] is None:
        pytest.skip("app.sessions not present in current database")

    email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    token, user_id = await register_user(async_client, email, password, "Studio Teacher")
    await promote_to_teacher(user_id)

    session_id = None
    slot_id = None

    try:
        start_at = datetime.now(timezone.utc) + timedelta(hours=1)
        end_at = start_at + timedelta(hours=1)
        create_payload = {
            "title": "Studio Session Smoke",
            "description": "Testing booking service via API",
            "capacity": 5,
            "price_cents": 2500,
            "currency": "sek",
            "start_at": start_at.isoformat(),
            "end_at": end_at.isoformat(),
            "visibility": "draft",
        }
        create_resp = await async_client.post(
            "/studio/sessions",
            json=create_payload,
            headers=auth_header(token),
        )
        assert create_resp.status_code == 201, create_resp.text
        session = create_resp.json()
        session_id = str(session["id"])
        assert session["title"] == create_payload["title"]

        # Listing returns the created session
        list_resp = await async_client.get("/studio/sessions", headers=auth_header(token))
        assert list_resp.status_code == 200, list_resp.text
        session_ids = {str(item["id"]) for item in list_resp.json()["items"]}
        assert session_id in session_ids

        # Update visibility to published
        update_resp = await async_client.put(
            f"/studio/sessions/{session_id}",
            json={"visibility": "published"},
            headers=auth_header(token),
        )
        assert update_resp.status_code == 200, update_resp.text
        assert update_resp.json()["visibility"] == "published"

        # Create a slot
        slot_payload = {
            "start_at": (start_at + timedelta(hours=2)).isoformat(),
            "end_at": (start_at + timedelta(hours=3)).isoformat(),
            "seats_total": 3,
        }
        slot_resp = await async_client.post(
            f"/studio/sessions/{session_id}/slots",
            json=slot_payload,
            headers=auth_header(token),
        )
        assert slot_resp.status_code == 201, slot_resp.text
        slot = slot_resp.json()
        slot_id = str(slot["id"])
        assert slot["seats_total"] == slot_payload["seats_total"]

        # Fetch slots list
        slots_resp = await async_client.get(
            f"/studio/sessions/{session_id}/slots",
            headers=auth_header(token),
        )
        assert slots_resp.status_code == 200
        slot_ids = {str(item["id"]) for item in slots_resp.json()["items"]}
        assert slot_id in slot_ids

        # Update slot seats
        slot_update_resp = await async_client.patch(
            f"/studio/sessions/{session_id}/slots/{slot_id}",
            json={"seats_total": 4},
            headers=auth_header(token),
        )
        assert slot_update_resp.status_code == 200
        assert slot_update_resp.json()["seats_total"] == 4
    finally:
        if session_id:
            await async_client.delete(
                f"/studio/sessions/{session_id}",
                headers=auth_header(token),
            )
        await cleanup_user(user_id)
