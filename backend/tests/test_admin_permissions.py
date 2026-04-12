import uuid

import pytest

from app import db
from app.repositories import memberships as memberships_repo

from .utils import (
    auth_header,
    ensure_admin_user,
    fetch_auth_subject,
    register_auth_user,
)


pytestmark = pytest.mark.anyio("asyncio")


async def _event_types_for(user_id: str) -> list[str]:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT event_type
                  FROM app.auth_events
                 WHERE subject_user_id = %s
                 ORDER BY created_at ASC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()
    return [str(row[0]) for row in rows]


async def _grant_app_entry(async_client, user: dict[str, str]) -> None:
    onboarding_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )
    assert onboarding_resp.status_code == 200, onboarding_resp.text
    await memberships_repo.upsert_membership_record(
        user["user_id"],
        status="active",
        source="test",
    )


async def test_teacher_role_routes_require_admin_and_mutate_canonical_authority(
    async_client,
):
    password = "Passw0rd!"
    non_admin_user = await register_auth_user(
        async_client,
        email=f"non_admin_{uuid.uuid4().hex[:8]}@example.com",
        password=password,
        display_name="Non Admin",
    )
    admin_user = await ensure_admin_user(
        async_client,
        password=password,
        display_name="Admin",
    )
    target_user = await register_auth_user(
        async_client,
        email=f"teacher_target_{uuid.uuid4().hex[:8]}@example.com",
        password=password,
        display_name="Teacher Target",
    )
    await _grant_app_entry(async_client, non_admin_user)
    await _grant_app_entry(async_client, admin_user)

    forbidden_resp = await async_client.post(
        f"/admin/users/{target_user['user_id']}/grant-teacher-role",
        headers=auth_header(non_admin_user["access_token"]),
    )
    assert forbidden_resp.status_code == 403, forbidden_resp.text
    assert forbidden_resp.json() == {
        "status": "error",
        "error_code": "admin_required",
        "message": "Adminbehorighet kravs for den har atgarden.",
    }

    grant_resp = await async_client.post(
        f"/admin/users/{target_user['user_id']}/grant-teacher-role",
        headers=auth_header(admin_user["access_token"]),
    )
    assert grant_resp.status_code == 204, grant_resp.text
    assert grant_resp.content == b""

    subject_after_grant = await fetch_auth_subject(target_user["user_id"])
    assert subject_after_grant == {
        "onboarding_state": "incomplete",
        "role_v2": "teacher",
        "role": "teacher",
        "is_admin": False,
    }

    revoked_refresh = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": target_user["refresh_token"]},
    )
    assert revoked_refresh.status_code == 401, revoked_refresh.text
    assert revoked_refresh.json() == {
        "status": "error",
        "error_code": "refresh_token_invalid",
        "message": "Ogiltig uppdateringstoken.",
    }

    target_login = await async_client.post(
        "/auth/login",
        json={
            "email": target_user["email"],
            "password": target_user["password"],
        },
    )
    assert target_login.status_code == 200, target_login.text
    refreshed_target_tokens = target_login.json()

    revoke_resp = await async_client.post(
        f"/admin/users/{target_user['user_id']}/revoke-teacher-role",
        headers=auth_header(admin_user["access_token"]),
    )
    assert revoke_resp.status_code == 204, revoke_resp.text
    assert revoke_resp.content == b""

    subject_after_revoke = await fetch_auth_subject(target_user["user_id"])
    assert subject_after_revoke == {
        "onboarding_state": "incomplete",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }

    revoked_again = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": refreshed_target_tokens["refresh_token"]},
    )
    assert revoked_again.status_code == 401, revoked_again.text
    assert revoked_again.json() == {
        "status": "error",
        "error_code": "refresh_token_invalid",
        "message": "Ogiltig uppdateringstoken.",
    }

    assert await _event_types_for(target_user["user_id"]) == [
        "teacher_role_granted",
        "teacher_role_revoked",
    ]
