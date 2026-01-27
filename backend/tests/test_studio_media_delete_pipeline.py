import uuid

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


async def create_lesson(async_client, headers):
    slug = f"course-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Delete Pipeline Course",
            "slug": slug,
            "description": "Course for delete pipeline tests",
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


async def test_delete_pipeline_audio_removes_storage_objects(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        source_path = (
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
        )
        derived_path = (
            f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )

        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type="audio",
            purpose="lesson_audio",
            ingest_format="wav",
            original_object_path=source_path,
            original_content_type="audio/wav",
            original_filename="demo.wav",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="ready",
        )
        assert asset
        await media_assets_repo.mark_media_asset_ready(
            media_id=str(asset["id"]),
            streaming_object_path=derived_path,
            streaming_format="mp3",
            duration_seconds=120,
            codec="mp3",
        )

        media_row = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=None,
            storage_bucket=storage_module.storage_service.bucket,
            media_id=None,
            media_asset_id=str(asset["id"]),
            position=1,
            duration_seconds=None,
        )
        assert media_row

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

        resp = await async_client.delete(
            f"/studio/media/{media_row['id']}",
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        assert resp.json() == {"deleted": True}

        assert await media_assets_repo.get_media_asset(str(asset["id"])) is None

        called_paths = {path for _, path in calls}
        assert source_path in called_paths
        assert derived_path in called_paths
    finally:
        await cleanup_user(user_id)


async def test_delete_lesson_cleans_pipeline_assets(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        source_path = (
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
        )
        derived_path = (
            f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )

        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type="audio",
            purpose="lesson_audio",
            ingest_format="wav",
            original_object_path=source_path,
            original_content_type="audio/wav",
            original_filename="demo.wav",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="ready",
        )
        assert asset
        await media_assets_repo.mark_media_asset_ready(
            media_id=str(asset["id"]),
            streaming_object_path=derived_path,
            streaming_format="mp3",
            duration_seconds=120,
            codec="mp3",
        )

        media_row = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=None,
            storage_bucket=storage_module.storage_service.bucket,
            media_id=None,
            media_asset_id=str(asset["id"]),
            position=1,
            duration_seconds=None,
        )
        assert media_row

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

        resp = await async_client.delete(
            f"/studio/lessons/{lesson_id}",
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        assert resp.json() == {"deleted": True}

        assert await media_assets_repo.get_media_asset(str(asset["id"])) is None

        called_paths = {path for _, path in calls}
        assert source_path in called_paths
        assert derived_path in called_paths
    finally:
        await cleanup_user(user_id)
