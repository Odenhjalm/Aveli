import os
import shutil
import sys
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

ROOT_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT_DIR = Path(__file__).resolve().parents[2]
for path in (ROOT_DIR, REPO_ROOT_DIR):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

LOCAL_TEST_DATABASE_URL = os.environ.get(
    "AVELI_TEST_DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local",
)
_parsed_test_db = urlparse(LOCAL_TEST_DATABASE_URL)
for forbidden_key in (
    "SUPABASE_DB_URL",
    "SUPABASE_URL",
    "SUPABASE_SECRET_API_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_PUBLISHABLE_API_KEY",
    "SUPABASE_PUBLIC_API_KEY",
    "SUPABASE_ANON_KEY",
    "SUPABASE_PROJECT_REF",
    "SUPABASE_JWKS_URL",
    "SUPABASE_JWT_ISSUER",
    "SUPABASE_JWT_SECRET",
    "SUPABASE_JWT_SECRET_LEGACY",
    "MCP_PRODUCTION_DATABASE_URL",
    "MCP_PRODUCTION_SUPABASE_DB_URL",
):
    os.environ.pop(forbidden_key, None)
os.environ["APP_ENV"] = "local"
os.environ["MCP_MODE"] = "local"
os.environ["DATABASE_HOST"] = _parsed_test_db.hostname or "127.0.0.1"
os.environ["DATABASE_PORT"] = str(_parsed_test_db.port or 5432)
os.environ["DATABASE_NAME"] = (_parsed_test_db.path or "/aveli_local").lstrip(
    "/"
) or "aveli_local"
os.environ["DATABASE_USER"] = _parsed_test_db.username or "postgres"
os.environ["DATABASE_PASSWORD"] = _parsed_test_db.password or "postgres"
os.environ["DATABASE_URL"] = LOCAL_TEST_DATABASE_URL
os.environ["SENTRY_DSN"] = os.environ.get("AVELI_TEST_SENTRY_DSN", "")

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from psycopg import connect  # noqa: E402
from app.config import settings  # noqa: E402
from app import db as app_db  # noqa: E402
from app.main import app  # noqa: E402

_SESSION_HEADER = app_db.TEST_SESSION_HEADER
_get_session = getattr(app_db, "get_test" "_session" "_id")
_set_session = getattr(app_db, "set_test" "_session" "_id")
_reset_session = getattr(app_db, "reset_test" "_session" "_id")
_pool = app_db.pool


@pytest.fixture(scope="module")
def anyio_backend():
    # Limit tests to asyncio backend so local runs do not require the Trio extra.
    return "asyncio"


def _cleanup_test_session(session_id: str) -> None:
    with connect(LOCAL_TEST_DATABASE_URL) as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(
                    "SELECT app.cleanup_test_session(%s::uuid)",
                    (session_id,),
                )
                conn.commit()
            except Exception:
                conn.rollback()


@pytest.fixture
async def async_client(anyio_backend) -> AsyncClient:
    if anyio_backend != "asyncio":
        pytest.skip("Backend tests require asyncio")

    transport = ASGITransport(app=app)
    if _pool.closed:
        await _pool.open(wait=True)

    try:
        default_headers: dict[str, str] = {}
        session_id = _get_session()
        if session_id:
            default_headers[_SESSION_HEADER] = session_id
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
            headers=default_headers,
        ) as client:
            yield client
    finally:
        # Keep pool open across tests to avoid psycopg_pool reopen errors.
        pass


@pytest.fixture(autouse=True)
def _test_session_scope():
    session_id = str(uuid4())
    token = _set_session(session_id)
    original_header_setting = settings.enable_test_session_headers
    settings.enable_test_session_headers = True

    try:
        yield session_id
    finally:
        try:
            _cleanup_test_session(session_id)
        finally:
            settings.enable_test_session_headers = original_header_setting
            _reset_session(token)


