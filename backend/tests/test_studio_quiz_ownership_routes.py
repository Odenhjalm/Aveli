from __future__ import annotations

from datetime import datetime, timezone
import uuid

import pytest

from app import db
from app.routes import studio as studio_routes


pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(
    client,
    email: str,
    password: str,
    display_name: str,
) -> tuple[str, str]:
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

    me_resp = await client.get("/profiles/me", headers=auth_header(token))
    assert me_resp.status_code == 200, me_resp.text
    user_id = str(me_resp.json()["user_id"])
    return token, user_id


async def promote_to_teacher(user_id: str) -> None:
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


async def test_studio_quiz_routes_remain_functional_with_canonical_ownership(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client,
        f"quiz_owner_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    course_id = str(uuid.uuid4())
    quiz_id = str(uuid.uuid4())
    question_id = str(uuid.uuid4())
    recorded_payloads: list[dict] = []

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
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

    async def fake_quiz_belongs_to_user(candidate_quiz_id: str, candidate_user_id: str) -> bool:
        assert candidate_quiz_id == quiz_id
        assert candidate_user_id == teacher_id
        return True

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

    monkeypatch.setattr(studio_routes.models, "is_course_owner", fake_is_course_owner, raising=True)
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
    monkeypatch.setattr(studio_routes.models, "quiz_questions", fake_quiz_questions, raising=True)
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

    ensure_resp = await async_client.post(
        f"/studio/courses/{course_id}/quiz",
        headers=auth_header(teacher_token),
    )
    assert ensure_resp.status_code == 200, ensure_resp.text
    assert ensure_resp.json()["quiz"]["id"] == quiz_id

    list_resp = await async_client.get(
        f"/studio/quizzes/{quiz_id}/questions",
        headers=auth_header(teacher_token),
    )
    assert list_resp.status_code == 200, list_resp.text
    assert list_resp.json()["items"][0]["id"] == question_id

    create_resp = await async_client.post(
        f"/studio/quizzes/{quiz_id}/questions",
        headers=auth_header(teacher_token),
        json={
            "position": 1,
            "kind": "single",
            "prompt": "Created",
            "options": {"a": "Answer"},
            "correct": "a",
        },
    )
    assert create_resp.status_code == 200, create_resp.text
    assert create_resp.json()["quiz_id"] == quiz_id

    update_resp = await async_client.put(
        f"/studio/quizzes/{quiz_id}/questions/{question_id}",
        headers=auth_header(teacher_token),
        json={
            "position": 2,
            "kind": "single",
            "prompt": "Updated",
            "options": {"a": "Answer"},
            "correct": "a",
        },
    )
    assert update_resp.status_code == 200, update_resp.text
    assert update_resp.json()["id"] == question_id

    delete_resp = await async_client.delete(
        f"/studio/quizzes/{quiz_id}/questions/{question_id}",
        headers=auth_header(teacher_token),
    )
    assert delete_resp.status_code == 200, delete_resp.text
    assert delete_resp.json() == {"deleted": True}

    assert recorded_payloads[0]["prompt"] == "Created"
    assert recorded_payloads[1]["id"] == question_id
    assert recorded_payloads[1]["prompt"] == "Updated"


async def test_studio_quiz_questions_reject_non_owner(async_client, monkeypatch):
    password = "Passw0rd!"
    teacher_token, teacher_id = await register_user(
        async_client,
        f"quiz_guard_{uuid.uuid4().hex[:6]}@example.org",
        password,
        "Teacher",
    )
    await promote_to_teacher(teacher_id)

    quiz_id = str(uuid.uuid4())

    async def fake_quiz_belongs_to_user(candidate_quiz_id: str, candidate_user_id: str) -> bool:
        assert candidate_quiz_id == quiz_id
        assert candidate_user_id == teacher_id
        return False

    monkeypatch.setattr(
        studio_routes.models,
        "quiz_belongs_to_user",
        fake_quiz_belongs_to_user,
        raising=True,
    )

    resp = await async_client.get(
        f"/studio/quizzes/{quiz_id}/questions",
        headers=auth_header(teacher_token),
    )
    assert resp.status_code == 403, resp.text
    assert resp.json()["detail"] == "Not quiz owner"
