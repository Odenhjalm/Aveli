import asyncio
import os
import shutil
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("APP_ENV", "test")

from app.testing.db_safety import assert_safe_test_db_url  # noqa: E402

for key in ("DATABASE_URL", "SUPABASE_DB_URL", "QA_DB_URL", "QA_DATABASE_URL"):
    value = os.environ.get(key)
    if value:
        assert_safe_test_db_url(value, source=key)

from tests.db_bootstrap import start_test_db  # noqa: E402

_TEST_DB = start_test_db()
os.environ["DATABASE_URL"] = _TEST_DB.url
os.environ["SUPABASE_DB_URL"] = _TEST_DB.url
os.environ.setdefault("SUPABASE_DB_PASSWORD", _TEST_DB.password)
os.environ.setdefault("MEDIA_SIGNING_SECRET", "test-secret")

import psycopg  # noqa: E402

_original_connect = psycopg.connect


def _guarded_connect(conninfo=None, *args, **kwargs):  # type: ignore[no-untyped-def]
    raw = ""
    if conninfo is not None:
        raw = str(conninfo)
    elif kwargs.get("host"):
        host = str(kwargs.get("host"))
        user = str(kwargs.get("user") or "")
        dbname = str(kwargs.get("dbname") or "")
        raw = f"postgresql://{user}@{host}/{dbname}"

    if raw:
        assert_safe_test_db_url(raw, source="psycopg.connect")
    return _original_connect(conninfo, *args, **kwargs)


psycopg.connect = _guarded_connect  # type: ignore[assignment]

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from app.config import settings  # noqa: E402
from app.db import pool  # noqa: E402
from app.main import app  # noqa: E402


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
    if pool.closed:
        await pool.open(wait=True)

    try:
        async with AsyncClient(
            transport=transport, base_url="http://testserver"
        ) as client:
            yield client
    finally:
        # Keep pool open across tests to avoid psycopg_pool reopen errors.
        pass


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
