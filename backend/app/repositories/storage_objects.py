from __future__ import annotations

from typing import Any, Iterable

from psycopg import errors

from ..db import pool


def _coerce_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _normalize_mime(value: Any) -> str | None:
    raw = str(value or "").strip().lower()
    if not raw:
        return None
    return raw.split(";", 1)[0].strip() or None


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


async def fetch_storage_object_details(
    pairs: Iterable[tuple[str, str]],
) -> tuple[dict[tuple[str, str], dict[str, Any] | None], bool]:
    """Return storage object metadata keyed by (bucket, key).

    Missing rows map to ``None``. If storage catalog tables are unavailable we
    return ({}, False) and callers must treat verification as unknown.
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
        SELECT
          c.bucket_id,
          c.name,
          o.id IS NOT NULL AS exists,
          o.metadata,
          o.created_at,
          o.updated_at,
          b.public
        FROM candidates c
        LEFT JOIN storage.objects o
          ON o.bucket_id = c.bucket_id
         AND o.name = c.name
        LEFT JOIN storage.buckets b
          ON b.id = c.bucket_id
    """

    try:
        async with pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(query, params)
                rows = await cur.fetchall()
        details: dict[tuple[str, str], dict[str, Any] | None] = {}
        for bucket_id, name, exists, metadata, created_at, updated_at, public in rows:
            key = (str(bucket_id), str(name))
            if not exists:
                details[key] = None
                continue
            meta = metadata or {}
            details[key] = {
                "bucket": str(bucket_id),
                "storage_path": str(name),
                "exists": True,
                "content_type": _normalize_mime(
                    meta.get("mimetype") or meta.get("content_type")
                ),
                "size_bytes": _coerce_int(
                    meta.get("size") or meta.get("contentLength")
                ),
                "public": bool(public),
                "metadata": meta,
                "created_at": created_at,
                "updated_at": updated_at,
            }
        for bucket, name in unique_pairs:
            details.setdefault((bucket, name), None)
        return details, True
    except errors.UndefinedTable:
        return {}, False
