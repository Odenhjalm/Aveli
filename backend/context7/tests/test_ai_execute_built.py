import uuid

import pytest

from app import repositories
from app.services import context7_builder

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


async def test_execute_built_missing_ids(async_client):
    token, user_id = await register_user(async_client)
    try:
        resp = await async_client.post(
            "/api/ai/execute-built",
            headers=auth_header(token),
            json={"input": "Hello AI"},
        )
        assert resp.status_code == 400
    finally:
        await cleanup_user(user_id)


async def test_execute_built_invalid_schema(async_client):
    token, user_id = await register_user(async_client)
    try:
        resp = await async_client.post(
            "/api/ai/execute-built",
            headers=auth_header(token),
            json={
                "input": "Hello AI",
                "course_id": str(uuid.uuid4()),
                "unexpected": "boom",
            },
        )
        assert resp.status_code == 400
        detail = resp.json().get("detail")
        detail_text = str(detail)
        assert "unexpected" in detail_text or "extra fields" in detail_text
    finally:
        await cleanup_user(user_id)


async def test_execute_built_forbidden_without_scope(async_client):
    teacher_token, teacher_id = await create_teacher(async_client)
    student_token, student_id = await register_user(async_client)
    seminar_id = None
    try:
        seminar_id = await create_seminar(async_client, teacher_token)
        await repositories.register_attendee(
            seminar_id=seminar_id,
            user_id=student_id,
            role="participant",
            invite_status="accepted",
        )

        resp = await async_client.post(
            "/api/ai/execute-built",
            headers=auth_header(student_token),
            json={"input": "Hello AI", "seminar_id": seminar_id},
        )
        assert resp.status_code == 403
    finally:
        if seminar_id:
            await cleanup_seminar(seminar_id)
        await cleanup_user(teacher_id)
        await cleanup_user(student_id)


async def test_execute_built_ok_for_teacher(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/ai/execute-built",
            headers=auth_header(token),
            json={"input": "Hello AI", "course_id": course_id},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["ok"] is True
        assert data["context_hash"]
        assert data["built_from"]["course_id"] == course_id
        assert data["context_version"]
        assert data["schema_version"]
        policy = data.get("policy")
        assert policy
        assert policy["mode"] == "stub"
        assert policy["max_steps"] > 0
        assert policy["max_seconds"] > 0
        assert policy["write_allowed"] is False
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_execute_built_rejects_non_stub_mode(monkeypatch, async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)

        original_policy = context7_builder._default_execution_policy

        def _unsafe_policy(role: str):
            policy = dict(original_policy(role))
            policy["mode"] = "live"
            return policy

        monkeypatch.setattr(context7_builder, "_default_execution_policy", _unsafe_policy)

        resp = await async_client.post(
            "/api/ai/execute-built",
            headers=auth_header(token),
            json={"input": "Hello AI", "course_id": course_id},
        )
        assert resp.status_code == 400
        assert "mode" in resp.json().get("detail", "")
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_execute_built_hash_stable(monkeypatch, async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        monkeypatch.setattr(
            context7_builder,
            "_utc_timestamp",
            lambda: "2025-01-01T00:00:00Z",
        )

        payload = {"input": "Hello AI", "course_id": course_id}
        resp1 = await async_client.post(
            "/api/ai/execute-built",
            headers=auth_header(token),
            json=payload,
        )
        resp2 = await async_client.post(
            "/api/ai/execute-built",
            headers=auth_header(token),
            json=payload,
        )

        assert resp1.status_code == 200, resp1.text
        assert resp2.status_code == 200, resp2.text
        assert resp1.json()["context_hash"] == resp2.json()["context_hash"]
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)
