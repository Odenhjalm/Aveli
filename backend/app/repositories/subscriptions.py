from __future__ import annotations

from typing import Any

from psycopg import errors

from ..db import get_conn


async def get_latest_subscription(user_id: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        try:
            await cur.execute(
                """
                SELECT id,
                       user_id,
                       subscription_id,
                       status,
                       customer_id,
                       price_id,
                       created_at,
                       updated_at
                  FROM app.subscriptions
                 WHERE user_id = %s
                 ORDER BY updated_at DESC
                 LIMIT 1
                """,
                (user_id,),
            )
        except errors.UndefinedTable:
            return None
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_membership(user_id: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        try:
            await cur.execute(
                """
                SELECT membership_id,
                       user_id,
                       plan_interval,
                       price_id,
                       stripe_customer_id,
                       stripe_subscription_id,
                       status,
                       start_date,
                       end_date,
                       created_at,
                       updated_at
                  FROM app.memberships
                 WHERE user_id = %s
                 LIMIT 1
                """,
                (user_id,),
            )
        except errors.UndefinedTable:
            return None
        row = await cur.fetchone()
    return dict(row) if row else None


__all__ = ["get_latest_subscription", "get_membership"]
