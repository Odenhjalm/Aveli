import os
import uuid

import httpx
import psycopg
import pytest

REQUIRED_ENV_VARS = [
    "SUPABASE_URL",
    "SUPABASE_DB_URL",
]
CLIENT_ENV_KEYS = (
    "SUPABASE_PUBLISHABLE_API_KEY",
    "SUPABASE_PUBLIC_API_KEY",
)
SERVICE_ENV_KEYS = ("SUPABASE_SECRET_API_KEY", "SUPABASE_SERVICE_ROLE_KEY")
DEFAULT_PASSWORD = "SupabaseTest123!"


def _looks_like_jwt(value: str) -> bool:
    return value.count(".") >= 2


def _env_first(*keys: str) -> str:
    for key in keys:
        value = os.getenv(key)
        if value:
            return value
    return ""


def _require_env():
    missing = [var for var in REQUIRED_ENV_VARS if not os.getenv(var)]
    if not _env_first(*SERVICE_ENV_KEYS):
        missing.append("SUPABASE_SECRET_API_KEY/SUPABASE_SERVICE_ROLE_KEY")
    if not _env_first(*CLIENT_ENV_KEYS):
        missing.append(
            "SUPABASE_PUBLISHABLE_API_KEY/SUPABASE_PUBLIC_API_KEY"
        )
    if missing:
        pytest.skip(f"Supabase env vars missing: {', '.join(missing)}")


