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

    profile_resp = await client.get(
        "/profiles/me", headers=auth_header(tokens["access_token"])
    )
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    return tokens["access_token"], tokens["refresh_token"], user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def test_profile_media_requires_teacher(async_client):
    email = f"profile_{uuid.uuid4().hex[:6]}@example.com"
    password = "Passw0rd!"
    access_token, _, user_id = await register_user(
        async_client, email, password, "Profile User"
    )

    try:
        resp = await async_client.get(
            "/studio/profile/media", headers=auth_header(access_token)
        )
        assert resp.status_code == 403
    finally:
        await cleanup_user(user_id)


async def test_teacher_profile_media_flow(async_client):
    teacher_email = f"teacher_profile_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    access_token, _, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher Profile"
    )
    await promote_to_teacher(teacher_id)

    course_id = None
    module_id = None
    lesson_id = None
    lesson_media_id = None
    seminar_id = None
    recording_id = None
    profile_media_id = None

    try:
        slug = f"profile-course-{uuid.uuid4().hex[:6]}"
        course_payload = {
            "title": "Profile Course",
            "slug": slug,
            "description": "Featured course for profile media testing",
            "is_free_intro": True,
            "is_published": True,
            "price_amount_cents": 0,
        }
        resp = await async_client.post(
            "/studio/courses",
            json=course_payload,
            headers=auth_header(access_token),
        )
        assert resp.status_code == 200, resp.text
        course_id = str(resp.json()["id"])

        resp = await async_client.post(
            "/studio/modules",
            json={"course_id": course_id, "title": "Profile Module", "position": 1},
            headers=auth_header(access_token),
        )
        assert resp.status_code == 200, resp.text
        module_id = str(resp.json()["id"])

        resp = await async_client.post(
            "/studio/lessons",
            json={
                "module_id": module_id,
                "title": "Profile Lesson",
                "content_markdown": "# Featured lesson",
                "position": 1,
                "is_intro": True,
            },
            headers=auth_header(access_token),
        )
        assert resp.status_code == 200, resp.text
        lesson_id = str(resp.json()["id"])

        resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media",
            headers=auth_header(access_token),
            files={"file": ("profile.mp3", b"ID3", "audio/mpeg")},
            data={"is_intro": "false"},
        )
        assert resp.status_code == 200, resp.text
        lesson_media_id = str(resp.json()["id"])

        resp = await async_client.post(
            "/studio/seminars",
            json={
                "title": "Profile Seminar",
                "description": "Meditation live session",
            },
            headers=auth_header(access_token),
        )
        assert resp.status_code == 200, resp.text
        seminar_id = str(resp.json()["id"])

        resp = await async_client.post(
            f"/studio/seminars/{seminar_id}/recordings/reserve",
            json={"extension": "mp4"},
            headers=auth_header(access_token),
        )
        assert resp.status_code == 200, resp.text
        recording_payload = resp.json()
        recording_id = str(recording_payload["id"])
        asset_url = recording_payload["asset_url"]
        assert asset_url.endswith(".mp4")

        resp = await async_client.get(
            "/studio/profile/media", headers=auth_header(access_token)
        )
        assert resp.status_code == 200, resp.text
        payload = resp.json()
        lesson_sources = {item["id"] for item in payload["lesson_media"]}
        recording_sources = {item["id"] for item in payload["seminar_recordings"]}
        assert lesson_media_id in lesson_sources
        assert recording_id in recording_sources
        assert payload["items"] == []

        resp = await async_client.post(
            "/studio/profile/media",
            json={
                "media_kind": "lesson_media",
                "media_id": lesson_media_id,
                "title": "Featured Meditation",
                "description": "Relaxing audio clip",
                "position": 5,
                "is_published": True,
            },
            headers=auth_header(access_token),
        )
        assert resp.status_code == 201, resp.text
        created_item = resp.json()
        profile_media_id = str(created_item["id"])
        assert created_item["source"]["lesson_media"]["id"] == lesson_media_id
        public_resp = await async_client.get(
            f"/community/teachers/{teacher_id}/media"
        )
        assert public_resp.status_code == 200, public_resp.text
        public_payload = public_resp.json()
        assert len(public_payload["items"]) == 1
        assert public_payload["items"][0]["id"] == profile_media_id

        resp = await async_client.patch(
            f"/studio/profile/media/{profile_media_id}",
            json={
                "title": "Updated Meditation",
                "position": 1,
                "is_published": False,
                "metadata": {"cta": "listen"},
            },
            headers=auth_header(access_token),
        )
        assert resp.status_code == 200, resp.text
        updated = resp.json()
        assert updated["title"] == "Updated Meditation"
        assert updated["position"] == 1
        assert updated["is_published"] is False
        assert updated["metadata"]["cta"] == "listen"
        resp = await async_client.get(
            f"/community/teachers/{teacher_id}/media"
        )
        assert resp.status_code == 200
        assert resp.json()["items"] == []

        resp = await async_client.get(
            "/studio/profile/media", headers=auth_header(access_token)
        )
        assert resp.status_code == 200
        listing = resp.json()
        returned_ids = {item["id"] for item in listing["items"]}
        assert profile_media_id in returned_ids

        resp = await async_client.delete(
            f"/studio/profile/media/{profile_media_id}",
            headers=auth_header(access_token),
        )
        assert resp.status_code == 204, resp.text

        resp = await async_client.get(
            "/studio/profile/media", headers=auth_header(access_token)
        )
        assert resp.status_code == 200
        final_items = {item["id"] for item in resp.json()["items"]}
        assert profile_media_id not in final_items
    finally:
        await cleanup_user(teacher_id)
