import uuid

import pytest

from app import db

from .test_context_builder import auth_header, cleanup_course, cleanup_user, create_course, create_teacher, register_user

pytestmark = pytest.mark.anyio("asyncio")


async def promote_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.profiles
                   SET role_v2 = 'user', role = 'student'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def test_tool_call_allowed(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "Call tool",
                "course_id": course_id,
                "tool": "supabase_readonly",
                "action": "query",
                "args": {"select": "*"},
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["ok"] is True
        assert body["context_hash"]
        assert body["result"]["stub"] is True
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_tool_call_disallowed_tool(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "Call tool",
                "course_id": course_id,
                "tool": "forbidden_tool",
                "action": "query",
                "args": {},
            },
        )
        assert resp.status_code == 403
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_tool_call_user_without_scope(async_client):
    teacher_token, teacher_id = await create_teacher(async_client)
    student_token, student_id = await register_user(async_client)
    course_id = None
    try:
        await promote_user(student_id)
        course_id = await create_course(async_client, teacher_token)
        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(student_token),
            json={
                "input": "Call tool",
                "course_id": course_id,
                "tool": "supabase_readonly",
                "action": "query",
                "args": {},
            },
        )
        assert resp.status_code == 403
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(student_id)
        await cleanup_user(teacher_id)


async def test_tool_call_missing_ids(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "Call tool",
                "tool": "supabase_readonly",
                "action": "query",
                "args": {},
            },
        )
        assert resp.status_code == 400
    finally:
        await cleanup_user(user_id)
