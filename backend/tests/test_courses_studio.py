import uuid

import pytest

from app import db
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import courses_service


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
    access_token = tokens["access_token"]

    profile_resp = await client.get("/profiles/me", headers=auth_header(access_token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    return access_token, tokens["refresh_token"], user_id


async def promote_to_teacher(user_id: str):
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


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def read_lesson_content_etag(
    async_client,
    *,
    lesson_id: str,
    token: str,
) -> str:
    response = await async_client.get(
        f"/studio/lessons/{lesson_id}/content",
        headers=auth_header(token),
    )
    assert response.status_code == 200, response.text
    assert set(response.json()) == {"lesson_id", "content_markdown", "media"}
    etag = response.headers.get("etag")
    assert etag
    return etag


async def test_studio_course_and_lesson_endpoints_follow_canonical_shape(async_client):
    teacher_email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"student_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)
    student_token, _, student_id = await register_user(
        async_client,
        student_email,
        password,
        "Student",
    )

    course_id = None
    lesson_id = None
    cover_media_id = None

    try:
        student_courses = await async_client.get(
            "/studio/courses",
            headers=auth_header(student_token),
        )
        assert student_courses.status_code == 403, student_courses.text

        slug = f"course-{uuid.uuid4().hex[:8]}"
        create_course = await async_client.post(
            "/studio/courses",
            headers=auth_header(teacher_token),
            json={
                "title": "Intro to Aveli",
                "slug": slug,
                "course_group_id": str(uuid.uuid4()),
                "group_position": 0,
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
            },
        )
        assert create_course.status_code == 200, create_course.text
        course = create_course.json()
        course_id = str(course["id"])
        assert course["slug"] == slug
        assert course["group_position"] == 0
        assert course["drip_enabled"] is False
        assert course["cover_media_id"] is None

        teacher_courses = await async_client.get(
            "/studio/courses",
            headers=auth_header(teacher_token),
        )
        assert teacher_courses.status_code == 200, teacher_courses.text
        assert any(str(item["id"]) == course_id for item in teacher_courses.json()["items"])

        student_patch = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(student_token),
            json={"title": "Hacked"},
        )
        assert student_patch.status_code == 403, student_patch.text

        update_course = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(teacher_token),
            json={"title": "Intro to Aveli (Updated)"},
        )
        assert update_course.status_code == 200, update_course.text
        assert update_course.json()["title"] == "Intro to Aveli (Updated)"

        cover_media_id = str(uuid.uuid4())
        await media_assets_repo.create_media_asset(
            media_asset_id=cover_media_id,
            media_type="image",
            purpose="course_cover",
            original_object_path=(
                f"media/source/cover/courses/{course_id}/{cover_media_id}.png"
            ),
            ingest_format="png",
            state="pending_upload",
        )
        await media_assets_repo.mark_media_asset_uploaded(media_id=cover_media_id)
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=cover_media_id,
            playback_object_path=(
                f"media/derived/cover/courses/{course_id}/{cover_media_id}.jpg"
            ),
        )

        update_cover = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(teacher_token),
            json={"cover_media_id": cover_media_id},
        )
        assert update_cover.status_code == 200, update_cover.text
        update_cover_body = update_cover.json()
        assert update_cover_body["cover_media_id"] == cover_media_id
        assert "cover_url" not in update_cover_body
        assert update_cover_body["cover"]["media_id"] == cover_media_id
        assert update_cover_body["cover"]["state"] == "ready"
        assert update_cover_body["cover"]["resolved_url"].endswith(
            f"/public-media/media/derived/cover/courses/{course_id}/{cover_media_id}.jpg"
        )

        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "SELECT cover_media_id FROM app.courses WHERE id = %s",
                    (course_id,),
                )
                persisted_cover = await cur.fetchone()
        assert str(persisted_cover[0]) == cover_media_id

        student_create_lesson = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(student_token),
            json={
                "lesson_title": "Lesson 1",
                "position": 1,
            },
        )
        assert student_create_lesson.status_code == 403, student_create_lesson.text

        create_lesson = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
            json={
                "lesson_title": "Lesson 1",
                "position": 1,
            },
        )
        assert create_lesson.status_code == 200, create_lesson.text
        lesson_id = str(create_lesson.json()["id"])
        assert create_lesson.json()["lesson_title"] == "Lesson 1"
        assert "content_markdown" not in create_lesson.json()

        update_content = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={
                **auth_header(teacher_token),
                "If-Match": await read_lesson_content_etag(
                    async_client,
                    lesson_id=lesson_id,
                    token=teacher_token,
                ),
            },
            json={"content_markdown": "# Hello"},
        )
        assert update_content.status_code == 200, update_content.text
        assert update_content.json()["lesson_id"] == lesson_id
        assert update_content.json()["content_markdown"] == "# Hello"

        list_lessons = await async_client.get(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
        )
        assert list_lessons.status_code == 200, list_lessons.text
        listed_lesson = next(
            item for item in list_lessons.json()["items"] if str(item["id"]) == lesson_id
        )
        assert "content_markdown" not in listed_lesson

        update_lesson = await async_client.patch(
            f"/studio/lessons/{lesson_id}/structure",
            headers=auth_header(teacher_token),
            json={
                "lesson_title": "Lesson 1 Updated",
                "position": 2,
            },
        )
        assert update_lesson.status_code == 200, update_lesson.text
        assert update_lesson.json()["lesson_title"] == "Lesson 1 Updated"
        assert update_lesson.json()["position"] == 2
        assert "content_markdown" not in update_lesson.json()

        mixed_create = await async_client.post(
            "/studio/lessons",
            headers=auth_header(teacher_token),
            json={
                "course_id": course_id,
                "lesson_title": "Mixed",
                "content_markdown": "Nope",
                "position": 2,
            },
        )
        assert mixed_create.status_code == 404, mixed_create.text

        mixed_update = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            headers=auth_header(teacher_token),
            json={"lesson_title": "Mixed", "content_markdown": "Nope"},
        )
        assert mixed_update.status_code == 405, mixed_update.text
    finally:
        if lesson_id:
            await async_client.delete(
                f"/studio/lessons/{lesson_id}",
                headers=auth_header(teacher_token),
            )
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        if cover_media_id:
            async with db.pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        "UPDATE app.courses SET cover_media_id = NULL WHERE cover_media_id = %s::uuid",
                        (cover_media_id,),
                    )
                    await cur.execute(
                        "DELETE FROM app.media_assets WHERE id = %s::uuid",
                        (cover_media_id,),
                    )
                    await conn.commit()
        await cleanup_user(student_id)
        await cleanup_user(teacher_id)


