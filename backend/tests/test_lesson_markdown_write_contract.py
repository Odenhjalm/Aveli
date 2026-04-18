import uuid

import pytest

from app.repositories import media_assets as media_assets_repo
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
    profile_resp = await async_client.get("/profiles/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]
    await _promote_to_teacher(user_id)
    return headers, user_id


async def _promote_to_teacher(user_id: str) -> None:
    from app import db

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def _cleanup_user(user_id: str) -> None:
    from app import db

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _read_lesson_content_etag(
    async_client,
    *,
    headers: dict[str, str],
    lesson_id: str,
) -> str:
    content_resp = await async_client.get(
        f"/studio/lessons/{lesson_id}/content",
        headers=headers,
    )
    assert content_resp.status_code == 200, content_resp.text
    assert set(content_resp.json()) == {"lesson_id", "content_markdown", "media"}
    etag = content_resp.headers.get("etag")
    assert etag
    return etag


async def _create_course_and_lesson(async_client, headers: dict[str, str]) -> tuple[str, str]:
    slug = f"lesson-contract-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Lesson Contract Course",
            "slug": slug,
            "course_group_id": str(uuid.uuid4()),
            "group_position": 0,
            "price_amount_cents": None,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
    )
    assert course_resp.status_code == 200, course_resp.text
    course_id = str(course_resp.json()["id"])

    lesson_resp = await async_client.post(
        f"/studio/courses/{course_id}/lessons",
        headers=headers,
        json={
            "lesson_title": "Lesson",
            "position": 1,
        },
    )
    assert lesson_resp.status_code == 200, lesson_resp.text
    lesson_id = str(lesson_resp.json()["id"])
    content_resp = await async_client.patch(
        f"/studio/lessons/{lesson_id}/content",
        headers={
            **headers,
            "If-Match": await _read_lesson_content_etag(
                async_client,
                headers=headers,
                lesson_id=lesson_id,
            ),
        },
        json={"content_markdown": "# Lesson"},
    )
    assert content_resp.status_code == 200, content_resp.text
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
    del owner_id, storage_bucket, original_name, position

    media_type = "document" if kind == "pdf" else kind
    media_asset = await media_assets_repo.create_media_asset(
        media_asset_id=str(uuid.uuid4()),
        media_type=media_type,
        purpose="lesson_media",
        original_object_path=storage_path,
        ingest_format=content_type,
        state="pending_upload",
    )
    assert media_asset is not None

    lesson_media = await courses_repo.create_lesson_media(
        lesson_id=lesson_id,
        media_asset_id=str(media_asset["id"]),
    )
    assert lesson_media is not None
    return str(lesson_media["lesson_media_id"])


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
            f"/studio/lessons/{lesson_id}/content",
            headers={
                **headers,
                "If-Match": await _read_lesson_content_etag(
                    async_client,
                    headers=headers,
                    lesson_id=lesson_id,
                ),
            },
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
            f"/studio/lessons/{lesson_id}/content",
            headers={
                **headers,
                "If-Match": await _read_lesson_content_etag(
                    async_client,
                    headers=headers,
                    lesson_id=lesson_id,
                ),
            },
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
            f"/studio/lessons/{lesson_id}/content",
            headers={
                **headers,
                "If-Match": await _read_lesson_content_etag(
                    async_client,
                    headers=headers,
                    lesson_id=lesson_id,
                ),
            },
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
            f"/studio/lessons/{lesson_id}/content",
            headers={
                **headers,
                "If-Match": await _read_lesson_content_etag(
                    async_client,
                    headers=headers,
                    lesson_id=lesson_id,
                ),
            },
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
