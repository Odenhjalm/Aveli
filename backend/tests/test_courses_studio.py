import uuid

import pytest

from app import db, repositories
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import courses_service
from ._custom_drip_test_support import ensure_custom_drip_schema


pytestmark = pytest.mark.anyio("asyncio")


@pytest.fixture(autouse=True)
async def _ensure_custom_drip_schema(async_client):
    del async_client
    await ensure_custom_drip_schema()


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def lesson_document(text: str) -> dict:
    return {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "paragraph",
                "children": [{"text": text}],
            }
        ],
    }


async def register_user(client, email: str, password: str, display_name: str):
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    access_token = tokens["access_token"]

    profile_resp = await client.get("/profiles/me", headers=auth_header(access_token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    create_profile_resp = await client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(access_token),
        json={"display_name": display_name, "bio": None},
    )
    assert create_profile_resp.status_code == 200, create_profile_resp.text
    complete_resp = await client.post(
        "/auth/onboarding/complete",
        headers=auth_header(access_token),
    )
    assert complete_resp.status_code == 200, complete_resp.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )
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


async def cleanup_course_families(teacher_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.course_families WHERE teacher_id = %s::uuid",
                (teacher_id,),
            )
            await conn.commit()


async def create_course_family(async_client, *, token: str, name: str) -> dict:
    response = await async_client.post(
        "/studio/course-families",
        headers=auth_header(token),
        json={"name": name},
    )
    assert response.status_code == 201, response.text
    return response.json()


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
    assert set(response.json()) == {"lesson_id", "content_document", "media"}
    etag = response.headers.get("etag")
    assert etag
    return etag