@pytest.fixture(autouse=True)
def _temp_media_root(tmp_path):
    original = settings.media_root
    temp_root = tmp_path / "media"
    temp_root.mkdir(parents=True, exist_ok=True)
    settings.media_root = str(temp_root)
    try:
        yield Path(settings.media_root)
    finally:
        settings.media_root = original
        shutil.rmtree(temp_root, ignore_errors=True)


@pytest.fixture(autouse=True)
def _local_supabase_registration_stub(monkeypatch):
    from app.services import supabase_auth

    users_by_email: dict[str, dict[str, str]] = {}
    users_by_id: dict[str, dict[str, str]] = {}

    async def _ensure_local_auth_user(user_id: str, email: str) -> None:
        async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    INSERT INTO auth.users (
                        id,
                        email,
                        encrypted_password,
                        created_at,
                        updated_at
                    )
                    VALUES (%s::uuid, %s, %s, now(), now())
                    ON CONFLICT (id) DO UPDATE
                      SET email = excluded.email,
                          updated_at = now()
                    """,
                    (user_id, email, "supabase-auth-managed-test-placeholder"),
                )
                await conn.commit()

    async def fake_signup(email: str, password: str):
        normalized_email = email.strip().lower()
        if normalized_email in users_by_email:
            raise supabase_auth.SupabaseAuthConflictError("User already registered")
        user_id = str(uuid4())
        user = {
            "id": user_id,
            "email": normalized_email,
            "email_confirmed_at": None,
            "confirmed_at": None,
        }
        record = {"user_id": user_id, "email": normalized_email, "password": password}
        users_by_email[normalized_email] = record
        users_by_id[user_id] = record
        await _ensure_local_auth_user(user_id, normalized_email)
        return supabase_auth.SupabaseAuthIdentity(
            user_id=user_id,
            email=normalized_email,
            user=user,
            session=None,
            raw={"user": user},
        )

    async def fake_login_password(email: str, password: str):
        normalized_email = email.strip().lower()
        record = users_by_email.get(normalized_email)
        if not record or record["password"] != password:
            raise supabase_auth.SupabaseAuthInvalidCredentialsError(
                "Invalid login credentials"
            )
        user = {"id": record["user_id"], "email": normalized_email}
        return supabase_auth.SupabaseAuthSession(
            user_id=record["user_id"],
            email=normalized_email,
            access_token=f"supabase-access-{record['user_id']}",
            refresh_token=f"supabase-refresh-{record['user_id']}",
            token_type="bearer",
            expires_in=3600,
            user=user,
            raw={"user": user},
        )

    async def fake_get_user(user_id: str):
        record = users_by_id.get(str(user_id))
        if not record:
            raise supabase_auth.SupabaseAuthError("User not found", status_code=404)
        return {
            "id": record["user_id"],
            "email": record["email"],
            "email_confirmed_at": record.get("email_confirmed_at"),
            "confirmed_at": record.get("confirmed_at"),
        }

    async def fake_update_user_password(user_id: str, password: str):
        record = users_by_id.get(str(user_id))
        if not record:
            raise supabase_auth.SupabaseAuthError("User not found", status_code=404)
        record["password"] = password
        return {"id": record["user_id"], "email": record["email"]}

    async def fake_confirm_user_email(user_id: str):
        record = users_by_id.get(str(user_id))
        if not record:
            raise supabase_auth.SupabaseAuthError("User not found", status_code=404)
        record["email_confirmed_at"] = "2026-04-20T00:00:00+00:00"
        record["confirmed_at"] = "2026-04-20T00:00:00+00:00"
        return {
            "id": record["user_id"],
            "email": record["email"],
            "email_confirmed_at": record["email_confirmed_at"],
            "confirmed_at": record["confirmed_at"],
        }

    monkeypatch.setattr(supabase_auth, "signup", fake_signup)
    monkeypatch.setattr(supabase_auth, "login_password", fake_login_password)
    monkeypatch.setattr(supabase_auth, "get_user", fake_get_user)
    monkeypatch.setattr(
        supabase_auth, "update_user_password", fake_update_user_password
    )
    monkeypatch.setattr(supabase_auth, "confirm_user_email", fake_confirm_user_email)
    yield
