import uuid

import pytest

from app import db


pytestmark = pytest.mark.anyio("asyncio")


async def register_teacher(async_client):
    email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Secret123!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Teacher"},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    profile_resp = await async_client.get("/profiles/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]
    await promote_to_teacher(user_id)
    return headers, user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
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
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def create_lesson(async_client, headers):
    slug = f"course-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Direct Upload Course",
            "slug": slug,
            "description": "Course for direct upload tests",
            "is_published": False,
        },
    )
    assert course_resp.status_code == 200, course_resp.text
    course_id = str(course_resp.json()["id"])

    lesson_resp = await async_client.post(
        "/studio/lessons",
        headers=headers,
        json={
            "course_id": course_id,
            "title": "Lesson",
            "content_markdown": "# Lesson",
            "position": 1,
            "is_intro": False,
        },
    )
    assert lesson_resp.status_code == 200, lesson_resp.text
    lesson_id = str(lesson_resp.json()["id"])
    return course_id, lesson_id


async def _lesson_media_count(lesson_id: str) -> int:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "SELECT count(*) FROM app.lesson_media WHERE lesson_id = %s",
                (lesson_id,),
            )
            row = await cur.fetchone()
    return int(row[0] or 0)


async def test_direct_lesson_media_presign_route_is_disabled(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

        resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media/presign",
            headers=headers,
            json={
                "filename": "demo.mp4",
                "content_type": "video/mp4",
                "media_type": "video",
            },
        )
        assert resp.status_code == 410, resp.text
        assert resp.json()["detail"] == "Legacy lesson upload is disabled"
        assert await _lesson_media_count(lesson_id) == 0
    finally:
        await cleanup_user(user_id)


async def test_direct_lesson_media_complete_route_is_disabled(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

        resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media/complete",
            headers=headers,
            json={
                "storage_path": f"lessons/{lesson_id}/demo.mp4",
                "storage_bucket": "course-media",
                "content_type": "video/mp4",
                "byte_size": 1024,
                "original_name": "demo.mp4",
            },
        )
        assert resp.status_code == 410, resp.text
        assert resp.json()["detail"] == "Legacy lesson upload is disabled"
        assert await _lesson_media_count(lesson_id) == 0
    finally:
        await cleanup_user(user_id)


async def test_direct_lesson_media_post_route_is_disabled(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

        resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media",
            headers=headers,
            files={"file": ("demo.mp4", b"mp4-bytes", "video/mp4")},
        )
        assert resp.status_code == 410, resp.text
        assert resp.json()["detail"] == "Legacy lesson upload is disabled"
        assert await _lesson_media_count(lesson_id) == 0
    finally:
        await cleanup_user(user_id)
