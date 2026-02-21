import uuid

import pytest

from app import db, repositories
from app.repositories import course_entitlements


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
        assert detail_resp.status_code == 403

        modules_resp = await async_client.get(f"/courses/{course_id}/modules")
        assert modules_resp.status_code == 403

        lessons_resp = await async_client.get(f"/courses/modules/{module_id}/lessons")
        assert lessons_resp.status_code == 403

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
        assert access_before["can_access"] is False
        assert access_before["access_reason"] == "none"
        assert access_before["enrolled"] is False

        enroll_status_resp = await async_client.get(
            f"/courses/{course_id}/enrollment",
            headers=auth_header(student_token),
        )
        assert enroll_status_resp.status_code == 200
        assert enroll_status_resp.json()["enrolled"] is False

        enroll_without_subscription = await async_client.post(
            f"/courses/{course_id}/enroll",
            headers=auth_header(student_token),
        )
        assert enroll_without_subscription.status_code == 403

        await repositories.upsert_membership_record(
            str(student_id),
            plan_interval="month",
            price_id="price_monthly_intro",
            status="active",
            stripe_customer_id=f"cus_{uuid.uuid4().hex[:8]}",
            stripe_subscription_id=f"sub_{uuid.uuid4().hex[:8]}",
        )

        enroll_resp = await async_client.post(
            f"/courses/{course_id}/enroll",
            headers=auth_header(student_token),
        )
        assert enroll_resp.status_code == 200, enroll_resp.text
        payload = enroll_resp.json()
        assert payload["enrolled"] is True
        assert payload["status"] in {"enrolled", "already_enrolled"}

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
        assert access_after["can_access"] is True
        assert access_after["access_reason"] == "enrolled"
        assert access_after["enrolled"] is True

        detail_after_enroll = await async_client.get(
            f"/courses/{course_id}",
            headers=auth_header(student_token),
        )
        assert detail_after_enroll.status_code == 200, detail_after_enroll.text
        detail_json = detail_after_enroll.json()
        assert detail_json["course"]["id"] == course_id
        assert any(m["id"] == module_id for m in detail_json["modules"])

        modules_after_enroll = await async_client.get(
            f"/courses/{course_id}/modules",
            headers=auth_header(student_token),
        )
        assert modules_after_enroll.status_code == 200, modules_after_enroll.text
        assert any(m["id"] == module_id for m in modules_after_enroll.json()["items"])

        lessons_after_enroll = await async_client.get(
            f"/courses/modules/{module_id}/lessons",
            headers=auth_header(student_token),
        )
        assert lessons_after_enroll.status_code == 200, lessons_after_enroll.text
        assert any(lesson["id"] == lesson_id for lesson in lessons_after_enroll.json()["items"])

        lesson_detail_after_enroll = await async_client.get(
            f"/courses/lessons/{lesson_id}",
            headers=auth_header(student_token),
        )
        assert lesson_detail_after_enroll.status_code == 200, lesson_detail_after_enroll.text
        assert lesson_detail_after_enroll.json()["lesson"]["id"] == lesson_id

        by_slug_after_enroll = await async_client.get(
            f"/courses/by-slug/{slug}",
            headers=auth_header(student_token),
        )
        assert by_slug_after_enroll.status_code == 200, by_slug_after_enroll.text
        assert by_slug_after_enroll.json()["course"]["id"] == course_id

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

        second_enroll = await async_client.post(
            f"/courses/{second_course_id}/enroll",
            headers=auth_header(student_token),
        )
        assert second_enroll.status_code == 403, second_enroll.text
        assert "monthly intro limit" in second_enroll.text.lower()

        unauthorized_enroll = await async_client.post(f"/courses/{course_id}/enroll")
        assert unauthorized_enroll.status_code == 401

    finally:
        if teacher_id:
            await cleanup_user(teacher_id)
        if student_id:
            await cleanup_user(student_id)