def _auth_headers(apikey: str, token: str) -> dict[str, str]:
    return {
        "apikey": apikey,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def _with_public_profile(headers: dict[str, str]) -> dict[str, str]:
    enriched = dict(headers)
    enriched["Accept-Profile"] = "public"
    enriched["Content-Profile"] = "public"
    return enriched


def _admin_headers(service_key: str) -> dict[str, str]:
    return {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def _client_headers(client_key: str) -> dict[str, str]:
    headers = {
        "apikey": client_key,
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if _looks_like_jwt(client_key):
        headers["Authorization"] = f"Bearer {client_key}"
    return headers


def _create_auth_user(
    client: httpx.Client, *, email: str, password: str
) -> dict[str, str]:
    payload = {"email": email, "password": password, "email_confirm": True}
    resp = client.post("/auth/v1/admin/users", json=payload)
    if resp.status_code not in (200, 201):
        raise RuntimeError(
            f"Supabase admin create failed ({resp.status_code}): {resp.text}"
        )
    return resp.json()


def _issue_access_token(
    client: httpx.Client, *, email: str, password: str
) -> str:
    resp = client.post(
        "/auth/v1/token?grant_type=password",
        json={"email": email, "password": password},
    )
    if resp.status_code != 200:
        raise RuntimeError(
            f"Supabase password grant failed ({resp.status_code}): {resp.text}"
        )
    data = resp.json()
    token = data.get("access_token")
    if not token:
        raise RuntimeError("Supabase auth response missing access_token")
    return token


def _delete_auth_users(
    base_url: str, service_key: str, user_ids: list[uuid.UUID]
) -> None:
    if not user_ids:
        return
    try:
        with httpx.Client(
            base_url=base_url, headers=_admin_headers(service_key), timeout=10
        ) as client:
            for user_id in user_ids:
                resp = client.delete(f"/auth/v1/admin/users/{user_id}")
                if resp.status_code not in (200, 204, 404):
                    continue
    except httpx.HTTPError:
        return


def _seed_supabase(db_url: str, users: dict[str, dict[str, str]]):
    host_id = users["host"]["id"]
    attendee_id = users["attendee"]["id"]
    outsider_id = users["outsider"]["id"]
    seminar_id = None

    host_email = users["host"]["email"]
    attendee_email = users["attendee"]["email"]
    outsider_email = users["outsider"]["email"]

    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into app.profiles (user_id, email, display_name, role, role_v2, is_admin)
                values (%s, %s, %s, 'teacher', 'teacher', false)
                on conflict (user_id) do nothing
                """,
                (host_id, host_email, "Host Tester"),
            )
            cur.execute(
                """
                insert into app.profiles (user_id, email, display_name, role, role_v2, is_admin)
                values (%s, %s, %s, 'student', 'user', false)
                on conflict (user_id) do nothing
                """,
                (attendee_id, attendee_email, "Attendee Tester"),
            )
            cur.execute(
                """
                insert into app.profiles (user_id, email, display_name, role, role_v2, is_admin)
                values (%s, %s, %s, 'student', 'user', false)
                on conflict (user_id) do nothing
                """,
                (outsider_id, outsider_email, "Outsider Tester"),
            )

            cur.execute(
                """
                insert into app.seminars (host_id, title, description, status)
                values (%s, 'Supabase PostgREST Seminar', 'RLS smoke test', 'scheduled')
                returning id
                """,
                (host_id,),
            )
            seminar_id = cur.fetchone()[0]

            cur.execute(
                """
                insert into app.seminar_attendees (seminar_id, user_id, role)
                values (%s, %s, 'participant')
                on conflict do nothing
                """,
                (seminar_id, attendee_id),
            )
        conn.commit()

    return {
        "host_id": host_id,
        "attendee_id": attendee_id,
        "outsider_id": outsider_id,
        "seminar_id": seminar_id,
    }


def _cleanup_supabase(db_url: str, ids: dict[str, uuid.UUID]):
    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "delete from app.seminar_attendees where seminar_id = %s",
                (ids["seminar_id"],),
            )
            cur.execute(
                "delete from app.seminars where id = %s",
                (ids["seminar_id"],),
            )
            cur.execute(
                "delete from app.profiles where user_id in (%s, %s, %s)",
                (ids["host_id"], ids["attendee_id"], ids["outsider_id"]),
            )
        conn.commit()


@pytest.fixture(scope="module")
def supabase_context():
    _require_env()
    client_key = _env_first(*CLIENT_ENV_KEYS)
    service_key = _env_first(*SERVICE_ENV_KEYS)
    env = {
        "url": os.environ["SUPABASE_URL"].rstrip("/"),
        "client_key": client_key,
        "service_role": service_key,
        "db_url": os.environ["SUPABASE_DB_URL"],
    }
    user_ids: list[uuid.UUID] = []
    ids: dict[str, uuid.UUID] = {}
    users: dict[str, dict[str, str]] = {}
    try:
        with httpx.Client(
            base_url=env["url"], headers=_admin_headers(env["service_role"]), timeout=10
        ) as admin_client:
            host_seed = uuid.uuid4()
            attendee_seed = uuid.uuid4()
            outsider_seed = uuid.uuid4()
            host_email = f"host_{host_seed.hex[:10]}@codecrafters.local"
            attendee_email = f"attendee_{attendee_seed.hex[:10]}@codecrafters.local"
            outsider_email = f"outsider_{outsider_seed.hex[:10]}@codecrafters.local"

            host_user = _create_auth_user(
                admin_client, email=host_email, password=DEFAULT_PASSWORD
            )
            attendee_user = _create_auth_user(
                admin_client, email=attendee_email, password=DEFAULT_PASSWORD
            )
            outsider_user = _create_auth_user(
                admin_client, email=outsider_email, password=DEFAULT_PASSWORD
            )

            users = {
                "host": {
                    "id": uuid.UUID(host_user["id"]),
                    "email": host_email,
                },
                "attendee": {
                    "id": uuid.UUID(attendee_user["id"]),
                    "email": attendee_email,
                },
                "outsider": {
                    "id": uuid.UUID(outsider_user["id"]),
                    "email": outsider_email,
                },
            }
            user_ids = [
                users["host"]["id"],
                users["attendee"]["id"],
                users["outsider"]["id"],
            ]

        ids = _seed_supabase(env["db_url"], users)
        with httpx.Client(
            base_url=env["url"], headers=_client_headers(env["client_key"]), timeout=10
        ) as token_client:
            host_token = _issue_access_token(
                token_client, email=users["host"]["email"], password=DEFAULT_PASSWORD
            )
            attendee_token = _issue_access_token(
                token_client, email=users["attendee"]["email"], password=DEFAULT_PASSWORD
            )
            outsider_token = _issue_access_token(
                token_client, email=users["outsider"]["email"], password=DEFAULT_PASSWORD
            )
        yield {
            **env,
            **ids,
            "host_token": host_token,
            "attendee_token": attendee_token,
            "outsider_token": outsider_token,
        }
    finally:
        if ids:
            _cleanup_supabase(env["db_url"], ids)
        if user_ids:
            _delete_auth_users(env["url"], env["service_role"], user_ids)


@pytest.mark.anyio("asyncio")
async def test_host_can_read_and_update_seminar_postgrest(supabase_context):
    rest_base = f"{supabase_context['url']}/rest/v1"
    headers = _with_public_profile(
        _auth_headers(supabase_context["client_key"], supabase_context["host_token"])
    )

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{rest_base}/rpc/rest_select_seminar",
            headers=headers,
            json={"p_seminar_id": str(supabase_context["seminar_id"])},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data[0]["id"] == str(supabase_context["seminar_id"])

        patch_resp = await client.post(
            f"{rest_base}/rpc/rest_update_seminar_description",
            headers=headers,
            json={
                "p_seminar_id": str(supabase_context["seminar_id"]),
                "p_description": "Updated via PostgREST smoke test",
            },
        )
        assert patch_resp.status_code == 200, patch_resp.text
        updated = patch_resp.json()
        assert updated["description"] == "Updated via PostgREST smoke test"


@pytest.mark.anyio("asyncio")
async def test_attendee_can_read_attendance_postgrest(supabase_context):
    rest_base = f"{supabase_context['url']}/rest/v1"
    headers = _with_public_profile(
        _auth_headers(
            supabase_context["client_key"], supabase_context["attendee_token"]
        )
    )

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{rest_base}/rpc/rest_select_seminar_attendees",
            headers=headers,
            json={"p_seminar_id": str(supabase_context["seminar_id"])},
        )
        assert resp.status_code == 200, resp.text
        attendees = resp.json()
        assert attendees[0]["user_id"] == str(supabase_context["attendee_id"])


@pytest.mark.anyio("asyncio")
async def test_outsider_cannot_insert_or_update_postgrest(supabase_context):
    rest_base = f"{supabase_context['url']}/rest/v1"
    headers = _with_public_profile(
        _auth_headers(
            supabase_context["client_key"], supabase_context["outsider_token"]
        )
    )

    async with httpx.AsyncClient() as client:
        insert_resp = await client.post(
            f"{rest_base}/rpc/rest_insert_seminar",
            headers=headers,
            json={
                "p_host_id": str(supabase_context["host_id"]),
                "p_title": "Unauthorized Seminar",
                "p_status": "scheduled",
            },
        )
        assert insert_resp.status_code in (401, 403), insert_resp.text

        patch_resp = await client.post(
            f"{rest_base}/rpc/rest_update_seminar_description",
            headers=headers,
            json={
                "p_seminar_id": str(supabase_context["seminar_id"]),
                "p_description": "Hijack Attempt",
            },
        )
        assert patch_resp.status_code == 200, patch_resp.text
        blocked = patch_resp.json()
        assert blocked["id"] is None