async def read_course_family_rows(course_group_id: str) -> list[tuple[str, int]]:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT id::text, group_position
                  FROM app.courses
                 WHERE course_group_id = %s::uuid
                 ORDER BY group_position ASC, id ASC
                """,
                (course_group_id,),
            )
            rows = await cur.fetchall()
    return [(str(row[0]), int(row[1])) for row in rows]


def assert_studio_drip_authoring(
    course: dict,
    *,
    mode: str,
    schedule_locked: bool = False,
    legacy_interval: int | None = None,
) -> None:
    assert "drip_enabled" not in course
    assert "drip_interval_days" not in course
    drip_authoring = course["drip_authoring"]
    assert drip_authoring["mode"] == mode
    assert drip_authoring["schedule_locked"] is schedule_locked
    expected_lock_reason = "first_enrollment_exists" if schedule_locked else None
    assert drip_authoring["lock_reason"] == expected_lock_reason
    if legacy_interval is None:
        assert drip_authoring["legacy_uniform"] is None
    else:
        assert drip_authoring["legacy_uniform"] == {
            "drip_interval_days": legacy_interval
        }


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

        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Intro Family",
        )
        slug = f"course-{uuid.uuid4().hex[:8]}"
        create_course = await async_client.post(
            "/studio/courses",
            headers=auth_header(teacher_token),
            json={
                "title": "Intro to Aveli",
                "slug": slug,
                "course_group_id": family["id"],
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
        assert course["cover_media_id"] is None
        assert_studio_drip_authoring(
            course,
            mode="no_drip_immediate_access",
        )

        teacher_courses = await async_client.get(
            "/studio/courses",
            headers=auth_header(teacher_token),
        )
        assert teacher_courses.status_code == 200, teacher_courses.text
        listed_course = next(
            item
            for item in teacher_courses.json()["items"]
            if str(item["id"]) == course_id
        )
        assert_studio_drip_authoring(
            listed_course,
            mode="no_drip_immediate_access",
        )

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
        updated_course = update_course.json()
        assert updated_course["title"] == "Intro to Aveli (Updated)"
        assert_studio_drip_authoring(
            updated_course,
            mode="no_drip_immediate_access",
        )

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
        await media_assets_repo._call_canonical_worker_transition(
            cover_media_id,
            target_state="processing",
        )
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=cover_media_id,
            playback_object_path=(
                f"media/derived/cover/courses/{course_id}/{cover_media_id}.jpg"
            ),
            playback_format="jpg",
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
        assert_studio_drip_authoring(
            update_cover_body,
            mode="no_drip_immediate_access",
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
            json={"content_document": lesson_document("Hello")},
        )
        assert update_content.status_code == 200, update_content.text
        assert update_content.json()["lesson_id"] == lesson_id
        assert update_content.json()["content_document"] == lesson_document("Hello")

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
        await cleanup_course_families(teacher_id)
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
        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Delete Media Family",
        )
        create_course = await async_client.post(
            "/studio/courses",
            headers=auth_header(teacher_token),
            json={
                "title": "Delete media boundary",
                "slug": f"delete-media-{uuid.uuid4().hex[:8]}",
                "course_group_id": family["id"],
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
            json={"content_document": lesson_document("Lesson body")},
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
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)


async def test_studio_course_family_transition_endpoints_are_canonical(async_client):
    teacher_email = f"family_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    created_course_ids: list[str] = []

    async def _create_course(*, title: str, slug: str, course_group_id: str) -> dict:
        response = await async_client.post(
            "/studio/courses",
            headers=auth_header(teacher_token),
            json={
                "title": title,
                "slug": slug,
                "course_group_id": course_group_id,
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        created_course_ids.append(str(body["id"]))
        assert {
            "id",
            "slug",
            "title",
            "course_group_id",
            "group_position",
            "cover_media_id",
            "cover",
            "price_amount_cents",
            "drip_authoring",
        }.issubset(body)
        assert_studio_drip_authoring(
            body,
            mode="no_drip_immediate_access",
        )
        return body

    try:
        listed_before = await async_client.get(
            "/studio/course-families",
            headers=auth_header(teacher_token),
        )
        assert listed_before.status_code == 200, listed_before.text
        assert listed_before.json()["items"] == []

        source_family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Source Family",
        )
        target_family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Target Family",
        )
        source_family_id = source_family["id"]
        target_family_id = target_family["id"]

        source_a = await _create_course(
            title="Source A",
            slug=f"source-a-{uuid.uuid4().hex[:8]}",
            course_group_id=source_family_id,
        )
        source_b = await _create_course(
            title="Source B",
            slug=f"source-b-{uuid.uuid4().hex[:8]}",
            course_group_id=source_family_id,
        )
        target_a = await _create_course(
            title="Target A",
            slug=f"target-a-{uuid.uuid4().hex[:8]}",
            course_group_id=target_family_id,
        )

        assert await read_course_family_rows(source_family_id) == [
            (str(source_a["id"]), 0),
            (str(source_b["id"]), 1),
        ]
        assert await read_course_family_rows(target_family_id) == [
            (str(target_a["id"]), 0),
        ]

        invalid_position_patch = await async_client.patch(
            f"/studio/courses/{source_a['id']}",
            headers=auth_header(teacher_token),
            json={"group_position": 0},
        )
        assert invalid_position_patch.status_code == 422, invalid_position_patch.text

        invalid_family_patch = await async_client.patch(
            f"/studio/courses/{source_a['id']}",
            headers=auth_header(teacher_token),
            json={"course_group_id": target_family_id},
        )
        assert invalid_family_patch.status_code == 422, invalid_family_patch.text

        reordered = await async_client.post(
            f"/studio/courses/{source_b['id']}/reorder",
            headers=auth_header(teacher_token),
            json={"group_position": 0},
        )
        assert reordered.status_code == 200, reordered.text
        reordered_body = reordered.json()
        assert reordered_body["group_position"] == 0
        assert reordered_body["course_group_id"] == source_family_id
        assert_studio_drip_authoring(
            reordered_body,
            mode="no_drip_immediate_access",
        )
        assert await read_course_family_rows(source_family_id) == [
            (str(source_b["id"]), 0),
            (str(source_a["id"]), 1),
        ]

        invalid_same_family_move = await async_client.post(
            f"/studio/courses/{source_a['id']}/move-family",
            headers=auth_header(teacher_token),
            json={"course_group_id": source_family_id},
        )
        assert invalid_same_family_move.status_code == 422, invalid_same_family_move.text

        moved = await async_client.post(
            f"/studio/courses/{source_a['id']}/move-family",
            headers=auth_header(teacher_token),
            json={"course_group_id": target_family_id},
        )
        assert moved.status_code == 200, moved.text
        moved_body = moved.json()
        assert moved_body["course_group_id"] == target_family_id
        assert moved_body["group_position"] == 1
        assert_studio_drip_authoring(
            moved_body,
            mode="no_drip_immediate_access",
        )
        assert await read_course_family_rows(source_family_id) == [
            (str(source_b["id"]), 0),
        ]
        assert await read_course_family_rows(target_family_id) == [
            (str(target_a["id"]), 0),
            (str(source_a["id"]), 1),
        ]

        listed_after = await async_client.get(
            "/studio/course-families",
            headers=auth_header(teacher_token),
        )
        assert listed_after.status_code == 200, listed_after.text
        listed_payload = listed_after.json()["items"]
        assert {
            "id",
            "name",
            "teacher_id",
            "created_at",
            "course_count",
        }.issubset(listed_payload[0])
        assert {item["id"] for item in listed_payload} == {
            source_family_id,
            target_family_id,
        }
    finally:
        for course_id in reversed(created_course_ids):
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)


async def test_studio_course_family_rename_and_empty_delete_are_canonical(
    async_client,
):
    teacher_email = f"family_manage_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    created_course_ids: list[str] = []

    async def _create_course(*, title: str, slug: str, course_group_id: str) -> dict:
        response = await async_client.post(
            "/studio/courses",
            headers=auth_header(teacher_token),
            json={
                "title": title,
                "slug": slug,
                "course_group_id": course_group_id,
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        created_course_ids.append(str(body["id"]))
        return body

    try:
        occupied_family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Occupied Family",
        )
        empty_family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Empty Family",
        )

        await _create_course(
            title="Occupied Course",
            slug=f"occupied-{uuid.uuid4().hex[:8]}",
            course_group_id=str(occupied_family["id"]),
        )

        renamed = await async_client.patch(
            f"/studio/course-families/{occupied_family['id']}",
            headers=auth_header(teacher_token),
            json={"name": "Renamed Family"},
        )
        assert renamed.status_code == 200, renamed.text
        renamed_body = renamed.json()
        assert renamed_body["id"] == occupied_family["id"]
        assert renamed_body["name"] == "Renamed Family"
        assert renamed_body["course_count"] == 1

        blocked_delete = await async_client.delete(
            f"/studio/course-families/{occupied_family['id']}",
            headers=auth_header(teacher_token),
        )
        assert blocked_delete.status_code == 422, blocked_delete.text
        assert blocked_delete.json()["detail"] == (
            "course family must be empty before deletion"
        )

        deleted = await async_client.delete(
            f"/studio/course-families/{empty_family['id']}",
            headers=auth_header(teacher_token),
        )
        assert deleted.status_code == 200, deleted.text
        assert deleted.json() == {"deleted": True}

        listed_after = await async_client.get(
            "/studio/course-families",
            headers=auth_header(teacher_token),
        )
        assert listed_after.status_code == 200, listed_after.text
        assert listed_after.json() == {
            "items": [
                {
                    "id": occupied_family["id"],
                    "name": "Renamed Family",
                    "teacher_id": teacher_id,
                    "created_at": occupied_family["created_at"],
                    "course_count": 1,
                }
            ]
        }
    finally:
        for course_id in reversed(created_course_ids):
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)
