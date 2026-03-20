import uuid

import pytest

from app import models
from app.repositories import courses as courses_repo

pytestmark = pytest.mark.anyio("asyncio")


async def _register_teacher(async_client) -> tuple[dict[str, str], str]:
    email = f"lesson_contract_{uuid.uuid4().hex[:8]}@example.com"
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
    from app import db

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def _cleanup_user(user_id: str) -> None:
    from app import db

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _create_course_and_lesson(async_client, headers: dict[str, str]) -> tuple[str, str]:
    slug = f"lesson-contract-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Lesson Contract Course",
            "slug": slug,
            "description": "Course for lesson media contract tests",
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


async def _attach_legacy_lesson_media(
    *,
    owner_id: str,
    lesson_id: str,
    storage_bucket: str,
    storage_path: str,
    kind: str,
    content_type: str,
    original_name: str,
    position: int,
) -> str:
    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=storage_path,
        storage_bucket=storage_bucket,
        content_type=content_type,
        byte_size=128,
        checksum=None,
        original_name=original_name,
    )
    assert media_object is not None

    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind=kind,
        storage_path=storage_path,
        storage_bucket=storage_bucket,
        media_id=str(media_object["id"]),
        media_asset_id=None,
        position=position,
        duration_seconds=None,
    )
    assert lesson_media is not None
    return str(lesson_media["id"])


async def test_update_lesson_accepts_canonical_typed_media_refs(async_client):
    headers, user_id = await _register_teacher(async_client)
    try:
        course_id, lesson_id = await _create_course_and_lesson(async_client, headers)
        image_path = f"courses/{course_id}/lessons/{lesson_id}/images/diagram.png"
        audio_path = f"courses/{course_id}/lessons/{lesson_id}/audio/voice.mp3"
        video_path = f"courses/{course_id}/lessons/{lesson_id}/video/clip.mp4"
        document_path = f"courses/{course_id}/lessons/{lesson_id}/docs/material.pdf"

        image_id = await _attach_legacy_lesson_media(
            owner_id=user_id,
            lesson_id=lesson_id,
            storage_bucket="course-media",
            storage_path=image_path,
            kind="image",
            content_type="image/png",
            original_name="diagram.png",
            position=1,
        )
        audio_id = await _attach_legacy_lesson_media(
            owner_id=user_id,
            lesson_id=lesson_id,
            storage_bucket="course-media",
            storage_path=audio_path,
            kind="audio",
            content_type="audio/mpeg",
            original_name="voice.mp3",
            position=2,
        )
        video_id = await _attach_legacy_lesson_media(
            owner_id=user_id,
            lesson_id=lesson_id,
            storage_bucket="course-media",
            storage_path=video_path,
            kind="video",
            content_type="video/mp4",
            original_name="clip.mp4",
            position=3,
        )
        document_id = await _attach_legacy_lesson_media(
            owner_id=user_id,
            lesson_id=lesson_id,
            storage_bucket="course-media",
            storage_path=document_path,
            kind="pdf",
            content_type="application/pdf",
            original_name="material.pdf",
            position=4,
        )

        update_resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            headers=headers,
            json={
                "content_markdown": (
                    f"!image({image_id})\n\n"
                    f"!audio({audio_id})\n\n"
                    f"!video({video_id})\n\n"
                    f"!document({document_id})"
                )
            },
        )
        assert update_resp.status_code == 200, update_resp.text

        stored = await courses_repo.get_lesson(lesson_id)
        assert stored is not None
        content = stored["content_markdown"]
        assert content == (
            f"!image({image_id})\n\n"
            f"!audio({audio_id})\n\n"
            f"!video({video_id})\n\n"
            f"!document({document_id})"
        )
    finally:
        await _cleanup_user(user_id)


async def test_update_lesson_rejects_unresolved_raw_media_refs(async_client):
    headers, user_id = await _register_teacher(async_client)
    try:
        _course_id, lesson_id = await _create_course_and_lesson(async_client, headers)

        update_resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            headers=headers,
            json={
                "content_markdown": "Intro\n\n![](https://cdn.test/lesson-image.png)\n"
            },
        )
        assert update_resp.status_code == 422, update_resp.text
        assert "could not normalize" in str(update_resp.json()["detail"])
    finally:
        await _cleanup_user(user_id)


async def test_update_lesson_rewrites_resolvable_legacy_document_links(async_client):
    headers, user_id = await _register_teacher(async_client)
    try:
        course_id, lesson_id = await _create_course_and_lesson(async_client, headers)
        document_path = f"courses/{course_id}/lessons/{lesson_id}/docs/material.pdf"
        document_id = await _attach_legacy_lesson_media(
            owner_id=user_id,
            lesson_id=lesson_id,
            storage_bucket="course-media",
            storage_path=document_path,
            kind="pdf",
            content_type="application/pdf",
            original_name="material.pdf",
            position=1,
        )

        update_resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            headers=headers,
            json={
                "content_markdown": f"[📄 material.pdf](/studio/media/{document_id})"
            },
        )
        assert update_resp.status_code == 200, update_resp.text

        stored = await courses_repo.get_lesson(lesson_id)
        assert stored is not None
        assert stored["content_markdown"] == f"!document({document_id})"
    finally:
        await _cleanup_user(user_id)


async def test_update_lesson_rejects_storage_path_media_refs(async_client):
    headers, user_id = await _register_teacher(async_client)
    try:
        course_id, lesson_id = await _create_course_and_lesson(async_client, headers)

        update_resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            headers=headers,
            json={
                "content_markdown": (
                    f"Intro\n\n[course pdf](courses/{course_id}/lessons/{lesson_id}/docs/material.pdf)"
                )
            },
        )
        assert update_resp.status_code == 422, update_resp.text
        assert "could not normalize" in str(update_resp.json()["detail"])
    finally:
        await _cleanup_user(user_id)
