import pytest

from app import db
from app.services import tool_dispatcher

from .test_context_builder import (
    auth_header,
    cleanup_course,
    cleanup_seminar,
    cleanup_user,
    create_course,
    create_seminar,
    create_teacher,
    register_user,
)

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
                "args": {"sql": "select 1 as one"},
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["ok"] is True
        assert body["context_hash"]
        assert body["result"]["stub"] is False
        assert body["result"]["row_count"] == 1
        assert body["result"]["rows"][0]["one"] == 1
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
                "args": {"sql": "select 1"},
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
                "args": {"sql": "select 1"},
            },
        )
        assert resp.status_code == 400
    finally:
        await cleanup_user(user_id)


async def test_tool_call_rejects_write_sql(async_client):
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
                "args": {"sql": "delete from app.profiles"},
            },
        )
        assert resp.status_code == 400
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


def test_supabase_readonly_sets_read_only_options(monkeypatch):
    captured: dict[str, object] = {}

    class DummyCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql: str):  # noqa: ANN001
            captured["sql"] = sql

        def fetchmany(self, size: int):  # noqa: ANN001
            captured["fetch_size"] = size
            return []

    class DummyConn:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def cursor(self, row_factory=None):  # noqa: ANN001
            captured["row_factory"] = row_factory
            return DummyCursor()

    def fake_connect(dsn, options=None):  # noqa: ANN001
        captured["dsn"] = dsn
        captured["options"] = options
        return DummyConn()

    monkeypatch.setenv("SUPABASE_DB_URL", "postgres://example")
    monkeypatch.setattr(tool_dispatcher.psycopg, "connect", fake_connect)

    result = tool_dispatcher.dispatch_tool_action(
        tool="supabase_readonly",
        action="query",
        args={"sql": "select 1"},
    )

    assert captured["options"] == tool_dispatcher._READONLY_OPTIONS
    assert captured["row_factory"] == tool_dispatcher.psycopg.rows.dict_row
    assert result["row_count"] == 0
    assert result["truncated"] is False


async def test_tool_call_list_intro_courses_wrapper(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        patch = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(token),
            json={"is_free_intro": True, "is_published": True},
        )
        assert patch.status_code == 200, patch.text

        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "list intro",
                "course_id": course_id,
                "tool": "supabase_readonly",
                "action": "list_intro_courses",
                "args": {"limit": 10},
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()["result"]
        assert body["stub"] is False
        assert isinstance(body["rows"], list)
        assert body["row_count"] >= 1
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_tool_call_get_course_by_id_wrapper(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        patch = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(token),
            json={"is_free_intro": True, "is_published": True},
        )
        assert patch.status_code == 200, patch.text

        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "get course",
                "course_id": course_id,
                "tool": "supabase_readonly",
                "action": "get_course_by_id",
                "args": {"course_id": course_id},
            },
        )
        assert resp.status_code == 200, resp.text
        result = resp.json()["result"]
        assert result["row_count"] == 1
        assert str(result["rows"][0]["id"]) == str(course_id)
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_tool_call_get_course_by_slug_wrapper(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        patch = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=auth_header(token),
            json={"is_free_intro": True, "is_published": True},
        )
        assert patch.status_code == 200, patch.text

        meta = await async_client.get(
            f"/studio/courses/{course_id}", headers=auth_header(token)
        )
        assert meta.status_code == 200, meta.text
        slug = meta.json()["slug"]

        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "get course",
                "course_id": course_id,
                "tool": "supabase_readonly",
                "action": "get_course_by_slug",
                "args": {"slug": slug},
            },
        )
        assert resp.status_code == 200, resp.text
        result = resp.json()["result"]
        assert result["row_count"] == 1
        assert result["rows"][0]["slug"] == slug
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_tool_call_list_seminars_wrapper(async_client):
    token, user_id = await create_teacher(async_client)
    seminar_id = None
    try:
        seminar_id = await create_seminar(async_client, token)
        publish = await async_client.post(
            f"/studio/seminars/{seminar_id}/publish",
            headers=auth_header(token),
        )
        assert publish.status_code == 200, publish.text

        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "list seminars",
                "course_id": None,
                "seminar_id": seminar_id,
                "tool": "supabase_readonly",
                "action": "list_seminars",
                "args": {"limit": 5},
            },
        )
        assert resp.status_code == 200, resp.text
        result = resp.json()["result"]
        assert result["stub"] is False
        assert isinstance(result["rows"], list)
        assert result["row_count"] >= 1
        assert any(str(row["id"]) == str(seminar_id) for row in result["rows"])
    finally:
        if seminar_id:
            await cleanup_seminar(seminar_id)
        await cleanup_user(user_id)


async def test_tool_call_invalid_args_wrapper(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/tool-call",
            headers=auth_header(token),
            json={
                "input": "bad args",
                "course_id": course_id,
                "tool": "supabase_readonly",
                "action": "get_course_by_id",
                "args": {},
            },
        )
        assert resp.status_code == 400
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)
