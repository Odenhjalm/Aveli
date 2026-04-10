from __future__ import annotations

from typing import Any

from psycopg import errors
from psycopg.types.json import Jsonb

from ..db import pool


async def insert_payment_event(event_id: str, payload: dict[str, Any]) -> bool:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.payment_events (event_id, payload, processed_at)
                    VALUES (%s, %s, now())
                    ON CONFLICT (event_id) DO NOTHING
                    RETURNING event_id
                    """,
                    (event_id, Jsonb(payload)),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return True
            row = await cur.fetchone()
            await conn.commit()
    return row is not None


async def insert_billing_log(
    *,
    user_id: str | None,
    step: str,
    info: dict[str, Any] | None = None,
) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.billing_logs (user_id, step, info, created_at)
                    VALUES (%s, %s, %s, now())
                    """,
                    (user_id, step, Jsonb(info or {})),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return
            await conn.commit()


__all__ = ["insert_billing_log", "insert_payment_event"]
