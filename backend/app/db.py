from contextlib import asynccontextmanager
from typing import AsyncIterator

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from .config import settings

pool = AsyncConnectionPool(
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
