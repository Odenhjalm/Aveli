from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool


async def create_order(
    *,
    user_id: str | UUID,
    service_id: str | UUID | None,
    course_id: str | UUID | None,
    amount_cents: int,
    currency: str,
    metadata: dict[str, Any] | None = None,
    order_type: str | None = None,
    session_id: str | UUID | None = None,
    session_slot_id: str | UUID | None = None,
    stripe_subscription_id: str | None = None,
    stripe_customer_id: str | None = None,
    connected_account_id: str | None = None,
) -> dict[str, Any]:
    normalized_order_type = (order_type or "one_off").lower()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.orders (
                    user_id,
                    service_id,
                    course_id,
                    session_id,
                    session_slot_id,
                    order_type,
                    amount_cents,
                    currency,
                    status,
                    stripe_checkout_id,
                    stripe_payment_intent,
                    stripe_subscription_id,
                    stripe_customer_id,
                    connected_account_id,
                    metadata
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'pending', NULL, NULL, %s, %s, %s, %s)
                RETURNING id,
                          user_id,
                          service_id,
                          course_id,
                          session_id,
                          session_slot_id,
                          order_type,
                          amount_cents,
                          currency,
                          status,
                          stripe_checkout_id,
                          stripe_payment_intent,
                          stripe_subscription_id,
                          stripe_customer_id,
                          connected_account_id,
                          metadata,
                          created_at,
                          updated_at
                """,
                (
                    user_id,
                    service_id,
                    course_id,
                    session_id,
                    session_slot_id,
                    normalized_order_type,
                    amount_cents,
                    currency,
                    stripe_subscription_id,
                    stripe_customer_id,
                    connected_account_id,
                    Jsonb(metadata or {}),
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row)


async def get_order(order_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id,
                   user_id,
                   service_id,
                   course_id,
                   session_id,
                   session_slot_id,
                   order_type,
                   amount_cents,
                   currency,
                   status,
                   stripe_checkout_id,
                   stripe_payment_intent,
                   stripe_subscription_id,
                   stripe_customer_id,
                   connected_account_id,
                   metadata,
                   created_at,
                   updated_at
            FROM app.orders
            WHERE id = %s
            LIMIT 1
            """,
            (order_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def get_user_order(
    order_id: str | UUID, user_id: str | UUID
) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id,
                   user_id,
                   service_id,
                   course_id,
                   session_id,
                   session_slot_id,
                   order_type,
                   amount_cents,
                   currency,
                   status,
                   stripe_checkout_id,
                   stripe_payment_intent,
                   stripe_subscription_id,
                   stripe_customer_id,
                   connected_account_id,
                   metadata,
                   created_at,
                   updated_at
            FROM app.orders
            WHERE id = %s AND user_id = %s
            LIMIT 1
            """,
            (order_id, user_id),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def list_user_orders(
    user_id: str | UUID,
    *,
    status: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    clauses = ["user_id = %s"]
    params: list[Any] = [user_id]
    if status:
        clauses.append("status = %s")
        params.append(status.lower())
    if limit <= 0 or limit > 200:
        limit = 50
    query = f"""
        SELECT id,
               user_id,
               service_id,
               course_id,
               session_id,
               session_slot_id,
               order_type,
               amount_cents,
               currency,
               status,
               stripe_checkout_id,
               stripe_payment_intent,
               stripe_subscription_id,
               stripe_customer_id,
               connected_account_id,
               metadata,
               created_at,
               updated_at
        FROM app.orders
        WHERE {' AND '.join(clauses)}
        ORDER BY created_at DESC
        LIMIT %s
    """
    params.append(limit)
    async with get_conn() as cur:
        await cur.execute(query, params)
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_latest_order_for_course(
    user_id: str | UUID,
    course_id: str | UUID,
) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id,
                   user_id,
                   service_id,
                   course_id,
                   session_id,
                   session_slot_id,
                   order_type,
                   amount_cents,
                   currency,
                   status,
                   stripe_checkout_id,
                   stripe_payment_intent,
                   stripe_subscription_id,
                   stripe_customer_id,
                   connected_account_id,
                   metadata,
                   created_at,
                   updated_at
            FROM app.orders
            WHERE user_id = %s AND course_id = %s
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (user_id, course_id),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def set_order_checkout_reference(
    *,
    order_id: str | UUID,
    checkout_id: str | None,
    payment_intent: str | None,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.orders
                   SET stripe_checkout_id = %s,
                       stripe_payment_intent = COALESCE(%s, stripe_payment_intent),
                       updated_at = now()
                 WHERE id = %s
                 RETURNING id,
                           user_id,
                           service_id,
                           course_id,
                           session_id,
                           session_slot_id,
                           order_type,
                           amount_cents,
                           currency,
                           status,
                           stripe_checkout_id,
                           stripe_payment_intent,
                           stripe_subscription_id,
                           stripe_customer_id,
                           connected_account_id,
                           metadata,
                           created_at,
                           updated_at
                """,
                (checkout_id, payment_intent, order_id),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None
