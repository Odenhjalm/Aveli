import asyncio
import shutil
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

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
    original_signing_secret = settings.media_signing_secret
    original_signing_ttl = settings.media_signing_ttl_seconds
    original_legacy = settings.media_allow_legacy_media
    temp_root = tmp_path / "media"
    temp_root.mkdir(parents=True, exist_ok=True)
    settings.media_root = str(temp_root)
    # Ensure /media/sign is enabled for tests unless explicitly overridden.
    settings.media_signing_secret = "test-media-secret"
    settings.media_signing_ttl_seconds = max(60, int(original_signing_ttl or 0) or 600)
    # Many API smoke tests still rely on legacy upload/file routes; keep them
    # enabled in the test environment unless explicitly overridden.
    settings.media_allow_legacy_media = True
    try:
        yield Path(settings.media_root)
    finally:
        settings.media_root = original
        settings.media_signing_secret = original_signing_secret
        settings.media_signing_ttl_seconds = original_signing_ttl
        settings.media_allow_legacy_media = original_legacy
        shutil.rmtree(temp_root, ignore_errors=True)
