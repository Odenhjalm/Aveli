import uuid

import pytest

from app import db


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
    return access_token, tokens.get("refresh_token"), user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher', is_admin = false WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def test_course_public_endpoints(async_client):
    teacher_email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"student_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    teacher_token, _, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher"
    )
    await promote_to_teacher(teacher_id)

    student_token, _, student_id = await register_user(
        async_client, student_email, password, "Student"
    )

    course_id = None
    module_id = None
    lesson_id = None

    try:
        slug = f"course-{uuid.uuid4().hex[:8]}"
        course_payload = {
            "title": "Free Intro Course",
            "slug": slug,
            "description": "Introductory course",
            "is_free_intro": True,
            "is_published": True,
            "price_amount_cents": 0,
        }
        create_resp = await async_client.post(
            "/studio/courses",
            json=course_payload,
            headers=auth_header(teacher_token),
        )
        assert create_resp.status_code == 200, create_resp.text
        course = create_resp.json()
        course_id = str(course["id"])
        # Modules are removed; public APIs expose a single virtual module per course.
        module_id = course_id

        lesson_resp = await async_client.post(
            "/studio/lessons",
            json={
                "course_id": course_id,
                "title": "Lesson 1",
                "content_markdown": "# Lesson",
                "position": 1,
                "is_intro": True,
            },
            headers=auth_header(teacher_token),
        )
        assert lesson_resp.status_code == 200, lesson_resp.text
        lesson_id = str(lesson_resp.json()["id"])

        list_resp = await async_client.get("/courses")
        assert list_resp.status_code == 200
        list_items = list_resp.json()["items"]
        assert any(str(item["id"]) == course_id for item in list_items)

        detail_resp = await async_client.get(f"/courses/{course_id}")
        assert detail_resp.status_code == 200
        detail_json = detail_resp.json()
        assert detail_json["course"]["id"] == course_id
        assert any(m["id"] == module_id for m in detail_json["modules"])

        modules_resp = await async_client.get(f"/courses/{course_id}/modules")
        assert modules_resp.status_code == 200
        assert any(m["id"] == module_id for m in modules_resp.json()["items"])

        lessons_resp = await async_client.get(f"/courses/modules/{module_id}/lessons")
        assert lessons_resp.status_code == 200
        assert any(lesson["id"] == lesson_id for lesson in lessons_resp.json()["items"])

        intro_resp = await async_client.get("/courses/intro-first")
        assert intro_resp.status_code == 200
        intro_course = intro_resp.json()["course"]
        assert intro_course is not None and intro_course["id"] == course_id

        access_before_resp = await async_client.get(
            f"/courses/{course_id}/access",
            headers=auth_header(student_token),
        )
        assert access_before_resp.status_code == 200
        access_before = access_before_resp.json()
        assert access_before["has_access"] is False
        assert access_before["enrolled"] is False

        enroll_status_resp = await async_client.get(
            f"/courses/{course_id}/enrollment",
            headers=auth_header(student_token),
        )
        assert enroll_status_resp.status_code == 200
        assert enroll_status_resp.json()["enrolled"] is False

        enroll_resp = await async_client.post(
            f"/courses/{course_id}/enroll",
            headers=auth_header(student_token),
        )
        assert enroll_resp.status_code == 200, enroll_resp.text
        payload = enroll_resp.json()
        assert payload["enrolled"] is True
        assert payload["status"] in {"enrolled", "already_enrolled"}
        assert payload["consumed"] >= 1
        assert payload["limit"] >= payload["consumed"]

        enroll_status_resp = await async_client.get(
            f"/courses/{course_id}/enrollment",
            headers=auth_header(student_token),
        )
        assert enroll_status_resp.json()["enrolled"] is True

        access_after_resp = await async_client.get(
            f"/courses/{course_id}/access",
            headers=auth_header(student_token),
        )
        assert access_after_resp.status_code == 200
        access_after = access_after_resp.json()
        assert access_after["has_access"] is True
        assert access_after["enrolled"] is True
        assert access_after["free_consumed"] >= 1

        quota_resp = await async_client.get(
            "/courses/free-consumed",
            headers=auth_header(student_token),
        )
        assert quota_resp.status_code == 200
        assert quota_resp.json()["consumed"] >= 1

        limit_resp = await async_client.get("/config/free-course-limit")
        assert limit_resp.status_code == 200
        assert "limit" in limit_resp.json()

        async with db.pool.connection() as conn:  # type: ignore
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "UPDATE app.app_config SET free_course_limit = 1 WHERE id = 1"
                )
                await conn.commit()

        second_course_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Free Intro Course 2",
                "slug": f"{slug}-2",
                "description": "Another Intro",
                "is_free_intro": True,
                "is_published": True,
                "price_amount_cents": 0,
            },
            headers=auth_header(teacher_token),
        )
        assert second_course_resp.status_code == 200, second_course_resp.text
        second_course_id = str(second_course_resp.json()["id"])

        limit_fail = await async_client.post(
            f"/courses/{second_course_id}/enroll",
            headers=auth_header(student_token),
        )
        assert limit_fail.status_code == 403, limit_fail.text
        limit_detail = limit_fail.json()["detail"]
        assert limit_detail["code"] == "limit_reached"
        assert limit_detail["consumed"] >= 1
        assert limit_detail["limit"] == 1

        async with db.pool.connection() as conn:  # type: ignore
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "UPDATE app.app_config SET free_course_limit = 5 WHERE id = 1"
                )
                await conn.commit()

        unauthorized_enroll = await async_client.post(f"/courses/{course_id}/enroll")
        assert unauthorized_enroll.status_code == 401

    finally:
        if teacher_id:
            await cleanup_user(teacher_id)
        if student_id:
            await cleanup_user(student_id)
