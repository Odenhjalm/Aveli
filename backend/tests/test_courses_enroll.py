import uuid

import pytest

from app import db, repositories


async def _grant_app_entry(async_client, headers: dict[str, str], user_id: str) -> None:
    profile_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=headers,
        json={"display_name": "Course QA", "bio": None},
    )
    assert profile_resp.status_code == 200, profile_resp.text
    onboarding_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=headers,
    )
    assert onboarding_resp.status_code == 200, onboarding_resp.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )


async def _insert_teacher(email: str) -> str:
    user_id = str(uuid.uuid4())
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO auth.users (
                    id,
                    email,
                    encrypted_password,
                    created_at,
                    updated_at
                )
                VALUES (%s::uuid, %s, 'test-hash', now(), now())
                """,
                (user_id, email.strip().lower()),
            )
            await cur.execute(
                """
                INSERT INTO app.auth_subjects (
                    user_id,
                    email,
                    role,
                    onboarding_state
                )
                VALUES (%s::uuid, %s, 'teacher', 'completed')
                """,
                (user_id, email.strip().lower()),
            )
            await conn.commit()
    return user_id


async def _insert_free_course(teacher_id: str) -> dict[str, str]:
    course_id = str(uuid.uuid4())
    slug = f"free-intro-{uuid.uuid4().hex[:8]}"
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.courses (
                    id,
                    teacher_id,
                    title,
                    slug,
                    course_group_id,
                    group_position,
                    visibility,
                    content_ready,
                    price_amount_cents,
                    sellable,
                    drip_enabled,
                    drip_interval_days
                )
                VALUES (
                    %s::uuid,
                    %s::uuid,
                    'Free Intro Course',
                    %s,
                    %s::uuid,
                    0,
                    'public',
                    true,
                    null,
                    false,
                    false,
                    null
                )
                """,
                (course_id, teacher_id, slug, str(uuid.uuid4())),
            )
            await conn.commit()
    return {"id": course_id, "slug": slug, "title": "Free Intro Course"}


async def _cleanup_course(course_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.course_enrollments WHERE course_id = %s::uuid",
                (course_id,),
            )
            await cur.execute(
                "DELETE FROM app.courses WHERE id = %s::uuid",
                (course_id,),
            )
            await conn.commit()


async def _cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.profiles WHERE user_id = %s::uuid",
                (user_id,),
            )
            await cur.execute(
                "DELETE FROM app.memberships WHERE user_id = %s::uuid",
                (user_id,),
            )
            await cur.execute(
                "DELETE FROM app.auth_subjects WHERE user_id = %s::uuid",
                (user_id,),
            )
            await cur.execute("DELETE FROM auth.users WHERE id = %s::uuid", (user_id,))
            await conn.commit()


@pytest.mark.anyio("asyncio")
async def test_enroll_free_intro_course_updates_my_courses(async_client):
    email = f"free_intro_{uuid.uuid4().hex[:8]}@example.com"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": "Intro123!",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    access_token = register_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    profile_resp = await async_client.get("/profiles/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    await _grant_app_entry(async_client, headers, user_id)
    teacher_id = await _insert_teacher(
        f"free_intro_teacher_{uuid.uuid4().hex[:8]}@example.com"
    )
    course = await _insert_free_course(teacher_id)

    try:
        me_resp = await async_client.get("/courses/me", headers=headers)
        assert me_resp.status_code == 200, me_resp.text
        assert me_resp.json().get("items") == []

        catalog_resp = await async_client.get(
            "/courses",
            headers=headers,
            params={"limit": 100},
        )
        assert catalog_resp.status_code == 200, catalog_resp.text
        items = [
            item
            for item in (catalog_resp.json().get("items") or [])
            if item.get("id") == course["id"]
        ]
        assert len(items) == 1
        course_id = items[0]["id"]
        assert items[0]["enrollable"] is True
        assert items[0]["purchasable"] is False

        enroll_resp = await async_client.post(
            f"/courses/{course_id}/enroll", headers=headers
        )
        assert enroll_resp.status_code == 200, enroll_resp.text
        payload = enroll_resp.json()
        assert payload["required_enrollment_source"] == "intro_enrollment"
        assert payload["enrollable"] is True
        assert payload["purchasable"] is False
        assert payload["enrollment"] is not None

        me_after = await async_client.get("/courses/me", headers=headers)
        assert me_after.status_code == 200, me_after.text
        enrolled_ids = [row["id"] for row in me_after.json().get("items", [])]
        assert course_id in enrolled_ids
    finally:
        await _cleanup_course(course["id"])
        await _cleanup_user(teacher_id)
        await _cleanup_user(user_id)
