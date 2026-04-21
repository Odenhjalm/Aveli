import pytest
from pathlib import Path
from uuid import uuid4

from app import db as app_db
from app.main import app


pytestmark = pytest.mark.anyio("asyncio")
ROOT = Path(__file__).resolve().parents[2]


def test_removed_legacy_auth_and_profile_routes_are_not_mounted():
    inventory = {
        (route.path, method)
        for route in app.routes
        for method in getattr(route, "methods", set())
        if method not in {"HEAD", "OPTIONS"}
    }

    forbidden = {
        ("/auth/change-password", "POST"),
        ("/auth/request-password-reset", "POST"),
        ("/profiles/me/avatar", "POST"),
    }

    assert inventory.isdisjoint(forbidden)


async def test_register_rejects_referral_code_with_canonical_failure_envelope(
    async_client,
):
    resp = await async_client.post(
        "/auth/register",
        json={
            "email": "referral@example.com",
            "password": "Secret123!",
            "referral_code": "legacy-code",
        },
    )

    assert resp.status_code == 422, resp.text
    assert resp.json() == {
        "status": "error",
        "error_code": "validation_error",
        "message": "Begaran innehaller ogiltiga eller saknade falt.",
        "field_errors": [
            {
                "field": "referral_code",
                "error_code": "extra_forbidden",
                "message": "Faltet ar inte tillatet.",
            }
        ],
    }


async def test_register_rejects_display_name_with_canonical_failure_envelope(
    async_client,
):
    resp = await async_client.post(
        "/auth/register",
        json={
            "email": "name-at-register@example.com",
            "password": "Secret123!",
            "display_name": "Register Name",
        },
    )

    assert resp.status_code == 422, resp.text
    assert resp.json() == {
        "status": "error",
        "error_code": "validation_error",
        "message": "Begaran innehaller ogiltiga eller saknade falt.",
        "field_errors": [
            {
                "field": "display_name",
                "error_code": "extra_forbidden",
                "message": "Faltet ar inte tillatet.",
            }
        ],
    }


async def test_invalid_login_uses_canonical_failure_envelope(async_client):
    resp = await async_client.post(
        "/auth/login",
        json={"email": "missing@example.com", "password": "wrong-password"},
    )

    assert resp.status_code == 401, resp.text
    assert resp.json() == {
        "status": "error",
        "error_code": "invalid_credentials",
        "message": "Fel e-postadress eller losenord.",
    }


def _auth_header(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


async def _register_user(async_client, *, email: str, password: str) -> dict[str, str]:
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert register_resp.status_code == 201, register_resp.text
    token_payload = register_resp.json()

    me_resp = await async_client.get(
        "/profiles/me",
        headers=_auth_header(token_payload["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text
    return {
        "user_id": me_resp.json()["user_id"],
        "email": email.strip().lower(),
        "password": password,
    }


async def _delete_auth_subject(user_id: str) -> None:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.auth_subjects WHERE user_id = %s::uuid",
                (user_id,),
            )
            await conn.commit()


async def _set_auth_subject(
    user_id: str,
    *,
    email: str,
    onboarding_state: str,
    role: str,
) -> None:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET email = %s,
                       onboarding_state = %s,
                       role = %s
                 WHERE user_id = %s::uuid
                """,
                (email, onboarding_state, role, user_id),
            )
            await conn.commit()


async def _fetch_auth_subject_rows(user_id: str) -> list[dict[str, str]]:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT user_id::text,
                       email,
                       onboarding_state,
                       role::text
                FROM app.auth_subjects
                WHERE user_id = %s::uuid
                ORDER BY user_id
                """,
                (user_id,),
            )
            rows = await cur.fetchall()
    return [
        {
            "user_id": row[0],
            "email": row[1],
            "onboarding_state": row[2],
            "role": row[3],
        }
        for row in rows
    ]


async def test_login_ensures_missing_auth_subject_with_canonical_defaults(async_client):
    account = await _register_user(
        async_client,
        email=f"projection-login-{uuid4().hex}@example.com",
        password="Secret123!",
    )
    await _delete_auth_subject(account["user_id"])

    login_resp = await async_client.post(
        "/auth/login",
        json={
            "email": account["email"],
            "password": account["password"],
        },
    )

    assert login_resp.status_code == 200, login_resp.text
    assert set(login_resp.json()) == {"access_token", "token_type", "refresh_token"}
    assert await _fetch_auth_subject_rows(account["user_id"]) == [
        {
            "user_id": account["user_id"],
            "email": account["email"],
            "onboarding_state": "incomplete",
            "role": "learner",
        }
    ]


async def test_login_leaves_existing_auth_subject_unchanged(async_client):
    account = await _register_user(
        async_client,
        email=f"projection-existing-{uuid4().hex}@example.com",
        password="Secret123!",
    )
    await _set_auth_subject(
        account["user_id"],
        email=account["email"],
        onboarding_state="welcome_pending",
        role="teacher",
    )

    login_resp = await async_client.post(
        "/auth/login",
        json={
            "email": account["email"],
            "password": account["password"],
        },
    )

    assert login_resp.status_code == 200, login_resp.text
    assert await _fetch_auth_subject_rows(account["user_id"]) == [
        {
            "user_id": account["user_id"],
            "email": account["email"],
            "onboarding_state": "welcome_pending",
            "role": "teacher",
        }
    ]


def test_post_auth_projection_ensure_path_does_not_write_auth_users_directly() -> None:
    targets = (
        ROOT / "backend" / "app" / "auth.py",
        ROOT / "backend" / "app" / "models.py",
        ROOT / "backend" / "app" / "routes" / "auth.py",
        ROOT / "backend" / "app" / "repositories" / "auth.py",
        ROOT / "backend" / "app" / "repositories" / "auth_subjects.py",
    )
    forbidden_fragments = (
        "insert into auth.users",
        "update auth.users",
        "delete from auth.users",
        "merge into auth.users",
    )

    for path in targets:
        source = path.read_text(encoding="utf-8").lower()
        for forbidden in forbidden_fragments:
            assert forbidden not in source, f"{path.name} contains {forbidden}"
