import uuid

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
    return access_token, tokens["refresh_token"], user_id


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def test_posts_and_messages_flow(async_client):
    student_email = f"student_{uuid.uuid4().hex[:8]}@example.com"
    teacher_email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    student_id = None
    teacher_id = None
    try:
        student_access, _, student_id = await register_user(
            async_client, student_email, password, "Student"
        )
        teacher_access, _, teacher_id = await register_user(
            async_client, teacher_email, password, "Teacher"
        )

        # Student creates a community post.
        post_resp = await async_client.post(
            "/community/posts",
            json={"content": "Hej Visdom!"},
            headers=auth_header(student_access),
        )
        assert post_resp.status_code == 201, post_resp.text
        post_payload = post_resp.json()
        assert post_payload["content"] == "Hej Visdom!"

        # Student follows teacher profile.
        follow_resp = await async_client.post(
            f"/community/follows/{teacher_id}",
            headers=auth_header(student_access),
        )
        assert follow_resp.status_code == 204, follow_resp.text

        async def _follow_exists() -> int:
            async with db.pool.connection() as conn:  # type: ignore
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        "SELECT COUNT(*) FROM app.follows WHERE follower_id = %s AND followee_id = %s",
                        (student_id, teacher_id),
                    )
                    row = await cur.fetchone()
                    return int(row[0]) if row else 0

        assert await _follow_exists() == 1

        detail_resp = await async_client.get(
            f"/community/profiles/{teacher_id}",
            headers=auth_header(student_access),
        )
        assert detail_resp.status_code == 403, detail_resp.text

        teacher_self_resp = await async_client.get(
            f"/community/profiles/{teacher_id}",
            headers=auth_header(teacher_access),
        )
        assert teacher_self_resp.status_code == 200, teacher_self_resp.text

        # Student sends a message on the global channel.
        message_resp = await async_client.post(
            "/community/messages",
            json={"channel": "global", "content": "Hej alla!"},
            headers=auth_header(student_access),
        )
        assert message_resp.status_code == 201, message_resp.text
        message_payload = message_resp.json()
        assert message_payload["channel"] == "global"
        assert message_payload["content"] == "Hej alla!"

        # Messages can be listed and include the just-sent message.
        list_resp = await async_client.get(
            "/community/messages",
            params={"channel": "global"},
            headers=auth_header(student_access),
        )
        assert list_resp.status_code == 200, list_resp.text
        items = list_resp.json()["items"]
        assert any(item["id"] == message_payload["id"] for item in items)

        anon_list = await async_client.get(
            "/community/messages",
            params={"channel": "global"},
        )
        assert anon_list.status_code == 401

        # Anonymous users may not post messages.
        anon_resp = await async_client.post(
            "/community/messages",
            json={"channel": "global", "content": "anon"},
        )
        assert anon_resp.status_code == 401

        # Student can unfollow the teacher.
        unfollow_resp = await async_client.delete(
            f"/community/follows/{teacher_id}",
            headers=auth_header(student_access),
        )
        assert unfollow_resp.status_code == 204, unfollow_resp.text

        assert await _follow_exists() == 0

        detail_after = await async_client.get(
            f"/community/profiles/{teacher_id}",
            headers=auth_header(student_access),
        )
        assert detail_after.status_code == 403, detail_after.text

    finally:
        if teacher_id:
            await cleanup_user(teacher_id)
        if student_id:
            await cleanup_user(student_id)


async def test_dm_channel_requires_membership(async_client):
    alice_email = f"alice_{uuid.uuid4().hex[:8]}@example.com"
    bob_email = f"bob_{uuid.uuid4().hex[:8]}@example.com"
    mallory_email = f"mallory_{uuid.uuid4().hex[:8]}@example.com"
    password = "Sup3rSecret!"

    alice_id = bob_id = mallory_id = None
    try:
        alice_access, _, alice_id = await register_user(async_client, alice_email, password, "Alice")
        bob_access, _, bob_id = await register_user(async_client, bob_email, password, "Bob")
        mallory_access, _, mallory_id = await register_user(async_client, mallory_email, password, "Mallory")

        channel_parts = sorted([alice_id, bob_id])
        dm_channel = f"dm:{channel_parts[0]}:{channel_parts[1]}"

        dm_message = await async_client.post(
            "/community/messages",
            json={"channel": dm_channel, "content": "Hej Bob!"},
            headers=auth_header(alice_access),
        )
        assert dm_message.status_code == 201, dm_message.text
        created = dm_message.json()

        dm_list_bob = await async_client.get(
            "/community/messages",
            params={"channel": dm_channel},
            headers=auth_header(bob_access),
        )
        assert dm_list_bob.status_code == 200, dm_list_bob.text
        bob_items = dm_list_bob.json()["items"]
        assert any(item["id"] == created["id"] for item in bob_items)

        dm_list_mallory = await async_client.get(
            "/community/messages",
            params={"channel": dm_channel},
            headers=auth_header(mallory_access),
        )
        assert dm_list_mallory.status_code == 403

        dm_send_mallory = await async_client.post(
            "/community/messages",
            json={"channel": dm_channel, "content": "Hej, jag smyger!"},
            headers=auth_header(mallory_access),
        )
        assert dm_send_mallory.status_code == 403

    finally:
        if mallory_id:
            await cleanup_user(mallory_id)
        if bob_id:
            await cleanup_user(bob_id)
        if alice_id:
            await cleanup_user(alice_id)
