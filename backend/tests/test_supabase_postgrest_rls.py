import os
import uuid
from datetime import datetime, timedelta, timezone

import httpx
import psycopg
import pytest
from jose import jwt

REQUIRED_ENV_VARS = [
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_DB_URL",
    "SUPABASE_JWT_SECRET",
]


def _require_env():
    missing = [var for var in REQUIRED_ENV_VARS if not os.getenv(var)]
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


def _make_token(user_id: uuid.UUID, email: str, secret: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "email": email,
        "role": "authenticated",
        "aud": "authenticated",
        "exp": now + timedelta(minutes=30),
        "app_metadata": {"provider": "email"},
        "user_metadata": {},
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def _seed_supabase(db_url: str):
    host_id = uuid.uuid4()
    attendee_id = uuid.uuid4()
    outsider_id = uuid.uuid4()
    seminar_id = None

    host_email = f"host_{host_id.hex[:10]}@codecrafters.local"
    attendee_email = f"attendee_{attendee_id.hex[:10]}@codecrafters.local"
    outsider_email = f"outsider_{outsider_id.hex[:10]}@codecrafters.local"

    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into auth.users (id, email, encrypted_password)
                values (%s, %s, 'integration-test')
                on conflict (id) do nothing
                """,
                (host_id, host_email),
            )
            cur.execute(
                """
                insert into auth.users (id, email, encrypted_password)
                values (%s, %s, 'integration-test')
                on conflict (id) do nothing
                """,
                (attendee_id, attendee_email),
            )
            cur.execute(
                """
                insert into auth.users (id, email, encrypted_password)
                values (%s, %s, 'integration-test')
                on conflict (id) do nothing
                """,
                (outsider_id, outsider_email),
            )

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
        "host_email": host_email,
        "attendee_email": attendee_email,
        "outsider_email": outsider_email,
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
            cur.execute(
                "delete from auth.users where id in (%s, %s, %s)",
                (ids["host_id"], ids["attendee_id"], ids["outsider_id"]),
            )
        conn.commit()


@pytest.fixture(scope="module")
def supabase_context():
    _require_env()
    env = {
        "url": os.environ["SUPABASE_URL"].rstrip("/"),
        "anon_key": os.environ["SUPABASE_ANON_KEY"],
        "service_role": os.environ["SUPABASE_SERVICE_ROLE_KEY"],
        "db_url": os.environ["SUPABASE_DB_URL"],
        "jwt_secret": os.environ["SUPABASE_JWT_SECRET"],
    }
    ids = _seed_supabase(env["db_url"])
    try:
        host_token = _make_token(ids["host_id"], ids["host_email"], env["jwt_secret"])
        attendee_token = _make_token(ids["attendee_id"], ids["attendee_email"], env["jwt_secret"])
        outsider_token = _make_token(ids["outsider_id"], ids["outsider_email"], env["jwt_secret"])
        yield {
            **env,
            **ids,
            "host_token": host_token,
            "attendee_token": attendee_token,
            "outsider_token": outsider_token,
        }
    finally:
        _cleanup_supabase(env["db_url"], ids)


@pytest.mark.anyio("asyncio")
async def test_host_can_read_and_update_seminar_postgrest(supabase_context):
    rest_base = f"{supabase_context['url']}/rest/v1"
    headers = _with_public_profile(
        _auth_headers(supabase_context["anon_key"], supabase_context["host_token"])
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
            supabase_context["anon_key"], supabase_context["attendee_token"]
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
            supabase_context["anon_key"], supabase_context["outsider_token"]
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
