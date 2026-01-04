import uuid

import pytest

from app import db
from context7.runtime import validate_context

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(async_client):
    email = f"ctx7b_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Ctx7 Builder"},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()

    profile_resp = await async_client.get(
        "/profiles/me", headers=auth_header(tokens["access_token"])
    )
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    return tokens["access_token"], user_id


async def promote_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.profiles
                   SET role_v2 = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def cleanup_course(course_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.courses WHERE id = %s", (course_id,))
            await conn.commit()


async def cleanup_seminar(seminar_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.seminars WHERE id = %s", (seminar_id,))
            await cur.execute("DELETE FROM app.seminar_attendees WHERE seminar_id = %s", (seminar_id,))
            await cur.execute("DELETE FROM app.seminar_sessions WHERE seminar_id = %s", (seminar_id,))
            await conn.commit()


async def create_teacher(async_client):
    token, user_id = await register_user(async_client)
    await promote_teacher(user_id)
    return token, user_id


async def create_course(async_client, token: str) -> str:
    slug = f"ctx7-{uuid.uuid4().hex[:6]}"
    resp = await async_client.post(
        "/studio/courses",
        headers=auth_header(token),
        json={"title": "Ctx7 Course", "slug": slug, "description": "Ctx7 builder"},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    return str(data["id"])


async def create_seminar(async_client, token: str) -> str:
    resp = await async_client.post(
        "/studio/seminars",
        headers=auth_header(token),
        json={"title": "Ctx7 Seminar"},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    return str(data["id"])


async def test_context_build_missing_ids(async_client):
    token, user_id = await register_user(async_client)
    try:
        resp = await async_client.post(
            "/api/context7/build", headers=auth_header(token), json={}
        )
        assert resp.status_code == 400
    finally:
        await cleanup_user(user_id)


async def test_context_build_course_not_found(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        resp = await async_client.post(
            "/api/context7/build",
            headers=auth_header(token),
            json={"course_id": str(uuid.uuid4())},
        )
        assert resp.status_code == 404
    finally:
        await cleanup_user(user_id)


async def test_context_build_unauthorized_course(async_client):
    teacher_token, teacher_id = await create_teacher(async_client)
    student_token, student_id = await register_user(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, teacher_token)
        resp = await async_client.post(
            "/api/context7/build",
            headers=auth_header(student_token),
            json={"course_id": course_id},
        )
        assert resp.status_code == 403
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(teacher_id)
        await cleanup_user(student_id)


async def test_context_build_valid_teacher_course(async_client):
    token, user_id = await create_teacher(async_client)
    course_id = None
    try:
        course_id = await create_course(async_client, token)
        resp = await async_client.post(
            "/api/context7/build",
            headers=auth_header(token),
            json={"course_id": course_id},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["context_hash"]
        ctx_payload = data["context"]
        ctx, computed_hash = validate_context(
            ctx_payload,
            user_id=user_id,
            user_role="teacher",
            required_scope="ai:execute",
            allowed_roles={"admin", "teacher", "student"},
        )
        assert computed_hash == data["context_hash"]
        assert ctx.scope and ctx.scope.course_id == course_id
    finally:
        if course_id:
            await cleanup_course(course_id)
        await cleanup_user(user_id)


async def test_context_build_seminar_unauthorized(async_client):
    host_token, host_id = await create_teacher(async_client)
    attendee_token, attendee_id = await register_user(async_client)
    seminar_id = None
    try:
        seminar_id = await create_seminar(async_client, host_token)
        resp = await async_client.post(
            "/api/context7/build",
            headers=auth_header(attendee_token),
            json={"seminar_id": seminar_id},
        )
        assert resp.status_code == 403
    finally:
        if seminar_id:
            await cleanup_seminar(seminar_id)
        await cleanup_user(host_id)
        await cleanup_user(attendee_id)
