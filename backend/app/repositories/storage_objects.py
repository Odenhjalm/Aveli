from __future__ import annotations

from typing import Any, Iterable

from psycopg import errors

from ..db import pool


async def fetch_storage_object_existence(
    pairs: Iterable[tuple[str, str]],
) -> tuple[dict[tuple[str, str], bool], bool]:
    """Return a map of (bucket, key) -> exists plus a boolean for table availability.

    The Supabase `storage.objects` table may not exist in some local dev setups.
    In that case we return ({}, False) and callers must treat existence as unknown.
    """

    unique_pairs = sorted({(b, p) for b, p in pairs if b and p})
    if not unique_pairs:
        return {}, True

    placeholders = ", ".join(["(%s, %s)"] * len(unique_pairs))
    params: list[Any] = []
    for bucket, name in unique_pairs:
        params.extend([bucket, name])

    query = f"""
        WITH candidates(bucket_id, name) AS (
          VALUES {placeholders}
        )
        SELECT c.bucket_id, c.name, (o.id IS NOT NULL) AS exists
        FROM candidates c
        LEFT JOIN storage.objects o
          ON o.bucket_id = c.bucket_id
         AND o.name = c.name
    """

    try:
        async with pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(query, params)
                rows = await cur.fetchall()
        existence: dict[tuple[str, str], bool] = {}
        for bucket_id, name, exists in rows:
            existence[(str(bucket_id), str(name))] = bool(exists)
        return existence, True
    except errors.UndefinedTable:
        return {}, False
