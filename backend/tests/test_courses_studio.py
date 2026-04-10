import uuid

import pytest

from app import db
from app.routes import studio as studio_routes


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
                   SET role_v2 = 'teacher',
                       role = 'teacher'
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
                "step": "intro",
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
            },
        )
        assert create_course.status_code == 200, create_course.text
        course = create_course.json()
        course_id = str(course["id"])
        assert course["slug"] == slug
        assert course["step"] == "intro"
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

        student_create_lesson = await async_client.post(
            "/studio/lessons",
            headers=auth_header(student_token),
            json={
                "course_id": course_id,
                "lesson_title": "Lesson 1",
                "content_markdown": "# Hello",
                "position": 1,
            },
        )
        assert student_create_lesson.status_code == 403, student_create_lesson.text

        create_lesson = await async_client.post(
            "/studio/lessons",
            headers=auth_header(teacher_token),
            json={
                "course_id": course_id,
                "lesson_title": "Lesson 1",
                "content_markdown": "# Hello",
                "position": 1,
            },
        )
        assert create_lesson.status_code == 200, create_lesson.text
        lesson_id = str(create_lesson.json()["id"])
        assert create_lesson.json()["lesson_title"] == "Lesson 1"

        list_lessons = await async_client.get(
            f"/studio/courses/{course_id}/lessons",
            headers=auth_header(teacher_token),
        )
        assert list_lessons.status_code == 200, list_lessons.text
        assert any(str(item["id"]) == lesson_id for item in list_lessons.json()["items"])

        update_lesson = await async_client.patch(
            f"/studio/lessons/{lesson_id}",
            headers=auth_header(teacher_token),
            json={
                "lesson_title": "Lesson 1 Updated",
                "position": 2,
            },
        )
        assert update_lesson.status_code == 200, update_lesson.text
        assert update_lesson.json()["lesson_title"] == "Lesson 1 Updated"
        assert update_lesson.json()["position"] == 2

        legacy_upload = await async_client.post(
            f"/studio/lessons/{lesson_id}/media",
            headers=auth_header(teacher_token),
            files={"file": ("intro.mp3", b"ID3", "audio/mpeg")},
        )
        assert legacy_upload.status_code == 410, legacy_upload.text
        assert legacy_upload.json()["detail"] == "Legacy lesson upload is disabled"
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
        await cleanup_user(student_id)
        await cleanup_user(teacher_id)


async def test_studio_quiz_endpoints_remain_mounted_and_teacher_scoped(
    async_client,
    monkeypatch,
):
    teacher_email = f"quiz_teacher_{uuid.uuid4().hex[:8]}@example.com"
    student_email = f"quiz_student_{uuid.uuid4().hex[:8]}@example.com"
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

    course_id = str(uuid.uuid4())
    quiz_id = str(uuid.uuid4())
    question_id = str(uuid.uuid4())
    recorded_payloads: list[dict] = []

    try:
        async def fake_is_course_owner(candidate_user_id: str, candidate_course_id: str) -> bool:
            assert candidate_user_id == teacher_id
            assert candidate_course_id == course_id
            return True

        async def fake_ensure_quiz_for_user(candidate_course_id: str, candidate_user_id: str):
            assert candidate_course_id == course_id
            assert candidate_user_id == teacher_id
            return {
                "id": quiz_id,
                "course_id": course_id,
                "title": "Quiz",
                "pass_score": 80,
            }

        async def fake_quiz_belongs_to_user(candidate_quiz_id: str, candidate_user_id: str) -> bool:
            assert candidate_quiz_id == quiz_id
            if candidate_user_id == teacher_id:
                return True
            if candidate_user_id == student_id:
                return False
            raise AssertionError(f"unexpected user_id {candidate_user_id}")

        async def fake_quiz_questions(candidate_quiz_id: str):
            assert candidate_quiz_id == quiz_id
            return [
                {
                    "id": question_id,
                    "quiz_id": quiz_id,
                    "position": 1,
                    "kind": "single",
                    "prompt": "Question",
                    "options": {"a": "Answer"},
                    "correct": "a",
                }
            ]

        async def fake_upsert_quiz_question(candidate_quiz_id: str, data: dict):
            assert candidate_quiz_id == quiz_id
            recorded_payloads.append(dict(data))
            return {
                "id": str(data.get("id") or question_id),
                "quiz_id": quiz_id,
                "position": int(data.get("position") or 1),
                "kind": data.get("kind") or "single",
                "prompt": data.get("prompt") or "Question",
                "options": data.get("options") or {"a": "Answer"},
                "correct": data.get("correct") or "a",
            }

        async def fake_delete_quiz_question(candidate_question_id: str) -> bool:
            assert candidate_question_id == question_id
            return True

        monkeypatch.setattr(
            studio_routes.models,
            "is_course_owner",
            fake_is_course_owner,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.models,
            "ensure_quiz_for_user",
            fake_ensure_quiz_for_user,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.models,
            "quiz_belongs_to_user",
            fake_quiz_belongs_to_user,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.models,
            "quiz_questions",
            fake_quiz_questions,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.models,
            "upsert_quiz_question",
            fake_upsert_quiz_question,
            raising=True,
        )
        monkeypatch.setattr(
            studio_routes.models,
            "delete_quiz_question",
            fake_delete_quiz_question,
            raising=True,
        )

        student_quiz = await async_client.post(
            f"/studio/courses/{course_id}/quiz",
            headers=auth_header(student_token),
        )
        assert student_quiz.status_code == 403, student_quiz.text

        ensure_quiz = await async_client.post(
            f"/studio/courses/{course_id}/quiz",
            headers=auth_header(teacher_token),
        )
        assert ensure_quiz.status_code == 200, ensure_quiz.text
        quiz_id = str(ensure_quiz.json()["quiz"]["id"])

        create_question = await async_client.post(
            f"/studio/quizzes/{quiz_id}/questions",
            headers=auth_header(teacher_token),
            json={
                "position": 1,
                "kind": "single",
                "prompt": "What is Aveli?",
                "options": {"a": "A platform", "b": "Unknown"},
                "correct": "a",
            },
        )
        assert create_question.status_code == 200, create_question.text
        assert create_question.json()["id"] == question_id

        student_questions = await async_client.get(
            f"/studio/quizzes/{quiz_id}/questions",
            headers=auth_header(student_token),
        )
        assert student_questions.status_code == 403, student_questions.text

        teacher_questions = await async_client.get(
            f"/studio/quizzes/{quiz_id}/questions",
            headers=auth_header(teacher_token),
        )
        assert teacher_questions.status_code == 200, teacher_questions.text
        assert len(teacher_questions.json()["items"]) == 1

        update_question = await async_client.put(
            f"/studio/quizzes/{quiz_id}/questions/{question_id}",
            headers=auth_header(teacher_token),
            json={
                "position": 2,
                "kind": "single",
                "prompt": "Updated prompt",
                "options": {"a": "A platform", "b": "Unknown"},
                "correct": "a",
            },
        )
        assert update_question.status_code == 200, update_question.text
        assert update_question.json()["prompt"] == "Updated prompt"
        assert update_question.json()["position"] == 2
        assert recorded_payloads[0]["prompt"] == "What is Aveli?"
        assert recorded_payloads[1]["id"] == question_id
    finally:
        if question_id and quiz_id:
            await async_client.delete(
                f"/studio/quizzes/{quiz_id}/questions/{question_id}",
                headers=auth_header(teacher_token),
            )
        await cleanup_user(student_id)
        await cleanup_user(teacher_id)
