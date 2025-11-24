import uuid

import pytest

from app import db
from app.services import storage_service as storage_module

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
    profile_resp = await async_client.get("/auth/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]
    await promote_to_teacher(user_id)
    return headers, user_id


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

    module_resp = await async_client.post(
        "/studio/modules",
        headers=headers,
        json={"course_id": course_id, "title": "Module", "position": 1},
    )
    assert module_resp.status_code == 200, module_resp.text
    module_id = str(module_resp.json()["id"])

    lesson_resp = await async_client.post(
        "/studio/lessons",
        headers=headers,
        json={
            "module_id": module_id,
            "title": "Lesson",
            "content_markdown": "# Lesson",
            "position": 1,
            "is_intro": False,
        },
    )
    assert lesson_resp.status_code == 200, lesson_resp.text
    lesson_id = str(lesson_resp.json()["id"])
    return course_id, lesson_id


@pytest.mark.anyio("asyncio")
async def test_direct_lesson_media_upload_flow(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={
                    "x-upsert": "true" if upsert else "false",
                    "content-type": content_type,
                    "cache-control": f"max-age={cache_seconds}",
                },
                path=path,
                expires_in=3600,
            )

        monkeypatch.setattr(
            "app.services.storage_service.StorageService.create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        presign_resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media/presign",
            headers=headers,
            json={
                "filename": "demo.mp4",
                "content_type": "video/mp4",
                "media_type": "video",
            },
        )
        assert presign_resp.status_code == 200, presign_resp.text
        presign_data = presign_resp.json()
        assert presign_data["method"] == "PUT"
        assert presign_data["storage_bucket"] == "course-media"
        assert presign_data["storage_path"].startswith("course-media/")

        complete_resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media/complete",
            headers=headers,
            json={
                "storage_path": presign_data["storage_path"],
                "storage_bucket": presign_data["storage_bucket"],
                "content_type": "video/mp4",
                "byte_size": 1024,
                "original_name": "demo.mp4",
            },
        )
        assert complete_resp.status_code == 200, complete_resp.text
        body = complete_resp.json()
        assert body["storage_path"] == presign_data["storage_path"]
        assert body["storage_bucket"] == presign_data["storage_bucket"]
        assert body["content_type"] == "video/mp4"

        # Lesson media list should include the new row.
        list_resp = await async_client.get(
            f"/studio/lessons/{lesson_id}/media", headers=headers
        )
        assert list_resp.status_code == 200
        items = list_resp.json()["items"]
        assert any(item["id"] == body["id"] for item in items)
    finally:
        await cleanup_user(user_id)


@pytest.mark.anyio("asyncio")
async def test_complete_rejects_bucket_mismatch(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        # Short-circuit storage presign
        async def fake_create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"x-upsert": "true", "content-type": content_type, "cache-control": "max-age=60"},
                path=path,
                expires_in=60,
            )

        monkeypatch.setattr(
            "app.services.storage_service.StorageService.create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        presign_resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media/presign",
            headers=headers,
            json={"filename": "demo.mp4", "content_type": "video/mp4"},
        )
        assert presign_resp.status_code == 200, presign_resp.text
        presign_data = presign_resp.json()

        bad_resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media/complete",
            headers=headers,
            json={
                "storage_path": presign_data["storage_path"],
                "storage_bucket": "public-media",
                "content_type": "video/mp4",
                "byte_size": 100,
            },
        )
        assert bad_resp.status_code == 400
        assert "storage_bucket" in bad_resp.text
    finally:
        await cleanup_user(user_id)
