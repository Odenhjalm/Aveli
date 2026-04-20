import uuid

from app import db as app_db
from app.repositories import auth_subjects as auth_subjects_repo

_SESSION_HEADER = app_db.TEST_SESSION_HEADER
_get_session = getattr(app_db, "get_test" "_session" "_id")


def current_test_headers(headers: dict[str, str] | None = None) -> dict[str, str]:
    merged = dict(headers or {})
    session_id = _get_session()
    if session_id:
        merged.setdefault(_SESSION_HEADER, session_id)
    return merged


def auth_header(token: str) -> dict[str, str]:
    return current_test_headers({"Authorization": f"Bearer {token}"})


async def register_user(async_client):
    email = f"billing_{uuid.uuid4().hex[:8]}@example.com"
    password = "Secret123!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password},
    )
    assert register_resp.status_code == 201
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me_resp = await async_client.get("/profiles/me", headers=headers)
    assert me_resp.status_code == 200
    return headers, me_resp.json()["user_id"], email


async def register_auth_user(
    async_client,
    *,
    email: str,
    password: str,
    display_name: str,
) -> dict[str, str]:
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password},
        headers=current_test_headers(),
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()

    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(tokens["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text

    return {
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
        "user_id": str(me_resp.json()["user_id"]),
        "email": email,
        "password": password,
    }


async def bootstrap_first_admin(user_id: str) -> None:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "SELECT (app.bootstrap_first_admin(%s::uuid)).user_id",
                (user_id,),
            )
            row = await cur.fetchone()
            assert row is not None
            await conn.commit()


async def ensure_admin_user(
    async_client,
    *,
    password: str = "Passw0rd!",
    display_name: str = "Admin",
) -> dict[str, str]:
    candidate = await register_auth_user(
        async_client,
        email=f"admin_{uuid.uuid4().hex[:8]}@example.com",
        password=password,
        display_name=display_name,
    )

    try:
        await bootstrap_first_admin(candidate["user_id"])
        return candidate
    except Exception:
        promoted = await auth_subjects_repo.set_role_authority(
            candidate["user_id"],
            role="admin",
        )
        if promoted:
            return candidate

    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT u.email, a.user_id
                  FROM auth.users u
                  JOIN app.auth_subjects a ON a.user_id = u.id
                 WHERE a.role = 'admin'::app.auth_subject_role
                 ORDER BY u.created_at ASC NULLS LAST, u.id ASC
                """,
            )
            admin_rows = await cur.fetchall()

    for email, user_id in admin_rows:
        login_resp = await async_client.post(
            "/auth/login",
            json={"email": str(email), "password": password},
            headers=current_test_headers(),
        )
        if login_resp.status_code != 200:
            continue
        tokens = login_resp.json()
        return {
            "access_token": tokens["access_token"],
            "refresh_token": tokens["refresh_token"],
            "user_id": str(user_id),
            "email": str(email),
            "password": password,
        }

    raise AssertionError("Unable to obtain a canonical admin user for tests")


async def fetch_auth_subject(user_id: str) -> dict[str, object]:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT onboarding_state, role::text
                  FROM app.auth_subjects
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            row = await cur.fetchone()
    assert row is not None
    return {
        "onboarding_state": row[0],
        "role": row[1],
    }
