import uuid
from datetime import datetime, timezone

import pytest

from app import db, models
from app.config import settings
from app.services import storage_service as storage_module
from .utils import register_user

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
            "title": "Media Course",
            "slug": slug,
            "description": "Course for media tests",
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


async def _insert_lesson_media(lesson_id: str, storage_path: str) -> None:
    await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=storage_path,
        storage_bucket=storage_module.storage_service.bucket,
        media_id=None,
        position=1,
        duration_seconds=None,
    )


async def test_upload_url_rejects_wav(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)
        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "demo.wav",
                "mime_type": "audio/wav",
                "size_bytes": 1024,
                "media_type": "audio",
                "lesson_id": lesson_id,
            },
        )
        assert resp.status_code == 415, resp.text
    finally:
        await cleanup_user(user_id)


async def test_upload_url_rejects_oversize(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)
        max_bytes = max(settings.media_upload_max_audio_bytes, 5 * 1024 * 1024 * 1024)
        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "demo.mp3",
                "mime_type": "audio/mpeg",
                "size_bytes": max_bytes + 1,
                "media_type": "audio",
                "lesson_id": lesson_id,
            },
        )
        assert resp.status_code == 413, resp.text
    finally:
        await cleanup_user(user_id)


async def test_upload_url_allows_mp3(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

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
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "demo.mp3",
                "mime_type": "audio/mpeg",
                "size_bytes": 2048,
                "media_type": "audio",
                "lesson_id": lesson_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["upload_url"].startswith("https://storage.local/")
        assert "media/audio" in body["object_path"]
        assert body["object_path"].endswith("_demo.mp3")
        expires_at = datetime.fromisoformat(body["expires_at"])
        delta = (expires_at - now).total_seconds()
        assert 110 <= delta <= 130
    finally:
        await cleanup_user(user_id)


async def test_upload_url_allows_mp4(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

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
                expires_in=180,
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "demo.mp4",
                "mime_type": "video/mp4",
                "size_bytes": 4096,
                "media_type": "video",
                "lesson_id": lesson_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["upload_url"].startswith("https://storage.local/")
        assert "media/video" in body["object_path"]
        assert body["object_path"].endswith("_demo.mp4")
    finally:
        await cleanup_user(user_id)


async def test_playback_url_authorized(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        storage_path = (
            f"media/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )
        await _insert_lesson_media(lesson_id, storage_path)

        async def fake_get_presigned_url(
            self,
            path,
            ttl,
            filename=None,
            *,
            download=True,
        ):
            assert download is False
            assert ttl == settings.media_playback_url_ttl_seconds
            return storage_module.PresignedUrl(
                url=f"https://stream.local/{path}",
                expires_in=300,
                headers={},
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "get_presigned_url",
            fake_get_presigned_url,
            raising=True,
        )

        now = datetime.now(timezone.utc)
        resp = await async_client.post(
            "/api/media/playback-url",
            headers=headers,
            json={"object_path": storage_path},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["playback_url"].startswith("https://stream.local/")
        expires_at = datetime.fromisoformat(body["expires_at"])
        delta = (expires_at - now).total_seconds()
        assert 290 <= delta <= 310
    finally:
        await cleanup_user(user_id)


async def test_upload_url_requires_auth(async_client):
    resp = await async_client.post(
        "/api/media/upload-url",
        json={
            "filename": "demo.mp3",
            "mime_type": "audio/mpeg",
            "size_bytes": 1024,
            "media_type": "audio",
            "course_id": str(uuid.uuid4()),
        },
    )
    assert resp.status_code == 401


async def test_playback_url_requires_auth(async_client):
    resp = await async_client.post(
        "/api/media/playback-url",
        json={"object_path": "media/audio/courses/demo.mp3"},
    )
    assert resp.status_code == 401


async def test_playback_url_rejects_non_owner(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    other_headers = None
    other_user_id = None
    try:
        other_headers, other_user_id, _ = await register_user(async_client)
        course_id, lesson_id = await create_lesson(async_client, headers)
        storage_path = (
            f"media/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )
        await _insert_lesson_media(lesson_id, storage_path)

        async def fake_get_presigned_url(
            self,
            path,
            ttl,
            filename=None,
            *,
            download=True,
        ):
            return storage_module.PresignedUrl(
                url=f"https://stream.local/{path}",
                expires_in=300,
                headers={},
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "get_presigned_url",
            fake_get_presigned_url,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/playback-url",
            headers=other_headers,
            json={"object_path": storage_path},
        )
        assert resp.status_code == 403, resp.text
    finally:
        if other_user_id:
            await cleanup_user(other_user_id)
        await cleanup_user(user_id)
