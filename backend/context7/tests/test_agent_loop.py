import pytest

from app.services import context7_builder

from .test_context_builder import auth_header, cleanup_course, cleanup_user, create_course, create_teacher

pytestmark = pytest.mark.anyio("asyncio")


async def test_plan_execute_max_steps_enforced(async_client, monkeypatch):
    def tiny_policy(role: str):  # noqa: ANN001
        return {
            "mode": "stub",
            "tools_allowed": ["supabase_readonly"],
            "write_allowed": False,
            "max_steps": 0,
            "max_seconds": 60,
            "redact_logs": True,
        }

    monkeypatch.setattr(context7_builder, "_default_execution_policy", tiny_policy)

    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/plan-and-execute",
            headers=auth_header(token),
            json={
                "input": "select something",
                "course_id": course_id,
                "args": {"sql": "select 1"},
            },
        )
        assert resp.status_code == 400
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_plan_execute_tool_not_allowed(async_client, monkeypatch):
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
            "/api/ai/plan-and-execute",
            headers=auth_header(token),
            json={
                "input": "select something",
                "course_id": course_id,
                "args": {"sql": "select 1"},
            },
        )
        assert resp.status_code == 403
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_plan_execute_successful_query(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/plan-and-execute",
            headers=auth_header(token),
            json={
                "input": "select one",
                "course_id": course_id,
                "args": {"sql": "select 1 as one"},
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["ok"] is True
        assert body["context_hash"]
        assert body["steps"][0]["tool"] == "supabase_readonly"
        assert body["final"]["row_count"] == 1
        assert body["final"]["rows"][0]["one"] == 1
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_plan_execute_rejects_invalid_sql(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/plan-and-execute",
            headers=auth_header(token),
            json={
                "input": "select attempt",
                "course_id": course_id,
                "args": {"sql": "delete from app.profiles"},
            },
        )
        assert resp.status_code == 400
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)
