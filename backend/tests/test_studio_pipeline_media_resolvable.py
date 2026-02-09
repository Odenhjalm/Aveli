import uuid

import pytest

from app import db, models
from app.repositories import media_assets as media_assets_repo
from app.repositories import storage_objects as storage_objects_repo
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
            "title": "Pipeline Media Course",
            "slug": slug,
            "description": "Course for pipeline media resolvable tests",
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


async def test_pipeline_audio_becomes_editor_resolvable_after_processing(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        source_path = f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
        derived_ok = f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        derived_missing = (
            f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/missing.mp3"
        )

        asset_ok = await media_assets_repo.create_media_asset(
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
        assert asset_ok
        await media_assets_repo.mark_media_asset_ready(
            media_id=str(asset_ok["id"]),
            streaming_object_path=derived_ok,
            streaming_format="mp3",
            duration_seconds=120,
            codec="mp3",
        )

        lesson_media_ok = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=None,
            storage_bucket=storage_module.storage_service.bucket,
            media_id=None,
            media_asset_id=str(asset_ok["id"]),
            position=1,
            duration_seconds=None,
        )
        assert lesson_media_ok

        asset_missing = await media_assets_repo.create_media_asset(
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
        assert asset_missing
        await media_assets_repo.mark_media_asset_ready(
            media_id=str(asset_missing["id"]),
            streaming_object_path=derived_missing,
            streaming_format="mp3",
            duration_seconds=120,
            codec="mp3",
        )

        lesson_media_missing = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=None,
            storage_bucket=storage_module.storage_service.bucket,
            media_id=None,
            media_asset_id=str(asset_missing["id"]),
            position=2,
            duration_seconds=None,
        )
        assert lesson_media_missing

        async def fake_fetch_storage_object_existence(pairs):
            bucket = storage_module.storage_service.bucket
            existence = {(bucket, derived_ok): True}
            # Missing pairs default to False via `.get(..., False)`.
            return existence, True

        monkeypatch.setattr(
            storage_objects_repo,
            "fetch_storage_object_existence",
            fake_fetch_storage_object_existence,
            raising=True,
        )

        async def fake_get_presigned_url(
            self,
            path,
            ttl,
            filename=None,
            *,
            download=True,
        ):
            assert download is False
            return storage_module.PresignedUrl(
                url=f"https://stream.local/{self.bucket}/{path}",
                expires_in=300,
                headers={},
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "get_presigned_url",
            fake_get_presigned_url,
            raising=True,
        )

        resp = await async_client.get(
            f"/studio/lessons/{lesson_id}/media",
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        items = resp.json()["items"]

        ok_item = next(it for it in items if it["id"] == str(lesson_media_ok["id"]))
        assert ok_item["media_state"] == "ready"
        assert ok_item["resolvable_for_editor"] is True
        assert ok_item.get("playback_url", "").startswith("https://stream.local/")

        missing_item = next(
            it for it in items if it["id"] == str(lesson_media_missing["id"])
        )
        assert missing_item["media_state"] == "ready"
        assert missing_item["resolvable_for_editor"] is False
        assert missing_item.get("playback_url") in {None, ""}
    finally:
        await cleanup_user(user_id)

