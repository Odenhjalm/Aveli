import asyncio
import logging
import time
import uuid

import pytest

from app import db, models
from app.services import storage_service as storage_module


pytestmark = pytest.mark.anyio("asyncio")

logger = logging.getLogger(__name__)


async def _register_teacher(async_client):
    email = f"concurrent_{uuid.uuid4().hex[:8]}@example.com"
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
    await _promote_to_teacher(user_id)
    return headers, user_id


async def _promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def _cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _create_lesson(async_client, headers):
    slug = f"intent-{uuid.uuid4().hex[:8]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Concurrency Upload Course",
            "slug": slug,
            "description": "Course for concurrent upload-url tests",
            "is_published": False,
            "is_free_intro": False,
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


async def _snapshot_lesson_media(lesson_id: str) -> dict[str, list[tuple]]:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT id::text, position, kind, coalesce(media_asset_id::text, ''), coalesce(storage_bucket, '')
                FROM app.lesson_media
                WHERE lesson_id = %s
                ORDER BY position ASC
                """,
                (lesson_id,),
            )
            lesson_media_rows = await cur.fetchall()

            await cur.execute(
                """
                SELECT id::text, coalesce(original_object_path, ''), coalesce(state, '')
                FROM app.media_assets
                WHERE lesson_id = %s
                ORDER BY created_at ASC
                """,
                (lesson_id,),
            )
            media_asset_rows = await cur.fetchall()

    return {
        "lesson_media": list(lesson_media_rows or []),
        "media_assets": list(media_asset_rows or []),
    }


async def test_concurrent_wav_upload_url_requests_allocate_unique_positions(
    async_client,
    monkeypatch,
):
    """
    Two near-simultaneous upload-url requests for the same lesson must both succeed.

    Under the hood both may compute the same next position initially, but the backend
    must retry on UNIQUE(lesson_id, position) until it can allocate distinct positions.
    """

    # Avoid real network calls to Supabase for this concurrency repro.
    async def fake_create_upload_url(self, path, *, content_type=None, upsert=False, cache_seconds=None):
        return storage_module.PresignedUpload(
            url=f"https://storage.local/object/upload/sign/course-media/{path}?token=test",
            headers={
                "x-upsert": "true" if upsert else "false",
                "content-type": content_type or "application/octet-stream",
                "cache-control": "max-age=60",
            },
            path=path,
            expires_in=3600,
        )

    monkeypatch.setattr(
        "app.services.storage_service.StorageService.create_upload_url",
        fake_create_upload_url,
        raising=True,
    )

    headers, user_id = await _register_teacher(async_client)
    try:
        course_id, lesson_id = await _create_lesson(async_client, headers)

        original_next_position = models.next_lesson_media_position
        barrier_reached = 0
        barrier_event = asyncio.Event()

        async def next_position_with_barrier(target_lesson_id: str) -> int:
            nonlocal barrier_reached
            position = await original_next_position(target_lesson_id)
            barrier_reached += 1
            if barrier_reached >= 2:
                barrier_event.set()
            else:
                await asyncio.wait_for(barrier_event.wait(), timeout=5)
            return position

        monkeypatch.setattr(models, "next_lesson_media_position", next_position_with_barrier)

        payload = {
            "filename": "demo.wav",
            "mime_type": "audio/wav",
            "size_bytes": 1234,
            "media_type": "audio",
            "course_id": course_id,
            "lesson_id": lesson_id,
        }

        async def call_upload_url(label: str):
            started = time.monotonic()
            resp = await async_client.post(
                "/api/media/upload-url",
                headers=headers,
                json=payload,
            )
            return label, started, time.monotonic(), resp

        results = await asyncio.gather(
            call_upload_url("A"),
            call_upload_url("B"),
            return_exceptions=True,
        )

        for result in results:
            if isinstance(result, BaseException):
                raise result
            assert result[3].status_code == 200, result[3].text

        snapshot = await _snapshot_lesson_media(lesson_id)
        logger.info(
            "DB SNAPSHOT lesson_id=%s lesson_media=%s media_assets=%s",
            lesson_id,
            snapshot["lesson_media"],
            snapshot["media_assets"],
        )

        assert len(snapshot["lesson_media"]) == 2, snapshot
        assert {row[1] for row in snapshot["lesson_media"]} == {1, 2}, snapshot

        assert len(snapshot["media_assets"]) == 2, snapshot
        lesson_media_asset_ids = {row[3] for row in snapshot["lesson_media"]}
        media_asset_ids = {row[0] for row in snapshot["media_assets"]}
        assert media_asset_ids == lesson_media_asset_ids, snapshot
    finally:
        if "course_id" in locals():
            await async_client.delete(f"/studio/courses/{course_id}", headers=headers)
        await _cleanup_user(user_id)
