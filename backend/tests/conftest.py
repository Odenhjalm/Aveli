import asyncio
import os
import shutil
import sys
from pathlib import Path
from uuid import uuid4

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

LOCAL_TEST_DATABASE_URL = os.environ.get(
    "AVELI_TEST_DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:54322/aveli_local",
)
os.environ["APP_ENV"] = "development"
os.environ["MCP_MODE"] = "local"
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
from app.db import (  # noqa: E402
    TEST_SESSION_HEADER,
    get_test_session_id,
    pool,
    reset_test_session_id,
    set_test_session_id,
)
from app.main import app  # noqa: E402


_ISOLATED_TEST_TABLES = (
    "courses",
    "lessons",
    "lesson_media",
    "media_assets",
    "runtime_media",
)


def _ensure_event_loop():
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)


_ensure_event_loop()


async def _isolated_row_counts(session_id: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            for table_name in _ISOLATED_TEST_TABLES:
                await cur.execute(
                    f"""
                    SELECT count(*)
                    FROM app.{table_name}
                    WHERE is_test = true
                      AND test_session_id = %s::uuid
                    """,
                    (session_id,),
                )
                row = await cur.fetchone()
                counts[table_name] = int((row or (0,))[0] or 0)
    return counts


@pytest.fixture(scope="module")
def anyio_backend():
    # Limit tests to asyncio backend so local runs do not require the Trio extra.
    return "asyncio"


@pytest.fixture
async def async_client(anyio_backend) -> AsyncClient:
    if anyio_backend != "asyncio":
        pytest.skip("Backend tests require asyncio")

    transport = ASGITransport(app=app)
    if pool.closed:
        await pool.open(wait=True)

    try:
        default_headers: dict[str, str] = {}
        test_session_id = get_test_session_id()
        if test_session_id:
            default_headers[TEST_SESSION_HEADER] = test_session_id
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
    token = set_test_session_id(session_id)
    original_header_setting = settings.enable_test_session_headers
    settings.enable_test_session_headers = True

    if pool.closed:
        await pool.open(wait=True)

    try:
        yield session_id
    finally:
        try:
            async with pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        "SELECT app.cleanup_test_session(%s::uuid)",
                        (session_id,),
                    )
                    await conn.commit()
            remaining = await _isolated_row_counts(session_id)
            leaked = {
                table_name: row_count
                for table_name, row_count in remaining.items()
                if row_count > 0
            }
            if leaked:
                formatted = ", ".join(
                    f"{table_name}={row_count}"
                    for table_name, row_count in sorted(leaked.items())
                )
                raise AssertionError(
                    f"test session cleanup left isolated rows behind: {formatted}"
                )
        finally:
            settings.enable_test_session_headers = original_header_setting
            reset_test_session_id(token)


@pytest.fixture
def test_session_id() -> str:
    current = get_test_session_id()
    assert current is not None
    return current


@pytest.fixture(autouse=True)
def _temp_media_root(tmp_path):
    original = settings.media_root
    original_signing_secret = settings.media_signing_secret
    original_signing_ttl = settings.media_signing_ttl_seconds
    temp_root = tmp_path / "media"
    temp_root.mkdir(parents=True, exist_ok=True)
    settings.media_root = str(temp_root)
    # Ensure /media/sign is enabled for tests unless explicitly overridden.
    settings.media_signing_secret = "test-media-secret"
    settings.media_signing_ttl_seconds = max(60, int(original_signing_ttl or 0) or 600)
    try:
        yield Path(settings.media_root)
    finally:
        settings.media_root = original
        settings.media_signing_secret = original_signing_secret
        settings.media_signing_ttl_seconds = original_signing_ttl
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
