import uuid

import pytest

from app import db

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_teacher(async_client):
    email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": "Teacher",
        },
    )
    assert register_resp.status_code == 201, register_resp.text

    login_resp = await async_client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, login_resp.text
    tokens = login_resp.json()
    access_token = tokens["access_token"]

    profile_resp = await async_client.get("/profiles/me", headers=auth_header(access_token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])

    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()

    return access_token, user_id


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def test_studio_lesson_newline_persists_in_storage(async_client):
    token, user_id = await register_teacher(async_client)

    try:
        slug = f"course-{uuid.uuid4().hex[:8]}"
        resp = await async_client.post(
            "/studio/courses",
            json={"title": "Course", "slug": slug},
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text
        course_id = str(resp.json()["id"])

        resp = await async_client.post(
            "/studio/modules",
            json={"course_id": course_id, "title": "Module 1", "position": 1},
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text
        module_id = str(resp.json()["id"])

        resp = await async_client.post(
            "/studio/lessons",
            json={
                "module_id": module_id,
                "title": "Lesson 1",
                "content_markdown": "Hello world\n\nThis is a lesson\n\n",
                "position": 1,
                "is_intro": True,
            },
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text
        lesson_id = str(resp.json()["id"])

        edited_markdown = "Hello world\n\n\n\nThis is a lesson\n\n"
        resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            json={"content_markdown": edited_markdown},
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text

        resp = await async_client.get(
            f"/studio/modules/{module_id}/lessons",
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text

        lesson = next(
            item for item in resp.json()["items"] if str(item["id"]) == lesson_id
        )
        assert lesson["content_markdown"] == edited_markdown
    finally:
        await cleanup_user(user_id)

