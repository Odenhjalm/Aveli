import uuid

import pytest

from app import db, models
from app.repositories import courses as courses_repo

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(client, email: str, password: str, display_name: str) -> tuple[str, str]:
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    token = tokens["access_token"]

    me_resp = await client.get("/auth/me", headers=auth_header(token))
    assert me_resp.status_code == 200, me_resp.text
    user_id = me_resp.json()["user_id"]
    return token, user_id


async def promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def test_home_audio_requires_teacher_opt_in_before_entitlements(async_client):
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client,
        f"home_gate_teacher_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    student_token, student_id = await register_user(
        async_client,
        f"home_gate_student_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Student",
    )

    slug = f"home-gate-{uuid.uuid4().hex[:8]}"
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.courses (
                  slug,
                  title,
                  is_free_intro,
                  price_amount_cents,
                  currency,
                  is_published,
                  created_by
                )
                VALUES (%s, %s, false, 1000, 'sek', true, %s)
                RETURNING id
                """,
                (slug, f"Course {slug}", teacher_id),
            )
            row = await cur.fetchone()
            await conn.commit()
    course_id = str(row[0])

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.lessons (course_id, title, position, is_intro)
                VALUES (%s, %s, 0, false)
                RETURNING id
                """,
                (course_id, "Lesson"),
            )
            row = await cur.fetchone()
            await conn.commit()
    lesson_id = str(row[0])

    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=f"lesson-media/{uuid.uuid4().hex}.mp3",
        storage_bucket="lesson-media",
        position=1,
        media_id=None,
    )
    assert lesson_media
    lesson_media_id = str(lesson_media["id"])

    # Not opted-in => excluded even for the owner.
    resp_off = await async_client.get("/home/audio", headers=auth_header(teacher_token))
    assert resp_off.status_code == 200, resp_off.text
    assert lesson_media_id not in {it.get("id") for it in resp_off.json().get("items") or []}

    create_link = await async_client.post(
        "/studio/home-player/course-links",
        headers=auth_header(teacher_token),
        json={
            "lesson_media_id": lesson_media_id,
            "title": "Home track",
            "enabled": True,
        },
    )
    assert create_link.status_code == 201, create_link.text
    link_id = str(create_link.json()["id"])

    # Opted-in => owner sees it.
    resp_on = await async_client.get("/home/audio", headers=auth_header(teacher_token))
    assert resp_on.status_code == 200, resp_on.text
    assert lesson_media_id in {it.get("id") for it in resp_on.json().get("items") or []}

    # Student still needs existing rights (enrollment) even when opted-in.
    resp_student = await async_client.get("/home/audio", headers=auth_header(student_token))
    assert resp_student.status_code == 200, resp_student.text
    assert lesson_media_id not in {
        it.get("id") for it in resp_student.json().get("items") or []
    }

    await courses_repo.ensure_course_enrollment(student_id, course_id)
    resp_student_enrolled = await async_client.get(
        "/home/audio",
        headers=auth_header(student_token),
    )
    assert resp_student_enrolled.status_code == 200, resp_student_enrolled.text
    assert lesson_media_id in {
        it.get("id") for it in resp_student_enrolled.json().get("items") or []
    }

    # Disable link => hidden.
    patch_resp = await async_client.patch(
        f"/studio/home-player/course-links/{link_id}",
        headers=auth_header(teacher_token),
        json={"enabled": False},
    )
    assert patch_resp.status_code == 200, patch_resp.text
    assert patch_resp.json()["enabled"] is False

    resp_disabled = await async_client.get("/home/audio", headers=auth_header(teacher_token))
    assert resp_disabled.status_code == 200, resp_disabled.text
    assert lesson_media_id not in {it.get("id") for it in resp_disabled.json().get("items") or []}
