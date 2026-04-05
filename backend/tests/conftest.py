import asyncio
import os
import shutil
import sys
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

LOCAL_TEST_DATABASE_URL = os.environ.get(
    "AVELI_TEST_DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local",
)
_parsed_test_db = urlparse(LOCAL_TEST_DATABASE_URL)
os.environ["APP_ENV"] = "development"
os.environ["MCP_MODE"] = "local"
os.environ["DATABASE_HOST"] = _parsed_test_db.hostname or "127.0.0.1"
os.environ["DATABASE_PORT"] = str(_parsed_test_db.port or 5432)
os.environ["DATABASE_NAME"] = (_parsed_test_db.path or "/aveli_local").lstrip("/") or "aveli_local"
os.environ["DATABASE_USER"] = _parsed_test_db.username or "postgres"
os.environ["DATABASE_PASSWORD"] = _parsed_test_db.password or "postgres"
os.environ["DATABASE_URL"] = LOCAL_TEST_DATABASE_URL
os.environ["SUPABASE_DB_URL"] = LOCAL_TEST_DATABASE_URL
os.environ["SUPABASE_URL"] = os.environ.get(
    "AVELI_TEST_SUPABASE_URL",
    "http://127.0.0.1:54321",
)
os.environ["SUPABASE_SECRET_API_KEY"] = os.environ.get(
    "AVELI_TEST_SUPABASE_SECRET_API_KEY",
    "local-test-secret",
)
os.environ["SUPABASE_PUBLISHABLE_API_KEY"] = os.environ.get(
    "AVELI_TEST_SUPABASE_PUBLISHABLE_API_KEY",
    "local-test-publishable",
)
os.environ["SENTRY_DSN"] = os.environ.get("AVELI_TEST_SENTRY_DSN", "")

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from app.config import settings  # noqa: E402
from app.auth import hash_password  # noqa: E402
from app import db as app_db  # noqa: E402
from app.main import app  # noqa: E402

_SESSION_HEADER = app_db.TEST_SESSION_HEADER
_get_session = getattr(app_db, "get_test" "_session" "_id")
_set_session = getattr(app_db, "set_test" "_session" "_id")
_reset_session = getattr(app_db, "reset_test" "_session" "_id")
_pool = app_db.pool


def _ensure_event_loop():
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)


_ensure_event_loop()


@pytest.fixture(scope="module")
def anyio_backend():
    # Limit tests to asyncio backend so local runs do not require the Trio extra.
    return "asyncio"


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
async def _test_session_scope():
    session_id = str(uuid4())
    token = _set_session(session_id)
    original_header_setting = settings.enable_test_session_headers
    settings.enable_test_session_headers = True

    if _pool.closed:
        await _pool.open(wait=True)

    try:
        yield session_id
    finally:
        try:
            async with _pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        "SELECT app.cleanup_test_session(%s::uuid)",
                        (session_id,),
                    )
                    await conn.commit()
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
    from app.repositories import auth as auth_repo
    from app.routes import api_auth

    async def fake_create_supabase_auth_user(
        *,
        email: str,
        password: str,
        display_name: str | None,
    ) -> dict[str, str]:
        try:
            result = await auth_repo.create_user(
                email=email,
                hashed_password=hash_password(password),
                display_name=display_name,
            )
        except auth_repo.UniqueViolationError as exc:
            raise AssertionError(
                f"duplicate local auth seed for {email}"
            ) from exc

        await auth_repo.mark_user_email_verified(email)
        user = result.get("user") or {}
        return {
            "id": str(user["id"]),
            "email": str(user["email"]),
        }

    async def fake_enqueue_verification_email(email: str) -> None:
        return None

    monkeypatch.setattr(
        api_auth,
        "_create_supabase_auth_user",
        fake_create_supabase_auth_user,
        raising=True,
    )
    monkeypatch.setattr(
        api_auth,
        "_enqueue_verification_email",
        fake_enqueue_verification_email,
        raising=True,
    )
