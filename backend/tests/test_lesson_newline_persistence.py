import uuid

import pytest

from app import db
from app.repositories import courses as courses_repo

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def studio_course_payload(title: str, slug: str) -> dict[str, object]:
    return {
        "title": title,
        "slug": slug,
        "course_group_id": str(uuid.uuid4()),
        "step": "intro",
        "price_amount_cents": None,
        "drip_enabled": False,
        "drip_interval_days": None,
    }


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
                """
                UPDATE app.auth_subjects
                   SET role_v2 = 'teacher',
                       role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()

    return access_token, user_id


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def read_lesson_content_etag(
    async_client,
    *,
    lesson_id: str,
    token: str,
) -> str:
    response = await async_client.get(
        f"/studio/lessons/{lesson_id}/content",
        headers=auth_header(token),
    )
    assert response.status_code == 200, response.text
    assert set(response.json()) == {"lesson_id", "content_markdown", "media"}
    etag = response.headers.get("etag")
    assert etag
    return etag


async def test_studio_lesson_newline_persists_in_storage(async_client):
    token, user_id = await register_teacher(async_client)

    try:
        slug = f"course-{uuid.uuid4().hex[:8]}"
        resp = await async_client.post(
            "/studio/courses",
            json=studio_course_payload("Course", slug),
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text
        course_id = str(resp.json()["id"])

        resp = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            json={
                "lesson_title": "Lesson 1",
                "position": 1,
            },
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text
        lesson_id = str(resp.json()["id"])

        resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            json={"content_markdown": "Hello world\n\nThis is a lesson\n\n"},
            headers={
                **auth_header(token),
                "If-Match": await read_lesson_content_etag(
                    async_client,
                    lesson_id=lesson_id,
                    token=token,
                ),
            },
        )
        assert resp.status_code == 200, resp.text

        edited_markdown = "Hello world\n\n\n\nThis is a lesson\n\n"
        resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            json={"content_markdown": edited_markdown},
            headers={
                **auth_header(token),
                "If-Match": resp.headers["etag"],
            },
        )
        assert resp.status_code == 200, resp.text

        resp = await async_client.get(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(token),
        )
        assert resp.status_code == 200, resp.text

        lesson = next(
            item for item in resp.json()["items"] if str(item["id"]) == lesson_id
        )
        assert "content_markdown" not in lesson

        stored = await courses_repo.get_lesson(lesson_id)
        assert stored is not None
        assert stored["content_markdown"] == edited_markdown
    finally:
        await cleanup_user(user_id)
