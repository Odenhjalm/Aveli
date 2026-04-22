import uuid

import pytest

from app import db, repositories
from app.repositories import media_assets as media_assets_repo
from ._custom_drip_test_support import ensure_custom_drip_schema


pytestmark = pytest.mark.anyio("asyncio")


@pytest.fixture(autouse=True)
async def _ensure_custom_drip_schema(async_client):
    del async_client
    await ensure_custom_drip_schema()


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _register_teacher(async_client) -> tuple[dict[str, str], str]:
    email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    access_token = tokens["access_token"]

    profile_resp = await async_client.get("/profiles/me", headers=_auth_header(access_token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])

    create_profile_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=_auth_header(access_token),
        json={"display_name": "Teacher", "bio": None},
    )
    assert create_profile_resp.status_code == 200, create_profile_resp.text

    complete_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=_auth_header(access_token),
    )
    assert complete_resp.status_code == 200, complete_resp.text

    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )

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

    return _auth_header(access_token), user_id


async def _cleanup_course_families(teacher_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                DELETE FROM app.lessons AS l
                 USING app.courses AS c
                 JOIN app.course_families AS cf
                   ON cf.id = c.course_group_id
                WHERE l.course_id = c.id
                  AND cf.teacher_id = %s::uuid
                """,
                (teacher_id,),
            )
            await cur.execute(
                """
                DELETE FROM app.courses AS c
                 USING app.course_families AS cf
                WHERE c.course_group_id = cf.id
                  AND cf.teacher_id = %s::uuid
                """,
                (teacher_id,),
            )
            await cur.execute(
                "DELETE FROM app.course_families WHERE teacher_id = %s::uuid",
                (teacher_id,),
            )
            await conn.commit()


async def _cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _create_course_and_lesson(async_client, headers: dict[str, str]) -> tuple[str, str]:
    family_resp = await async_client.post(
        "/studio/course-families",
        headers=headers,
        json={"name": f"Metadata Family {uuid.uuid4().hex[:6]}"},
    )
    assert family_resp.status_code == 201, family_resp.text
    family_id = family_resp.json()["id"]

    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Metadata Course",
            "slug": f"metadata-course-{uuid.uuid4().hex[:8]}",
            "course_group_id": family_id,
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
        json={"lesson_title": "Metadata Lesson", "position": 1},
    )
    assert lesson_resp.status_code == 200, lesson_resp.text
    lesson_id = str(lesson_resp.json()["id"])
    return course_id, lesson_id


async def test_canonical_upload_session_routes_persist_media_ingest_metadata(
    async_client,
) -> None:
    headers, user_id = await _register_teacher(async_client)

    try:
        course_id, lesson_id = await _create_course_and_lesson(async_client, headers)

        lesson_upload = await async_client.post(
            f"/api/lessons/{lesson_id}/media-assets/upload-url",
            headers=headers,
            json={
                "media_type": "audio",
                "filename": "Intro Track #1.wav",
                "mime_type": "audio/wav",
                "size_bytes": 128,
            },
        )
        assert lesson_upload.status_code == 200, lesson_upload.text
        lesson_asset = await media_assets_repo.get_media_asset(
            lesson_upload.json()["media_asset_id"]
        )
        assert lesson_asset is not None
        assert lesson_asset["original_filename"] == "Intro Track #1.wav"
        assert lesson_asset["lesson_id"] == lesson_id
        assert lesson_asset["course_id"] == course_id
        assert lesson_asset["owner_user_id"] is None

        cover_upload = await async_client.post(
            f"/api/courses/{course_id}/cover-media-assets/upload-url",
            headers=headers,
            json={
                "filename": "Course Cover ?.png",
                "mime_type": "image/png",
                "size_bytes": 128,
            },
        )
        assert cover_upload.status_code == 200, cover_upload.text
        cover_asset = await media_assets_repo.get_media_asset(
            cover_upload.json()["media_asset_id"]
        )
        assert cover_asset is not None
        assert cover_asset["original_filename"] == "Course Cover ?.png"
        assert cover_asset["course_id"] == course_id
        assert cover_asset["lesson_id"] is None
        assert cover_asset["owner_user_id"] is None

        home_upload = await async_client.post(
            "/api/home-player/media-assets/upload-url",
            headers=headers,
            json={
                "filename": "Focus Mix?.m4a",
                "mime_type": "audio/mp4",
                "size_bytes": 128,
            },
        )
        assert home_upload.status_code == 200, home_upload.text
        home_asset = await media_assets_repo.get_media_asset(
            home_upload.json()["media_asset_id"]
        )
        assert home_asset is not None
        assert home_asset["original_filename"] == "Focus Mix?.m4a"
        assert home_asset["owner_user_id"] == user_id
        assert home_asset["lesson_id"] is None
        assert home_asset["course_id"] is None

        avatar_upload = await async_client.post(
            "/api/media/profile-avatar/init",
            headers=headers,
            json={
                "filename": "Åvatar #1.png",
                "mime_type": "image/png",
                "size_bytes": 128,
            },
        )
        assert avatar_upload.status_code == 200, avatar_upload.text
        avatar_asset = await media_assets_repo.get_media_asset(
            avatar_upload.json()["media_asset_id"]
        )
        assert avatar_asset is not None
        assert avatar_asset["original_filename"] == "Åvatar #1.png"
        assert avatar_asset["owner_user_id"] == user_id
        assert avatar_asset["lesson_id"] is None
        assert avatar_asset["course_id"] is None
    finally:
        await _cleanup_course_families(user_id)
        await _cleanup_user(user_id)
