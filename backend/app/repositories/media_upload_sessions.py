from __future__ import annotations

from datetime import datetime
from typing import Any

from psycopg import errors
from psycopg.rows import dict_row

from ..db import pool


class UploadChunkAlreadyExistsError(RuntimeError):
    """Raised when a chunk insert races an existing session chunk."""


_SESSION_COLUMNS = """
    id,
    media_asset_id,
    owner_user_id,
    state,
    total_bytes,
    content_type,
    chunk_size,
    expected_chunks,
    received_bytes,
    expires_at,
    finalized_at,
    created_at,
    updated_at
"""

_CHUNK_COLUMNS = """
    id,
    upload_session_id,
    media_asset_id,
    chunk_index,
    byte_start,
    byte_end,
    size_bytes,
    sha256,
    spool_object_path,
    created_at
"""


def _row(value: Any) -> dict[str, Any] | None:
    return dict(value) if value is not None else None


async def create_upload_session(
    *,
    media_asset_id: str,
    owner_user_id: str,
    total_bytes: int,
    content_type: str,
    chunk_size: int,
    expected_chunks: int,
    expires_at: datetime,
) -> dict[str, Any]:
    query = f"""
        insert into app.media_upload_sessions (
            media_asset_id,
            owner_user_id,
            total_bytes,
            content_type,
            chunk_size,
            expected_chunks,
            expires_at
        )
        values (
            %s::uuid,
            %s::uuid,
            %s,
            %s,
            %s,
            %s,
            %s
        )
        returning {_SESSION_COLUMNS}
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    media_asset_id,
                    owner_user_id,
                    total_bytes,
                    content_type,
                    chunk_size,
                    expected_chunks,
                    expires_at,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        raise RuntimeError("created media upload session was not returned")
    return dict(row)


async def get_upload_session_for_owner_media_asset(
    *,
    upload_session_id: str,
    media_asset_id: str,
    owner_user_id: str,
) -> dict[str, Any] | None:
    query = f"""
        select {_SESSION_COLUMNS}
          from app.media_upload_sessions
         where id = %s::uuid
           and media_asset_id = %s::uuid
           and owner_user_id = %s::uuid
         limit 1
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (upload_session_id, media_asset_id, owner_user_id))
            row = await cur.fetchone()
    return _row(row)


async def get_upload_chunk(
    *,
    upload_session_id: str,
    chunk_index: int,
) -> dict[str, Any] | None:
    query = f"""
        select {_CHUNK_COLUMNS}
          from app.media_upload_chunks
         where upload_session_id = %s::uuid
           and chunk_index = %s
         limit 1
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (upload_session_id, chunk_index))
            row = await cur.fetchone()
    return _row(row)


async def create_upload_chunk(
    *,
    upload_session_id: str,
    media_asset_id: str,
    chunk_index: int,
    byte_start: int,
    byte_end: int,
    size_bytes: int,
    sha256: str,
    spool_object_path: str,
) -> dict[str, Any]:
    insert_query = f"""
        insert into app.media_upload_chunks (
            upload_session_id,
            media_asset_id,
            chunk_index,
            byte_start,
            byte_end,
            size_bytes,
            sha256,
            spool_object_path
        )
        values (
            %s::uuid,
            %s::uuid,
            %s,
            %s,
            %s,
            %s,
            %s,
            %s
        )
        returning {_CHUNK_COLUMNS}
    """
    update_query = f"""
        update app.media_upload_sessions
           set received_bytes = received_bytes + %s,
               updated_at = now()
         where id = %s::uuid
           and media_asset_id = %s::uuid
        returning {_SESSION_COLUMNS}
    """
    try:
        async with pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    insert_query,
                    (
                        upload_session_id,
                        media_asset_id,
                        chunk_index,
                        byte_start,
                        byte_end,
                        size_bytes,
                        sha256,
                        spool_object_path,
                    ),
                )
                chunk = await cur.fetchone()
                await cur.execute(
                    update_query,
                    (size_bytes, upload_session_id, media_asset_id),
                )
                session = await cur.fetchone()
                await conn.commit()
    except errors.UniqueViolation as exc:
        raise UploadChunkAlreadyExistsError(str(exc)) from exc

    if chunk is None or session is None:
        raise RuntimeError("created media upload chunk was not returned")
    result = dict(chunk)
    result["received_bytes"] = session["received_bytes"]
    return result


async def list_upload_chunks(*, upload_session_id: str) -> list[dict[str, Any]]:
    query = f"""
        select {_CHUNK_COLUMNS}
          from app.media_upload_chunks
         where upload_session_id = %s::uuid
         order by chunk_index asc
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (upload_session_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def mark_upload_session_finalized(
    *,
    upload_session_id: str,
    media_asset_id: str,
    owner_user_id: str,
) -> dict[str, Any] | None:
    query = f"""
        update app.media_upload_sessions
           set state = 'finalized',
               finalized_at = coalesce(finalized_at, now()),
               updated_at = now()
         where id = %s::uuid
           and media_asset_id = %s::uuid
           and owner_user_id = %s::uuid
           and state in ('open', 'finalized')
        returning {_SESSION_COLUMNS}
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (upload_session_id, media_asset_id, owner_user_id))
            row = await cur.fetchone()
            await conn.commit()
    return _row(row)


async def expire_abandoned_upload_sessions(*, now_at: datetime | None = None) -> int:
    timestamp_clause = "%s" if now_at is not None else "now()"
    query = f"""
        update app.media_upload_sessions
           set state = 'expired',
               updated_at = now()
         where state = 'open'
           and expires_at < {timestamp_clause}
    """
    params: tuple[Any, ...] = (now_at,) if now_at is not None else ()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            count = int(cur.rowcount or 0)
            await conn.commit()
    return count
