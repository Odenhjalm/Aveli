from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from psycopg.rows import dict_row

from ..db import get_conn, pool


SESSION_COLUMNS = """
    id, teacher_id, title, description, start_at, end_at,
    capacity, price_cents, currency, visibility,
    recording_url, stripe_price_id, created_at, updated_at
"""

SLOT_COLUMNS = """
    id, session_id, start_at, end_at,
    seats_total, seats_taken, created_at, updated_at
"""


async def create_session(
    *,
    teacher_id: str | UUID,
    title: str,
    description: str | None,
    start_at: datetime | None,
    end_at: datetime | None,
    capacity: int | None,
    price_cents: int,
    currency: str,
    visibility: str,
    recording_url: str | None,
    stripe_price_id: str | None,
) -> dict[str, Any]:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.sessions (
                    teacher_id,
                    title,
                    description,
                    start_at,
                    end_at,
                    capacity,
                    price_cents,
                    currency,
                    visibility,
                    recording_url,
                    stripe_price_id,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, now(), now())
                RETURNING {cols}
                """.format(cols=SESSION_COLUMNS),
                (
                    teacher_id,
                    title,
                    description,
                    start_at,
                    end_at,
                    capacity,
                    price_cents,
                    currency,
                    visibility,
                    recording_url,
                    stripe_price_id,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row)


async def update_session(
    session_id: str | UUID,
    *,
    teacher_id: str | UUID,
    fields: dict[str, Any],
) -> dict[str, Any] | None:
    if not fields:
        return await get_session(session_id)

    sets = []
    params: list[Any] = []
    for column, value in fields.items():
        sets.append(f"{column} = %s")
        params.append(value)

    params.extend([session_id, teacher_id])
    query = """
        UPDATE app.sessions
           SET {sets}, updated_at = now()
         WHERE id = %s AND teacher_id = %s
         RETURNING {cols}
    """.format(
        sets=", ".join(sets),
        cols=SESSION_COLUMNS,
    )

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def get_session(session_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT {cols}
              FROM app.sessions
             WHERE id = %s
             LIMIT 1
            """.format(cols=SESSION_COLUMNS),
            (session_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def list_teacher_sessions(
    teacher_id: str | UUID,
    *,
    visibility: str | None = None,
) -> list[dict[str, Any]]:
    clauses = ["teacher_id = %s"]
    params: list[Any] = [teacher_id]
    if visibility:
        clauses.append("visibility = %s")
        params.append(visibility)

    query = """
        SELECT {cols}
          FROM app.sessions
         WHERE {where}
         ORDER BY start_at NULLS LAST, created_at DESC
    """.format(cols=SESSION_COLUMNS, where=" AND ".join(clauses))

    async with get_conn() as cur:
        await cur.execute(query, params)
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_published_sessions(
    *,
    from_time: datetime | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    clauses = ["visibility = 'published'"]
    params: list[Any] = []

    if from_time:
        clauses.append("(start_at IS NULL OR start_at >= %s)")
        params.append(from_time)

    if limit <= 0 or limit > 200:
        limit = 50

    query = """
        SELECT {cols}
          FROM app.sessions
         WHERE {where}
         ORDER BY start_at NULLS LAST, created_at DESC
         LIMIT %s
    """.format(cols=SESSION_COLUMNS, where=" AND ".join(clauses))

    params.append(limit)

    async with get_conn() as cur:
        await cur.execute(query, params)
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def delete_session(session_id: str | UUID, *, teacher_id: str | UUID) -> bool:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                DELETE FROM app.sessions
                 WHERE id = %s AND teacher_id = %s
                """,
                (session_id, teacher_id),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
            return deleted


async def create_session_slot(
    *,
    session_id: str | UUID,
    start_at: datetime,
    end_at: datetime,
    seats_total: int,
) -> dict[str, Any]:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.session_slots (
                    session_id,
                    start_at,
                    end_at,
                    seats_total,
                    seats_taken,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, 0, now(), now())
                RETURNING {cols}
                """.format(cols=SLOT_COLUMNS),
                (session_id, start_at, end_at, seats_total),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row)


async def update_session_slot(
    slot_id: str | UUID,
    *,
    session_id: str | UUID | None = None,
    fields: dict[str, Any],
) -> dict[str, Any] | None:
    if not fields:
        return await get_session_slot(slot_id)

    sets = []
    params: list[Any] = []
    for column, value in fields.items():
        sets.append(f"{column} = %s")
        params.append(value)

    params.append(slot_id)

    where_clause = "id = %s"
    if session_id:
        where_clause += " AND session_id = %s"
        params.append(session_id)

    query = """
        UPDATE app.session_slots
           SET {sets}, updated_at = now()
         WHERE {where}
         RETURNING {cols}
    """.format(
        sets=", ".join(sets),
        where=where_clause,
        cols=SLOT_COLUMNS,
    )

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def list_session_slots(session_id: str | UUID) -> list[dict[str, Any]]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT {cols}
              FROM app.session_slots
             WHERE session_id = %s
             ORDER BY start_at
            """.format(cols=SLOT_COLUMNS),
            (session_id,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_session_slot(slot_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT {cols}
              FROM app.session_slots
             WHERE id = %s
             LIMIT 1
            """.format(cols=SLOT_COLUMNS),
            (slot_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def increment_slot_booking(
    slot_id: str | UUID,
    *,
    seats: int = 1,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.session_slots
                   SET seats_taken = seats_taken + %s,
                       updated_at = now()
                 WHERE id = %s
                   AND seats_taken + %s <= seats_total
                 RETURNING {cols}
                """.format(cols=SLOT_COLUMNS),
                (seats, slot_id, seats),
            )
            row = await cur.fetchone()
            if row:
                await conn.commit()
                return dict(row)
            await conn.rollback()
            return None


async def release_slot_booking(
    slot_id: str | UUID,
    *,
    seats: int = 1,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.session_slots
                   SET seats_taken = GREATEST(seats_taken - %s, 0),
                       updated_at = now()
                 WHERE id = %s
                 RETURNING {cols}
                """.format(cols=SLOT_COLUMNS),
                (seats, slot_id),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None
