import uuid

import pytest

from app import db

pytestmark = pytest.mark.anyio('asyncio')


def _auth_header(token: str) -> dict[str, str]:
    return {'Authorization': f'Bearer {token}'}


async def _register(async_client, email: str, password: str, display_name: str):
    resp = await async_client.post(
        '/auth/register',
        json={'email': email, 'password': password, 'display_name': display_name},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _promote_teacher(user_id: str):
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


async def _cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute('DELETE FROM auth.users WHERE id = %s', (user_id,))
            await conn.commit()


async def test_studio_courses_requires_teacher(async_client):
    email = f"studio_{uuid.uuid4().hex[:6]}@example.com"
    password = 'Passw0rd!'
    tokens = await _register(async_client, email, password, 'Studio User')
    user_id = None

    try:
        resp = await async_client.get(
            '/studio/courses', headers=_auth_header(tokens['access_token'])
        )
        assert resp.status_code == 403

        profile_resp = await async_client.get(
            '/profiles/me', headers=_auth_header(tokens['access_token'])
        )
        user_id = str(profile_resp.json()['user_id'])
        await _promote_teacher(user_id)

        resp_after = await async_client.get(
            '/studio/courses', headers=_auth_header(tokens['access_token'])
        )
        assert resp_after.status_code == 200
    finally:
        if user_id:
            await _cleanup_user(user_id)
