from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import pool

_PAYMENT_SELECT = """
    SELECT id,
           order_id,
           provider,
           provider_reference,
           status,
           amount_cents,
           currency,
           metadata,
           raw_payload,
           created_at,
           updated_at
      FROM app.payments
"""


async def mark_order_paid(
    order_id: str | UUID,
    *,
    payment_intent: str | None = None,
    checkout_id: str | None = None,
    subscription_id: str | None = None,
    customer_id: str | None = None,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.orders
                   SET status = 'paid',
                       stripe_payment_intent = COALESCE(%s, stripe_payment_intent),
                       stripe_checkout_id = COALESCE(%s, stripe_checkout_id),
                       stripe_subscription_id = COALESCE(%s, stripe_subscription_id),
                       stripe_customer_id = COALESCE(%s, stripe_customer_id),
                       updated_at = now()
                 WHERE id = %s
                 RETURNING id, user_id, service_id, course_id, amount_cents,
                           currency, status, stripe_checkout_id, stripe_payment_intent,
                           stripe_subscription_id, stripe_customer_id,
                           metadata, created_at, updated_at
                """,
                (payment_intent, checkout_id, subscription_id, customer_id, order_id),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def get_latest_payment_for_order(
    order_id: str | UUID,
    *,
    status: str | None = None,
) -> dict[str, Any] | None:
    clauses = ["order_id = %s"]
    params: list[Any] = [order_id]
    if status:
        clauses.append("status = %s")
        params.append(str(status).strip().lower())

    query = f"""
        {_PAYMENT_SELECT}
         WHERE {' AND '.join(clauses)}
         ORDER BY created_at DESC, id DESC
         LIMIT 1
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_payment_for_order_by_reference(
    order_id: str | UUID,
    provider_reference: str,
    *,
    status: str | None = None,
) -> dict[str, Any] | None:
    clauses = [
        "order_id = %s",
        "provider_reference = %s",
    ]
    params: list[Any] = [order_id, provider_reference]
    if status:
        clauses.append("status = %s")
        params.append(str(status).strip().lower())

    query = f"""
        {_PAYMENT_SELECT}
         WHERE {' AND '.join(clauses)}
         ORDER BY created_at DESC, id DESC
         LIMIT 1
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
    return dict(row) if row else None


async def record_payment(
    *,
    order_id: str | UUID,
    provider: str,
    provider_reference: str | None,
    status: str,
    amount_cents: int,
    currency: str,
    metadata: dict[str, Any] | None = None,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.payments (
                    order_id,
                    provider,
                    provider_reference,
                    status,
                    amount_cents,
                    currency,
                    metadata,
                    raw_payload,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now(), now())
                RETURNING id, order_id, provider, provider_reference,
                          status, amount_cents, currency, metadata,
                          raw_payload, created_at, updated_at
                """,
                (
                    order_id,
                    provider,
                    provider_reference,
                    status,
                    amount_cents,
                    currency,
                    Jsonb(metadata or {}),
                    Jsonb(payload or {}),
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row)
