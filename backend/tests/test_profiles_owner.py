import uuid

import pytest

from app import db

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register(async_client, email: str, password: str, display_name: str):
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": display_name},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    return tokens


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def promote_to_admin(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.profiles
                   SET is_admin = true,
                       role_v2 = COALESCE(role_v2, 'user'),
                       updated_at = now()
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def test_profiles_me_limits_to_owner(async_client):
    password = "Passw0rd!"
    tokens_a = await register(async_client, f"owner_{uuid.uuid4().hex[:6]}@example.com", password, "Owner")
    tokens_b = await register(async_client, f"intruder_{uuid.uuid4().hex[:6]}@example.com", password, "Intruder")
    user_a_id = None
    user_b_id = None

    try:
        profile_a = await async_client.get(
            "/profiles/me", headers=auth_header(tokens_a["access_token"])
        )
        assert profile_a.status_code == 200
        user_a_id = str(profile_a.json()["user_id"])

        profile_b = await async_client.get(
            "/profiles/me", headers=auth_header(tokens_b["access_token"])
        )
        assert profile_b.status_code == 200
        user_b_id = str(profile_b.json()["user_id"])

        assert user_a_id != user_b_id

        patch_body = {"display_name": "Owner Updated"}
        patch_resp = await async_client.patch(
            "/profiles/me", headers=auth_header(tokens_a["access_token"]), json=patch_body
        )
        assert patch_resp.status_code == 200, patch_resp.text
        assert patch_resp.json()["display_name"] == "Owner Updated"

        profile_a_after = await async_client.get(
            "/profiles/me", headers=auth_header(tokens_a["access_token"])
        )
        assert profile_a_after.json()["display_name"] == "Owner Updated"

        profile_b_after = await async_client.get(
            "/profiles/me", headers=auth_header(tokens_b["access_token"])
        )
        assert profile_b_after.json()["display_name"] != "Owner Updated"
    finally:
        if user_a_id:
            await cleanup_user(user_a_id)
        if user_b_id:
            await cleanup_user(user_b_id)


async def test_profile_certificates_require_owner_or_admin(async_client):
    password = "Passw0rd!"
    tokens_owner = await register(
        async_client,
        f"owner_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Owner",
    )
    tokens_other = await register(
        async_client,
        f"other_{uuid.uuid4().hex[:6]}@example.com",
        password,
        "Other",
    )

    owner_id = None
    other_id = None
    try:
        owner_profile = await async_client.get(
            "/profiles/me", headers=auth_header(tokens_owner["access_token"])
        )
        assert owner_profile.status_code == 200, owner_profile.text
        owner_id = str(owner_profile.json()["user_id"])

        other_profile = await async_client.get(
            "/profiles/me", headers=auth_header(tokens_other["access_token"])
        )
        assert other_profile.status_code == 200, other_profile.text
        other_id = str(other_profile.json()["user_id"])

        ok_resp = await async_client.get(
            f"/profiles/{owner_id}/certificates",
            headers=auth_header(tokens_owner["access_token"]),
        )
        assert ok_resp.status_code == 200, ok_resp.text
        assert "items" in ok_resp.json()

        forbidden_resp = await async_client.get(
            f"/profiles/{owner_id}/certificates",
            headers=auth_header(tokens_other["access_token"]),
        )
        assert forbidden_resp.status_code == 403, forbidden_resp.text

        await promote_to_admin(other_id)
        admin_resp = await async_client.get(
            f"/profiles/{owner_id}/certificates",
            headers=auth_header(tokens_other["access_token"]),
        )
        assert admin_resp.status_code == 200, admin_resp.text
        assert "items" in admin_resp.json()
    finally:
        if owner_id:
            await cleanup_user(owner_id)
        if other_id:
            await cleanup_user(other_id)