async def test_teacher_has_full_access_to_own_paid_course(async_client):
    teacher_email = f"teacher_paid_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    teacher_token, _, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher"
    )
    await promote_to_teacher(teacher_id)

    try:
        slug = f"paid-course-{uuid.uuid4().hex[:8]}"
        create_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Paid Teacher Course",
                "slug": slug,
                "description": "Private paid course",
                "is_free_intro": False,
                "is_published": False,
                "price_amount_cents": 12900,
            },
            headers=auth_header(teacher_token),
        )
        assert create_resp.status_code == 200, create_resp.text
        course_id = str(create_resp.json()["id"])

        lesson_resp = await async_client.post(
            "/studio/lessons",
            json={
                "course_id": course_id,
                "title": "Paid Lesson",
                "content_markdown": "# Private",
                "position": 1,
                "is_intro": False,
            },
            headers=auth_header(teacher_token),
        )
        assert lesson_resp.status_code == 200, lesson_resp.text
        lesson_id = str(lesson_resp.json()["id"])

        access_resp = await async_client.get(
            f"/courses/{course_id}/access",
            headers=auth_header(teacher_token),
        )
        assert access_resp.status_code == 200, access_resp.text
        access = access_resp.json()
        assert access["can_access"] is True
        assert access["has_access"] is True
        assert access["access_reason"] == "teacher"

        detail_resp = await async_client.get(
            f"/courses/{course_id}",
            headers=auth_header(teacher_token),
        )
        assert detail_resp.status_code == 200, detail_resp.text
        assert str(detail_resp.json()["course"]["id"]) == course_id

        lesson_detail_resp = await async_client.get(
            f"/courses/lessons/{lesson_id}",
            headers=auth_header(teacher_token),
        )
        assert lesson_detail_resp.status_code == 200, lesson_detail_resp.text
        assert lesson_detail_resp.json()["lesson"]["id"] == lesson_id

        media_upload_resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media",
            headers=auth_header(teacher_token),
            files={"file": ("teacher-paid.mp3", b"ID3", "audio/mpeg")},
            data={"is_intro": "false"},
        )
        assert media_upload_resp.status_code == 200, media_upload_resp.text
        media_id = str(media_upload_resp.json()["id"])

        media_sign_resp = await async_client.post(
            "/media/sign",
            headers=auth_header(teacher_token),
            json={"media_id": media_id, "mode": "student_render"},
        )
        assert media_sign_resp.status_code == 200, media_sign_resp.text
        assert media_sign_resp.json()["media_id"] == media_id
    finally:
        if teacher_id:
            await cleanup_user(teacher_id)


async def test_active_subscription_only_grants_intro_course_access(async_client):
    teacher_email = f"teacher_sub_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"student_sub_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    teacher_token, _, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher"
    )
    await promote_to_teacher(teacher_id)
    student_token, _, student_id = await register_user(
        async_client, student_email, password, "Student"
    )

    try:
        intro_slug = f"intro-sub-{uuid.uuid4().hex[:8]}"
        intro_course_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Subscription Intro",
                "slug": intro_slug,
                "description": "Intro course",
                "is_free_intro": True,
                "is_published": True,
                "price_amount_cents": 0,
            },
            headers=auth_header(teacher_token),
        )
        assert intro_course_resp.status_code == 200, intro_course_resp.text
        intro_course_id = str(intro_course_resp.json()["id"])
        intro_lesson_resp = await async_client.post(
            "/studio/lessons",
            json={
                "course_id": intro_course_id,
                "title": "Intro Lesson",
                "content_markdown": "# Intro",
                "position": 1,
                "is_intro": True,
            },
            headers=auth_header(teacher_token),
        )
        assert intro_lesson_resp.status_code == 200, intro_lesson_resp.text
        intro_lesson_id = str(intro_lesson_resp.json()["id"])

        paid_slug = f"paid-sub-{uuid.uuid4().hex[:8]}"
        paid_course_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Subscription Paid",
                "slug": paid_slug,
                "description": "Paid course",
                "is_free_intro": False,
                "is_published": True,
                "price_amount_cents": 14900,
            },
            headers=auth_header(teacher_token),
        )
        assert paid_course_resp.status_code == 200, paid_course_resp.text
        paid_course_id = str(paid_course_resp.json()["id"])

        await repositories.upsert_membership_record(
            str(student_id),
            plan_interval="month",
            price_id="price_monthly",
            status="active",
            stripe_customer_id="cus_sub_test",
            stripe_subscription_id="sub_sub_test",
        )

        intro_course_access = await async_client.get(
            f"/courses/{intro_course_id}",
            headers=auth_header(student_token),
        )
        assert intro_course_access.status_code == 200, intro_course_access.text

        intro_lesson_access = await async_client.get(
            f"/courses/lessons/{intro_lesson_id}",
            headers=auth_header(student_token),
        )
        assert intro_lesson_access.status_code == 200, intro_lesson_access.text

        paid_course_access = await async_client.get(
            f"/courses/{paid_course_id}",
            headers=auth_header(student_token),
        )
        assert paid_course_access.status_code == 403, paid_course_access.text
    finally:
        if teacher_id:
            await cleanup_user(teacher_id)
        if student_id:
            await cleanup_user(student_id)


