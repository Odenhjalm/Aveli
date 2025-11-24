from typing import AsyncIterator

from ..db import get_conn


async def list_feed(*, limit: int = 50) -> AsyncIterator[dict]:
    query = """
        select id,
               activity_type,
               actor_id,
               subject_table,
               subject_id,
               summary,
               metadata,
               occurred_at
        from app.activities_feed
        order by occurred_at desc
        limit %s
    """
    async with get_conn() as cur:
        await cur.execute(query, (limit,))
        rows = await cur.fetchall()
    for row in rows:
        yield row
