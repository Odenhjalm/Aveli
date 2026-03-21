from contextlib import asynccontextmanager, contextmanager
from contextvars import ContextVar, Token
from typing import AsyncIterator
from uuid import UUID

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from .config import settings

TEST_SESSION_HEADER = "X-Test-Session-ID"

_test_session_id: ContextVar[str | None] = ContextVar(
    "aveli_test_session_id",
    default=None,
)


def _normalize_test_session_id(value: str | UUID | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, UUID):
        return str(value)
    normalized = str(value).strip()
    if not normalized:
        return None
    try:
        return str(UUID(normalized))
    except ValueError:
        return None


def get_test_session_id() -> str | None:
    return _test_session_id.get()


def set_test_session_id(value: str | UUID | None) -> Token[str | None]:
    return _test_session_id.set(_normalize_test_session_id(value))


def reset_test_session_id(token: Token[str | None]) -> None:
    _test_session_id.reset(token)


@contextmanager
def use_test_session(value: str | UUID | None):
    token = set_test_session_id(value)
    try:
        yield get_test_session_id()
    finally:
        reset_test_session_id(token)


async def _apply_test_session_setting(conn) -> None:
    session_id = get_test_session_id() or ""
    await conn.execute(
        "SELECT set_config('app.test_session_id', %s, false)",
        (session_id,),
    )
    await conn.commit()


class ContextAwareAsyncConnectionPool(AsyncConnectionPool):
    @asynccontextmanager
    async def connection(self, *args, **kwargs):  # type: ignore[override]
        async with super().connection(*args, **kwargs) as conn:
            await _apply_test_session_setting(conn)
            yield conn


pool = ContextAwareAsyncConnectionPool(
    conninfo=settings.database_url.unicode_string(),
    min_size=1,
    max_size=10,
    open=False,
)


@asynccontextmanager
async def get_conn() -> AsyncIterator:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            yield cur
