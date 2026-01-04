import uuid

import pytest

from app import db

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def build_context(user_id: str, *, role: str = "teacher", scopes: list[str] | None = None):
    return {
        "context_version": "2025-02-18",
        "schema_version": "2025-02-01",
        "actor": {
            "id": user_id,
            "role": role,
            "scopes": scopes or ["ai:execute"],
        },
    }


async def register_user(async_client):
    email = f"ctx7_{uuid.uuid4().hex[:8]}@example.com"
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Ctx7"},
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
                   SET role_v2 = 'teacher', updated_at = now()
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


async def create_teacher(async_client):
    token, user_id = await register_user(async_client)
    await promote_teacher(user_id)
    return token, user_id


async def test_ai_execute_valid_context(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        payload = {"context": build_context(user_id), "input": "Hello AI"}
        resp = await async_client.post(
            "/api/ai/execute", headers=auth_header(token), json=payload
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["ok"] is True
        assert data["context_version"] == payload["context"]["context_version"]
        assert data["schema_version"] == payload["context"]["schema_version"]
        assert isinstance(data["context_hash"], str)
        assert len(data["context_hash"]) == 64
    finally:
        await cleanup_user(user_id)


async def test_ai_execute_missing_field(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        context = build_context(user_id)
        context.pop("schema_version")
        resp = await async_client.post(
            "/api/ai/execute",
            headers=auth_header(token),
            json={"context": context, "input": "Hello"},
        )
        assert resp.status_code == 400
        assert "schema_version" in resp.json()["detail"]
    finally:
        await cleanup_user(user_id)


async def test_ai_execute_extra_field(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        context = build_context(user_id)
        context["unexpected"] = "boom"
        resp = await async_client.post(
            "/api/ai/execute",
            headers=auth_header(token),
            json={"context": context, "input": "Hello"},
        )
        assert resp.status_code == 400
        assert "unexpected" in resp.json()["detail"] or "Extra inputs" in resp.json()["detail"]
    finally:
        await cleanup_user(user_id)


async def test_ai_execute_permission_mismatch(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        context = build_context("someone-else")
        resp = await async_client.post(
            "/api/ai/execute",
            headers=auth_header(token),
            json={"context": context, "input": "Hello"},
        )
        assert resp.status_code == 403
    finally:
        await cleanup_user(user_id)


async def test_ai_execute_no_context(async_client):
    token, user_id = await create_teacher(async_client)
    try:
        resp = await async_client.post(
            "/api/ai/execute",
            headers=auth_header(token),
            json={"input": "Hello"},
        )
        assert resp.status_code == 400
        assert resp.json()["detail"] == "context is required"
    finally:
        await cleanup_user(user_id)