async def test_studio_lesson_delete_removes_content_and_placements_only(
    async_client,
    monkeypatch,
):
    teacher_email = f"delete_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    course_id = None
    lesson_id = None
    media_asset_id = None
    lifecycle_calls: list[dict[str, object]] = []

    async def fake_lifecycle_request(**kwargs):
        lifecycle_calls.append(dict(kwargs))
        return len(list(kwargs["media_asset_ids"]))

    async def fail_delete_media_asset(*args, **kwargs):
        raise AssertionError("lesson delete must not delete media_assets")

    monkeypatch.setattr(
        courses_service.media_cleanup,
        "request_lifecycle_evaluation",
        fake_lifecycle_request,
        raising=True,
    )
    monkeypatch.setattr(
        media_assets_repo,
        "delete_media_asset",
        fail_delete_media_asset,
        raising=False,
    )

    try:
        create_course = await async_client.post(
            "/studio/courses",
            headers=auth_header(teacher_token),
            json={
                "title": "Delete media boundary",
                "slug": f"delete-media-{uuid.uuid4().hex[:8]}",
                "course_group_id": str(uuid.uuid4()),
                "group_position": 0,
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
            },
        )
        assert create_course.status_code == 200, create_course.text
        course_id = str(create_course.json()["id"])

        create_lesson = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
            json={"lesson_title": "Media lesson", "position": 1},
        )
        assert create_lesson.status_code == 200, create_lesson.text
        lesson_id = str(create_lesson.json()["id"])

        update_content = await async_client.patch(
            f"/studio/lessons/{lesson_id}/content",
            headers={
                **auth_header(teacher_token),
                "If-Match": await read_lesson_content_etag(
                    async_client,
                    lesson_id=lesson_id,
                    token=teacher_token,
                ),
            },
            json={"content_markdown": "Lesson body"},
        )
        assert update_content.status_code == 200, update_content.text

        media_asset_id = str(uuid.uuid4())
        await media_assets_repo.create_media_asset(
            media_asset_id=media_asset_id,
            media_type="image",
            purpose="lesson_media",
            original_object_path=f"lessons/{lesson_id}/images/{media_asset_id}.png",
            ingest_format="png",
            state="pending_upload",
        )
        placement = await courses_repo.create_lesson_media(
            lesson_id=lesson_id,
            media_asset_id=media_asset_id,
        )

        delete_lesson = await async_client.delete(
            f"/studio/lessons/{lesson_id}",
            headers=auth_header(teacher_token),
        )
        assert delete_lesson.status_code == 200, delete_lesson.text
        assert delete_lesson.json() == {"deleted": True}

        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    SELECT
                      EXISTS (
                        SELECT 1 FROM app.lesson_contents WHERE lesson_id = %s::uuid
                      ),
                      EXISTS (
                        SELECT 1 FROM app.lesson_media WHERE lesson_id = %s::uuid
                      ),
                      EXISTS (
                        SELECT 1 FROM app.lessons WHERE id = %s::uuid
                      ),
                      EXISTS (
                        SELECT 1 FROM app.media_assets WHERE id = %s::uuid
                      )
                    """,
                    (lesson_id, lesson_id, lesson_id, media_asset_id),
                )
                content_exists, placement_exists, lesson_exists, asset_exists = (
                    await cur.fetchone()
                )

        assert content_exists is False
        assert placement_exists is False
        assert lesson_exists is False
        assert asset_exists is True
        assert lifecycle_calls == [
            {
                "media_asset_ids": [media_asset_id],
                "trigger_source": "lesson_delete",
                "subject_type": "lesson",
                "subject_id": lesson_id,
            }
        ]
        assert str(placement["media_asset_id"]) == media_asset_id
        lesson_id = None
    finally:
        if lesson_id:
            await async_client.delete(
                f"/studio/lessons/{lesson_id}",
                headers=auth_header(teacher_token),
            )
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        if media_asset_id:
            async with db.pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        "DELETE FROM app.lesson_media WHERE media_asset_id = %s::uuid",
                        (media_asset_id,),
                    )
                    await cur.execute(
                        "DELETE FROM app.media_assets WHERE id = %s::uuid",
                        (media_asset_id,),
                    )
                    await conn.commit()
        await cleanup_user(teacher_id)
