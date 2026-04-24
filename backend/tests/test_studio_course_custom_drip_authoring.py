import uuid

import pytest

from app import db, repositories
from app.repositories import courses as courses_repo
from ._custom_drip_test_support import ensure_custom_drip_schema


pytestmark = pytest.mark.anyio("asyncio")


@pytest.fixture(autouse=True)
async def _ensure_custom_drip_schema(async_client):
    del async_client
    await ensure_custom_drip_schema()


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


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


async def create_course(async_client, *, token: str, course_group_id: str, slug: str) -> dict:
    response = await async_client.post(
        "/studio/courses",
        headers=auth_header(token),
        json={
            "title": "Custom Drip Course",
            "slug": slug,
            "course_group_id": course_group_id,
            "price_amount_cents": None,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


async def create_lessons(async_client, *, token: str, course_id: str, count: int) -> list[str]:
    lesson_ids: list[str] = []
    for position in range(1, count + 1):
        response = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(token),
            json={
                "lesson_title": f"Lesson {position}",
                "position": position,
            },
        )
        assert response.status_code == 200, response.text
        lesson_ids.append(str(response.json()["id"]))
    return lesson_ids


def custom_schedule_payload(
    lesson_ids: list[str],
    offsets: list[int],
) -> dict:
    return {
        "mode": "custom_lesson_offsets",
        "custom_schedule": {
            "rows": [
                {
                    "lesson_id": lesson_id,
                    "unlock_offset_days": offset,
                }
                for lesson_id, offset in zip(lesson_ids, offsets, strict=True)
            ]
        },
    }


def assert_drip_authoring_shape(
    course: dict,
    *,
    mode: str,
    schedule_locked: bool,
    legacy_interval: int | None = None,
    custom_rows: list[dict] | None = None,
) -> None:
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
    if custom_rows is None:
        assert drip_authoring.get("custom_schedule") in (None, {})
    else:
        assert drip_authoring["custom_schedule"] == {"rows": custom_rows}


async def read_drip_storage(course_id: str) -> dict:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT
                    c.drip_enabled,
                    c.drip_interval_days,
                    EXISTS (
                        SELECT 1
                          FROM app.course_custom_drip_configs
                         WHERE course_id = c.id
                    ) AS has_custom_config
                  FROM app.courses AS c
                 WHERE c.id = %s::uuid
                """,
                (course_id,),
            )
            drip_enabled, drip_interval_days, has_custom_config = await cur.fetchone()
            await cur.execute(
                """
                SELECT
                    offsets.lesson_id::text,
                    offsets.unlock_offset_days
                  FROM app.course_custom_drip_lesson_offsets AS offsets
                  JOIN app.lessons AS l
                    ON l.id = offsets.lesson_id
                 WHERE offsets.course_id = %s::uuid
                 ORDER BY l.position ASC, l.id ASC
                """,
                (course_id,),
            )
            rows = [
                {
                    "lesson_id": str(row[0]),
                    "unlock_offset_days": int(row[1]),
                }
                for row in await cur.fetchall()
            ]
    return {
        "drip_enabled": bool(drip_enabled),
        "drip_interval_days": drip_interval_days,
        "has_custom_config": bool(has_custom_config),
        "rows": rows,
    }


async def read_custom_drip_counts(course_id: str) -> tuple[int, int]:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT COUNT(*)
                  FROM app.lessons
                 WHERE course_id = %s::uuid
                """,
                (course_id,),
            )
            lesson_count = int((await cur.fetchone())[0])
            await cur.execute(
                """
                SELECT COUNT(*)
                  FROM app.course_custom_drip_lesson_offsets
                 WHERE course_id = %s::uuid
                """,
                (course_id,),
            )
            offset_count = int((await cur.fetchone())[0])
    return lesson_count, offset_count