async def test_step1_ownership_bypasses_intro_monthly_limit(async_client):
    teacher_email = f"teacher_step1_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"student_step1_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    teacher_token, _, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher"
    )
    await promote_to_teacher(teacher_id)
    student_token, _, student_id = await register_user(
        async_client, student_email, password, "Student"
    )

    try:
        step1_slug = f"owned-step1-{uuid.uuid4().hex[:8]}"
        step1_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Owned Step1",
                "slug": step1_slug,
                "description": "Step1 course",
                "journey_step": "step1",
                "is_free_intro": False,
                "is_published": True,
                "price_amount_cents": 9900,
            },
            headers=auth_header(teacher_token),
        )
        assert step1_resp.status_code == 200, step1_resp.text

        await course_entitlements.grant_course_entitlement(
            user_id=str(student_id),
            course_slug=step1_slug,
            stripe_customer_id="cus_step1_owner",
            payment_intent_id="pi_step1_owner",
        )

        intro_one_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Intro One",
                "slug": f"intro-one-{uuid.uuid4().hex[:8]}",
                "description": "First intro",
                "is_free_intro": True,
                "is_published": True,
                "price_amount_cents": 0,
            },
            headers=auth_header(teacher_token),
        )
        assert intro_one_resp.status_code == 200, intro_one_resp.text
        intro_two_resp = await async_client.post(
            "/studio/courses",
            json={
                "title": "Intro Two",
                "slug": f"intro-two-{uuid.uuid4().hex[:8]}",
                "description": "Second intro",
                "is_free_intro": True,
                "is_published": True,
                "price_amount_cents": 0,
            },
            headers=auth_header(teacher_token),
        )
        assert intro_two_resp.status_code == 200, intro_two_resp.text

        intro_one_id = str(intro_one_resp.json()["id"])
        intro_two_id = str(intro_two_resp.json()["id"])

        enroll_intro_one = await async_client.post(
            f"/courses/{intro_one_id}/enroll",
            headers=auth_header(student_token),
        )
        assert enroll_intro_one.status_code == 200, enroll_intro_one.text
        enroll_intro_two = await async_client.post(
            f"/courses/{intro_two_id}/enroll",
            headers=auth_header(student_token),
        )
        assert enroll_intro_two.status_code == 200, enroll_intro_two.text

        intro_two_access = await async_client.get(
            f"/courses/{intro_two_id}",
            headers=auth_header(student_token),
        )
        assert intro_two_access.status_code == 200, intro_two_access.text
    finally:
        if teacher_id:
            await cleanup_user(teacher_id)
        if student_id:
            await cleanup_user(student_id)
