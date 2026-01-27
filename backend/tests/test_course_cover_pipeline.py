import uuid
from datetime import datetime, timezone

import pytest

from app import db, models
from app.repositories import media_assets as media_assets_repo
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


async def create_course(async_client, headers):
    slug = f"course-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Cover Course",
            "slug": slug,
            "description": "Course for cover tests",
            "is_published": False,
        },
    )
    assert course_resp.status_code == 200, course_resp.text
    return str(course_resp.json()["id"])


async def create_lesson(async_client, headers, course_id: str):
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
    return str(lesson_resp.json()["id"])


async def test_cover_upload_url_allows_image(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        now = datetime.now(timezone.utc)
        resp = await async_client.post(
            "/api/media/cover-upload-url",
            headers=headers,
            json={
                "filename": "cover.jpg",
                "mime_type": "image/jpeg",
                "size_bytes": 2048,
                "course_id": course_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["upload_url"].startswith("https://storage.local/")
        assert "media/source/cover/courses" in body["object_path"]
        assert body["object_path"].endswith("_cover.jpg")
        expires_at = datetime.fromisoformat(body["expires_at"])
        delta = (expires_at - now).total_seconds()
        assert 110 <= delta <= 130

        asset = await media_assets_repo.get_media_asset(body["media_id"])
        assert asset is not None
        assert asset["media_type"] == "image"
        assert asset["purpose"] == "course_cover"
        assert asset["state"] == "uploaded"
    finally:
        await cleanup_user(user_id)


async def test_cover_upload_url_rejects_non_image(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        resp = await async_client.post(
            "/api/media/cover-upload-url",
            headers=headers,
            json={
                "filename": "cover.wav",
                "mime_type": "audio/wav",
                "size_bytes": 1024,
                "course_id": course_id,
            },
        )
        assert resp.status_code == 415, resp.text
    finally:
        await cleanup_user(user_id)


async def test_cover_from_lesson_media_creates_asset(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        lesson_id = await create_lesson(async_client, headers, course_id)

        media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="image",
            storage_path="course-media/demo/cover.png",
            storage_bucket=storage_module.storage_service.bucket,
            media_id=None,
            media_asset_id=None,
            position=1,
            duration_seconds=None,
        )
        assert media

        resp = await async_client.post(
            "/api/media/cover-from-media",
            headers=headers,
            json={
                "course_id": course_id,
                "lesson_media_id": str(media["id"]),
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        asset = await media_assets_repo.get_media_asset(body["media_id"])
        assert asset is not None
        assert asset["original_object_path"] == "course-media/demo/cover.png"
        assert asset["purpose"] == "course_cover"
    finally:
        await cleanup_user(user_id)


async def test_cover_clear_deletes_assets(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)

        source_path = f"media/source/cover/courses/{course_id}/demo.jpg"
        derived_path = f"media/derived/cover/courses/{course_id}/demo.jpg"

        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="jpeg",
            original_object_path=source_path,
            original_content_type="image/jpeg",
            original_filename="demo.jpg",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
        )
        assert asset

        await media_assets_repo.mark_course_cover_ready(
            media_id=str(asset["id"]),
            streaming_object_path=derived_path,
            streaming_format="jpg",
            streaming_storage_bucket=storage_module.public_storage_service.bucket,
            public_url=f"https://public.local/{derived_path}",
            codec="jpeg",
        )

        calls: list[tuple[str, str]] = []

        async def fake_delete_object(self, path):
            calls.append((self.bucket, path))
            return True

        monkeypatch.setattr(
            storage_module.StorageService,
            "delete_object",
            fake_delete_object,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/cover-clear",
            headers=headers,
            json={"course_id": course_id},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json() == {"ok": True}

        meta = await async_client.get(
            f"/studio/courses/{course_id}",
            headers=headers,
        )
        assert meta.status_code == 200, meta.text
        meta_json = meta.json()
        assert meta_json.get("cover_media_id") is None
        assert meta_json.get("cover_url") is None

        assert await media_assets_repo.get_media_asset(str(asset["id"])) is None

        assert (storage_module.storage_service.bucket, source_path) in calls
        assert (storage_module.public_storage_service.bucket, derived_path) in calls
    finally:
        await cleanup_user(user_id)