async def seed_first_enrollment(course_id: str, user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.courses
                   SET required_enrollment_source = 'intro_enrollment'::app.course_enrollment_source
                 WHERE id = %s::uuid
                """,
                (course_id,),
            )
            await conn.commit()
    await courses_repo.create_course_enrollment(
        user_id=user_id,
        course_id=course_id,
        source="intro_enrollment",
    )


async def test_studio_custom_drip_write_replaces_full_schedule_atomically(async_client):
    teacher_email = f"custom_atomic_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    course_id = None

    try:
        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Atomic Family",
        )
        course = await create_course(
            async_client,
            token=teacher_token,
            course_group_id=family["id"],
            slug=f"custom-atomic-{uuid.uuid4().hex[:8]}",
        )
        course_id = str(course["id"])
        lesson_ids = await create_lessons(
            async_client,
            token=teacher_token,
            course_id=course_id,
            count=3,
        )

        partial_write = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids[:2], [0, 2]),
        )
        assert partial_write.status_code == 422, partial_write.text
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": False,
            "rows": [],
        }

        first_rows = [
            {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
            {"lesson_id": lesson_ids[1], "unlock_offset_days": 2},
            {"lesson_id": lesson_ids[2], "unlock_offset_days": 5},
        ]
        first_write = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 2, 5]),
        )
        assert first_write.status_code == 200, first_write.text
        assert_drip_authoring_shape(
            first_write.json(),
            mode="custom_lesson_offsets",
            schedule_locked=False,
            custom_rows=first_rows,
        )

        replacement_rows = [
            {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
            {"lesson_id": lesson_ids[1], "unlock_offset_days": 4},
            {"lesson_id": lesson_ids[2], "unlock_offset_days": 4},
        ]
        replacement_write = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 4, 4]),
        )
        assert replacement_write.status_code == 200, replacement_write.text
        assert_drip_authoring_shape(
            replacement_write.json(),
            mode="custom_lesson_offsets",
            schedule_locked=False,
            custom_rows=replacement_rows,
        )
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": True,
            "rows": replacement_rows,
        }
    finally:
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)


async def test_custom_drip_lesson_create_preserves_schedule_invariant(async_client):
    teacher_email = f"custom_create_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    course_id = None

    try:
        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Lesson Create Family",
        )
        course = await create_course(
            async_client,
            token=teacher_token,
            course_group_id=family["id"],
            slug=f"custom-create-{uuid.uuid4().hex[:8]}",
        )
        course_id = str(course["id"])
        lesson_ids = await create_lessons(
            async_client,
            token=teacher_token,
            course_id=course_id,
            count=2,
        )

        write_response = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 6]),
        )
        assert write_response.status_code == 200, write_response.text

        create_response = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
            json={
                "lesson_title": "Lesson 3",
                "position": 3,
            },
        )
        assert create_response.status_code == 200, create_response.text
        created_lesson_id = str(create_response.json()["id"])

        assert await read_custom_drip_counts(course_id) == (3, 3)
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": True,
            "rows": [
                {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
                {"lesson_id": lesson_ids[1], "unlock_offset_days": 6},
                {"lesson_id": created_lesson_id, "unlock_offset_days": 6},
            ],
        }
    finally:
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)


async def test_non_custom_lesson_create_does_not_create_custom_drip_rows(async_client):
    teacher_email = f"plain_create_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    course_id = None

    try:
        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Plain Lesson Family",
        )
        course = await create_course(
            async_client,
            token=teacher_token,
            course_group_id=family["id"],
            slug=f"plain-create-{uuid.uuid4().hex[:8]}",
        )
        course_id = str(course["id"])

        create_response = await async_client.post(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
            json={
                "lesson_title": "Plain Lesson",
                "position": 1,
            },
        )
        assert create_response.status_code == 200, create_response.text

        assert await read_custom_drip_counts(course_id) == (1, 0)
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": False,
            "rows": [],
        }
    finally:
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)


async def test_studio_custom_drip_zero_enrollment_mode_switches_are_atomic(async_client):
    teacher_email = f"custom_switch_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    course_id = None

    try:
        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Switch Family",
        )
        course = await create_course(
            async_client,
            token=teacher_token,
            course_group_id=family["id"],
            slug=f"custom-switch-{uuid.uuid4().hex[:8]}",
        )
        course_id = str(course["id"])
        lesson_ids = await create_lessons(
            async_client,
            token=teacher_token,
            course_id=course_id,
            count=2,
        )

        no_drip_to_custom = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 3]),
        )
        assert no_drip_to_custom.status_code == 200, no_drip_to_custom.text
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": True,
            "rows": [
                {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
                {"lesson_id": lesson_ids[1], "unlock_offset_days": 3},
            ],
        }

        custom_to_legacy = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json={
                "mode": "legacy_uniform_drip",
                "legacy_uniform": {"drip_interval_days": 7},
            },
        )
        assert custom_to_legacy.status_code == 200, custom_to_legacy.text
        assert_drip_authoring_shape(
            custom_to_legacy.json(),
            mode="legacy_uniform_drip",
            schedule_locked=False,
            legacy_interval=7,
        )
        assert await read_drip_storage(course_id) == {
            "drip_enabled": True,
            "drip_interval_days": 7,
            "has_custom_config": False,
            "rows": [],
        }

        legacy_to_custom = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 1]),
        )
        assert legacy_to_custom.status_code == 200, legacy_to_custom.text
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": True,
            "rows": [
                {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
                {"lesson_id": lesson_ids[1], "unlock_offset_days": 1},
            ],
        }

        custom_to_no_drip = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json={"mode": "no_drip_immediate_access"},
        )
        assert custom_to_no_drip.status_code == 200, custom_to_no_drip.text
        assert_drip_authoring_shape(
            custom_to_no_drip.json(),
            mode="no_drip_immediate_access",
            schedule_locked=False,
        )
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": False,
            "rows": [],
        }

        no_drip_to_custom_again = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 5]),
        )
        assert no_drip_to_custom_again.status_code == 200, no_drip_to_custom_again.text
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": True,
            "rows": [
                {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
                {"lesson_id": lesson_ids[1], "unlock_offset_days": 5},
            ],
        }
    finally:
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)


async def test_studio_custom_drip_lock_rejection_and_patch_isolation(async_client):
    teacher_email = f"custom_lock_teacher_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"custom_lock_student_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)
    _, _, student_id = await register_user(
        async_client,
        student_email,
        password,
        "Student",
    )

    course_id = None

    try:
        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Lock Family",
        )
        course = await create_course(
            async_client,
            token=teacher_token,
            course_group_id=family["id"],
            slug=f"custom-lock-{uuid.uuid4().hex[:8]}",
        )
        course_id = str(course["id"])
        lesson_ids = await create_lessons(
            async_client,
            token=teacher_token,
            course_id=course_id,
            count=2,
        )

        initial_custom = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 6]),
        )
        assert initial_custom.status_code == 200, initial_custom.text

        await seed_first_enrollment(course_id, student_id)

        locked_write = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json={
                "mode": "legacy_uniform_drip",
                "legacy_uniform": {"drip_interval_days": 9},
            },
        )
        assert locked_write.status_code == 409, locked_write.text
        assert locked_write.json() == {
            "code": "studio_course_schedule_locked",
            "detail": "Schedule-affecting edits are locked after first enrollment.",
            "course_id": course_id,
            "schedule_locked": True,
        }
        assert await read_drip_storage(course_id) == {
            "drip_enabled": False,
            "drip_interval_days": None,
            "has_custom_config": True,
            "rows": [
                {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
                {"lesson_id": lesson_ids[1], "unlock_offset_days": 6},
            ],
        }

        metadata_patch = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(teacher_token),
            json={"title": "Metadata survives schedule lock"},
        )
        assert metadata_patch.status_code == 200, metadata_patch.text
        patched_course = metadata_patch.json()
        assert patched_course["title"] == "Metadata survives schedule lock"
        assert_drip_authoring_shape(
            patched_course,
            mode="custom_lesson_offsets",
            schedule_locked=True,
            custom_rows=[
                {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
                {"lesson_id": lesson_ids[1], "unlock_offset_days": 6},
            ],
        )

        invalid_patch = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(teacher_token),
            json={"drip_enabled": True, "drip_interval_days": 7},
        )
        assert invalid_patch.status_code == 422, invalid_patch.text

        detail = await async_client.get(
            f"/studio/courses/{course_id}",
            headers=auth_header(teacher_token),
        )
        assert detail.status_code == 200, detail.text
        assert_drip_authoring_shape(
            detail.json(),
            mode="custom_lesson_offsets",
            schedule_locked=True,
            custom_rows=[
                {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
                {"lesson_id": lesson_ids[1], "unlock_offset_days": 6},
            ],
        )
    finally:
        if course_id:
            async with db.pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        "DELETE FROM app.course_enrollments WHERE course_id = %s::uuid",
                        (course_id,),
                    )
                    await conn.commit()
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(student_id)
        await cleanup_user(teacher_id)


async def test_studio_custom_drip_read_hydration_surfaces(async_client):
    teacher_email = f"custom_read_teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    teacher_token, _, teacher_id = await register_user(
        async_client,
        teacher_email,
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    course_id = None

    try:
        family = await create_course_family(
            async_client,
            token=teacher_token,
            name="Read Family",
        )
        course = await create_course(
            async_client,
            token=teacher_token,
            course_group_id=family["id"],
            slug=f"custom-read-{uuid.uuid4().hex[:8]}",
        )
        course_id = str(course["id"])
        lesson_ids = await create_lessons(
            async_client,
            token=teacher_token,
            course_id=course_id,
            count=2,
        )
        expected_rows = [
            {"lesson_id": lesson_ids[0], "unlock_offset_days": 0},
            {"lesson_id": lesson_ids[1], "unlock_offset_days": 8},
        ]

        write_response = await async_client.put(
            f"/studio/courses/{course_id}/drip-authoring",
            headers=auth_header(teacher_token),
            json=custom_schedule_payload(lesson_ids, [0, 8]),
        )
        assert write_response.status_code == 200, write_response.text

        list_response = await async_client.get(
            "/studio/courses",
            headers=auth_header(teacher_token),
        )
        assert list_response.status_code == 200, list_response.text
        summary = next(
            item
            for item in list_response.json()["items"]
            if str(item["id"]) == course_id
        )
        assert_drip_authoring_shape(
            summary,
            mode="custom_lesson_offsets",
            schedule_locked=False,
        )
        assert "custom_schedule" not in summary["drip_authoring"]

        detail_response = await async_client.get(
            f"/studio/courses/{course_id}",
            headers=auth_header(teacher_token),
        )
        assert detail_response.status_code == 200, detail_response.text
        assert_drip_authoring_shape(
            detail_response.json(),
            mode="custom_lesson_offsets",
            schedule_locked=False,
            custom_rows=expected_rows,
        )
    finally:
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_course_families(teacher_id)
        await cleanup_user(teacher_id)
