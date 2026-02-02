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
    return access_token, tokens["refresh_token"], user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def test_course_and_studio_endpoints(async_client):
    teacher_email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"student_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"

    teacher_token, teacher_refresh, teacher_id = await register_user(
        async_client, teacher_email, password, "Teacher"
    )
    await promote_to_teacher(teacher_id)

    student_token, student_refresh, student_id = await register_user(
        async_client, student_email, password, "Student"
    )

    course_id = None
    lesson_id = None
    quiz_id = None
    question_id = None
    media_id = None

    try:
        # Non-teacher access is forbidden
        resp = await async_client.get("/studio/courses", headers=auth_header(student_token))
        assert resp.status_code == 403

        # Teacher creates a course
        slug = f"course-{uuid.uuid4().hex[:8]}"
        course_payload = {
            "title": "Intro to Aveli",
            "slug": slug,
            "description": "A free introduction",
            "is_free_intro": True,
            "is_published": True,
            "price_amount_cents": 0,
        }
        resp = await async_client.post(
            "/studio/courses",
            json=course_payload,
            headers=auth_header(teacher_token),
        )
        assert resp.status_code == 200, resp.text
        course = resp.json()
        course_id = str(course["id"])

        # Teacher lists courses and sees the new one
        resp = await async_client.get(
            "/studio/courses", headers=auth_header(teacher_token)
        )
        assert resp.status_code == 200
        assert any(str(item["id"]) == course_id for item in resp.json()["items"])

        # Student cannot create lessons for teacher-owned courses.
        resp = await async_client.post(
            "/studio/lessons",
            json={
                "course_id": course_id,
                "title": "Lesson 1",
                "content_markdown": "# Hello",
                "position": 1,
                "is_intro": True,
            },
            headers=auth_header(student_token),
        )
        assert resp.status_code == 403

        # Teacher adds lesson
        resp = await async_client.post(
            "/studio/lessons",
            json={
                "course_id": course_id,
                "title": "Lesson 1",
                "content_markdown": "# Hello",
                "position": 1,
                "is_intro": True,
            },
            headers=auth_header(teacher_token),
        )
        assert resp.status_code == 200, resp.text
        lesson_id = str(resp.json()["id"])

        # Update lesson metadata
        resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            json={"title": "Lesson 1 Updated", "position": 2, "is_intro": False},
            headers=auth_header(teacher_token),
        )
        assert resp.status_code == 200
        assert resp.json()["title"] == "Lesson 1 Updated"

        # Toggle intro flag directly
        resp = await async_client.patch(
            f"/studio/lessons/{lesson_id}/intro",
            json={"is_intro": True},
            headers=auth_header(teacher_token),
        )
        assert resp.status_code == 200

        # Update course metadata
        resp = await async_client.patch(
            f"/studio/courses/{course_id}",
            json={"title": "Intro to Aveli (Updated)"},
            headers=auth_header(teacher_token),
        )
        assert resp.status_code == 200
        assert resp.json()["title"] == "Intro to Aveli (Updated)"

        # Student cannot modify the course
        resp = await async_client.patch(
            f"/studio/courses/{course_id}",
            json={"title": "Hacked"},
            headers=auth_header(student_token),
        )
        assert resp.status_code == 403

        # Ensure quiz exists and manage questions
        resp = await async_client.post(
            f"/studio/courses/{course_id}/quiz",
            headers=auth_header(teacher_token),
        )
        quiz_available = resp.status_code == 200
        if quiz_available:
            quiz_id = str(resp.json()["quiz"]["id"])

            question_payload = {
                "position": 1,
                "kind": "single",
                "prompt": "What is Aveli?",
                "options": {"a": "A platform", "b": "Unknown"},
                "correct": "a",
            }
            resp = await async_client.post(
                f"/studio/quizzes/{quiz_id}/questions",
                json=question_payload,
                headers=auth_header(teacher_token),
            )
            assert resp.status_code == 200, resp.text
            question_id = str(resp.json()["id"])
        else:
            quiz_id = None

        # Teacher uploads lesson media
        resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media",
            headers=auth_header(teacher_token),
            files={"file": ("intro.mp3", b"ID3", "audio/mpeg")},
            data={"is_intro": "false"},
        )
        assert resp.status_code == 200, resp.text
        media = resp.json()
        media_id = str(media["id"])

        # Media listing includes upload
        resp = await async_client.get(
            f"/studio/lessons/{lesson_id}/media",
            headers=auth_header(teacher_token),
        )
        assert resp.status_code == 200
        assert any(item["id"] == media_id for item in resp.json()["items"])

        # Student cannot upload media
        resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media",
            headers=auth_header(student_token),
            files={"file": ("fail.txt", b"no", "text/plain")},
            data={"is_intro": "false"},
        )
        assert resp.status_code == 403

        # Reject unsupported media types
        resp = await async_client.post(
            f"/studio/lessons/{lesson_id}/media",
            headers=auth_header(teacher_token),
            files={"file": ("script.exe", b"MZ", "application/x-msdownload")},
            data={"is_intro": "false"},
        )
        assert resp.status_code == 415

        # Media download works
        resp = await async_client.get(
            f"/studio/media/{media_id}",
            headers=auth_header(teacher_token),
        )
        assert resp.status_code == 200

        # Student views published course and enrollment info
        resp = await async_client.get("/courses", headers=auth_header(student_token))
        assert resp.status_code == 200
        assert any(item["id"] == course_id for item in resp.json()["items"])

        resp = await async_client.get(
            f"/courses/{course_id}/enrollment",
            headers=auth_header(student_token),
        )
        assert resp.status_code == 200
        assert resp.json()["enrolled"] is False

        # Enroll in free intro course
        resp = await async_client.post(
            f"/courses/{course_id}/enroll",
            headers=auth_header(student_token),
        )
        assert resp.status_code == 200
        payload = resp.json()
        assert payload["enrolled"] is True
        assert payload["status"] in {"enrolled", "already_enrolled"}
        assert payload["consumed"] >= 1
        assert payload["limit"] >= payload["consumed"]

        resp = await async_client.get(
            f"/courses/{course_id}/enrollment",
            headers=auth_header(student_token),
        )
        assert resp.status_code == 200
        assert resp.json()["enrolled"] is True

        # Free limit endpoints
        resp = await async_client.get(
            "/courses/free-consumed", headers=auth_header(student_token)
        )
        assert resp.status_code == 200
        free_counts = resp.json()
        assert free_counts["consumed"] >= 1
        assert free_counts["limit"] >= free_counts["consumed"]

        resp = await async_client.get("/courses/config/free-limit")
        assert resp.status_code == 200
        assert "limit" in resp.json()

        # Course detail includes lessons (virtual module for backwards compatibility)
        resp = await async_client.get(
            f"/courses/{course_id}", headers=auth_header(student_token)
        )
        assert resp.status_code == 200
        detail = resp.json()
        assert str(detail["course"]["id"]) == course_id
        assert detail["modules"], "Course lessons should be present"

        # Quiz info available to student
        if quiz_available and quiz_id is not None:
            resp = await async_client.get(
                f"/courses/{course_id}/quiz",
                headers=auth_header(student_token),
            )
            assert resp.status_code == 200
            quiz_info = resp.json()
            assert quiz_info["quiz_id"] == quiz_id

            resp = await async_client.get(
                f"/courses/quiz/{quiz_id}/questions",
                headers=auth_header(student_token),
            )
            assert resp.status_code == 200
            assert len(resp.json()["items"]) == 1
    finally:
        if question_id and quiz_id:
            await async_client.delete(
                f"/studio/quizzes/{quiz_id}/questions/{question_id}",
                headers=auth_header(teacher_token),
            )
        if media_id:
            # Student still blocked from deleting
            resp = await async_client.delete(
                f"/studio/media/{media_id}",
                headers=auth_header(student_token),
            )
            assert resp.status_code == 403

            await async_client.delete(
                f"/studio/media/{media_id}",
                headers=auth_header(teacher_token),
            )
        if lesson_id:
            await async_client.delete(
                f"/studio/lessons/{lesson_id}", headers=auth_header(teacher_token)
            )
        if course_id:
            await async_client.delete(
                f"/studio/courses/{course_id}", headers=auth_header(teacher_token)
            )

        await cleanup_user(student_id)
        await cleanup_user(teacher_id)
