import os

import pytest

from app import db
from app.services import context7_builder

from .test_context_builder import (
    auth_header,
    cleanup_course,
    cleanup_user,
    create_course,
    create_teacher,
    register_user,
)

pytestmark = pytest.mark.anyio("asyncio")


async def promote_admin(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.profiles
                   SET is_admin = true
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def enroll_user(course_id: str, user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.enrollments (user_id, course_id, source)
                VALUES (%s, %s, 'purchase') ON CONFLICT DO NOTHING
                """,
                (user_id, course_id),
            )
            await conn.commit()


async def test_plan_execute_v1_missing_required_ids(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        resp = await async_client.post(
            "/api/ai/plan-and-execute-v1",
            headers=auth_header(token),
            json={"input": "list students"},
        )
        assert resp.status_code == 400
    finally:
        await cleanup_user(user_id)


async def test_plan_execute_v1_unknown_intent(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/plan-and-execute-v1",
            headers=auth_header(token),
            json={"input": "do something else", "course_id": course_id},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["ok"] is False
        assert "supported_intents" in body
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_plan_execute_v1_list_students(async_client):
    if not os.environ.get("SUPABASE_DB_URL"):
        pytest.skip("SUPABASE_DB_URL missing")
    teacher_token, teacher_id = await create_teacher(async_client)
    student_token, student_id = await register_user(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, teacher_token)
        await enroll_user(course_id, student_id)

        resp = await async_client.post(
            "/api/ai/plan-and-execute-v1",
            headers=auth_header(teacher_token),
            json={
                "input": "list students",
                "course_id": course_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["ok"] is True
        assert body["intent"] == "list_course_students"
        assert body["steps"]
        assert any(str(row["user_id"]) == str(student_id) for row in body["final"]["rows"])
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(student_id)
        await cleanup_user(teacher_id)


async def test_plan_execute_v1_user_summary(async_client):
    if not os.environ.get("SUPABASE_DB_URL"):
        pytest.skip("SUPABASE_DB_URL missing")
    admin_token, admin_id = await register_user(async_client)
    await promote_admin(admin_id)
    course_creator_token, course_creator_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, course_creator_token)
        target_token, target_id = await register_user(async_client)

        resp = await async_client.post(
            "/api/ai/plan-and-execute-v1",
            headers=auth_header(admin_token),
            json={
                "input": "user summary",
                "course_id": course_id,
                "user_id": target_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["ok"] is True
        assert body["intent"] == "get_user_summary"
        assert body["final"]["row_count"] == 1
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(course_creator_id)
        await cleanup_user(admin_id)
        await cleanup_user(target_id)


async def test_plan_execute_v1_enforces_tools_allowed(async_client, monkeypatch):
    def restricted_policy(role: str):  # noqa: ANN001
        return {
            "mode": "stub",
            "tools_allowed": [],
            "write_allowed": False,
            "max_steps": 5,
            "max_seconds": 60,
            "redact_logs": True,
        }

    monkeypatch.setattr(context7_builder, "_default_execution_policy", restricted_policy)

    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/plan-and-execute-v1",
            headers=auth_header(token),
            json={
                "input": "list students",
                "course_id": course_id,
            },
        )
        assert resp.status_code == 403
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)
