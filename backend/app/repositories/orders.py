from __future__ import annotations

from typing import Any, Mapping, Sequence
from uuid import UUID

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool

_ORDER_SELECT = """
    SELECT id,
           user_id,
           course_id,
           bundle_id,
           order_type,
           amount_cents,
           currency,
           status,
           stripe_checkout_id,
           stripe_payment_intent,
           stripe_subscription_id,
           stripe_customer_id,
           metadata,
           created_at,
           updated_at
      FROM app.orders
"""


async def create_order(
    *,
    user_id: str | UUID,
    course_id: str | UUID | None,
    bundle_id: str | UUID | None = None,
    amount_cents: int,
    currency: str,
    metadata: dict[str, Any] | None = None,
    order_type: str | None = None,
    stripe_subscription_id: str | None = None,
    stripe_customer_id: str | None = None,
) -> dict[str, Any]:
    normalized_order_type = (order_type or "one_off").lower()
    if normalized_order_type == "one_off":
        if course_id is None or bundle_id is not None:
            raise ValueError("one_off orders require exactly one course target")
    elif normalized_order_type == "bundle":
        if bundle_id is None or course_id is not None:
            raise ValueError("bundle orders require exactly one bundle target")
    elif normalized_order_type == "subscription":
        if course_id is not None or bundle_id is not None:
            raise ValueError("subscription orders cannot target course or bundle")
    else:
        raise ValueError("unsupported order_type")

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.orders (
                    user_id,
                    course_id,
                    bundle_id,
                    order_type,
                    amount_cents,
                    currency,
                    status,
                    stripe_checkout_id,
                    stripe_payment_intent,
                    stripe_subscription_id,
                    stripe_customer_id,
                    metadata
                )
                VALUES (%s, %s, %s, %s, %s, %s, 'pending', NULL, NULL, %s, %s, %s)
                RETURNING id,
                          user_id,
                          course_id,
                          bundle_id,
                          order_type,
                          amount_cents,
                          currency,
                          status,
                          stripe_checkout_id,
                          stripe_payment_intent,
                          stripe_subscription_id,
                          stripe_customer_id,
                          metadata,
                          created_at,
                          updated_at
                """,
                (
                    user_id,
                    course_id,
                    bundle_id,
                    normalized_order_type,
                    amount_cents,
                    currency,
                    stripe_subscription_id,
                    stripe_customer_id,
                    Jsonb(metadata or {}),
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row)


async def create_bundle_order_with_snapshot(
    *,
    user_id: str | UUID,
    bundle_id: str | UUID,
    amount_cents: int,
    currency: str,
    snapshot_courses: Sequence[Mapping[str, Any]],
    metadata: dict[str, Any] | None = None,
    stripe_customer_id: str | None = None,
) -> dict[str, Any]:
    snapshot_rows = [
        (bundle_id, row["course_id"], int(row["position"]))
        for row in snapshot_courses
    ]
    if not snapshot_rows:
        raise ValueError("bundle orders require a non-empty course snapshot")

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        try:
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    INSERT INTO app.orders (
                        user_id,
                        course_id,
                        bundle_id,
                        order_type,
                        amount_cents,
                        currency,
                        status,
                        stripe_checkout_id,
                        stripe_payment_intent,
                        stripe_subscription_id,
                        stripe_customer_id,
                        metadata
                    )
                    VALUES (%s, NULL, %s, 'bundle', %s, %s, 'pending', NULL, NULL, NULL, %s, %s)
                    RETURNING id,
                              user_id,
                              course_id,
                              bundle_id,
                              order_type,
                              amount_cents,
                              currency,
                              status,
                              stripe_checkout_id,
                              stripe_payment_intent,
                              stripe_subscription_id,
                              stripe_customer_id,
                              metadata,
                              created_at,
                              updated_at
                    """,
                    (
                        user_id,
                        bundle_id,
                        amount_cents,
                        currency,
                        stripe_customer_id,
                        Jsonb(metadata or {}),
                    ),
                )
                order = await cur.fetchone()
                if order is None:
                    raise RuntimeError("bundle order insert returned no row")

                await cur.executemany(
                    """
                    INSERT INTO app.bundle_order_courses (
                        order_id,
                        bundle_id,
                        course_id,
                        position
                    )
                    VALUES (%s, %s, %s, %s)
                    """,
                    [
                        (order["id"], row_bundle_id, course_id, position)
                        for row_bundle_id, course_id, position in snapshot_rows
                    ],
                )
            await conn.commit()
            return dict(order)
        except Exception:
            await conn.rollback()
            raise


async def get_order(order_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            f"""
            {_ORDER_SELECT}
             WHERE id = %s
             LIMIT 1
            """,
            (order_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def list_bundle_order_courses(order_id: str | UUID) -> list[dict[str, Any]]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id,
                   order_id,
                   bundle_id,
                   course_id,
                   position,
                   created_at
              FROM app.bundle_order_courses
             WHERE order_id = %s
             ORDER BY position
            """,
            (order_id,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_user_order(
    order_id: str | UUID,
    user_id: str | UUID,
) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            f"""
            {_ORDER_SELECT}
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
        {_ORDER_SELECT}
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
            f"""
            {_ORDER_SELECT}
             WHERE user_id = %s AND course_id = %s
             ORDER BY created_at DESC
             LIMIT 1
            """,
            (user_id, course_id),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_order_by_checkout_id(checkout_id: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            f"""
            {_ORDER_SELECT}
             WHERE stripe_checkout_id = %s
             ORDER BY updated_at DESC
             LIMIT 1
            """,
            (checkout_id,),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_order_by_payment_intent(payment_intent: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            f"""
            {_ORDER_SELECT}
             WHERE stripe_payment_intent = %s
             ORDER BY updated_at DESC
             LIMIT 1
            """,
            (payment_intent,),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_order_by_subscription_id(subscription_id: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            f"""
            {_ORDER_SELECT}
             WHERE stripe_subscription_id = %s
             ORDER BY updated_at DESC
             LIMIT 1
            """,
            (subscription_id,),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def set_order_checkout_reference(
    *,
    order_id: str | UUID,
    checkout_id: str | None,
    payment_intent: str | None,
    subscription_id: str | None = None,
    customer_id: str | None = None,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.orders
                   SET stripe_checkout_id = COALESCE(%s, stripe_checkout_id),
                       stripe_payment_intent = COALESCE(%s, stripe_payment_intent),
                       stripe_subscription_id = COALESCE(%s, stripe_subscription_id),
                       stripe_customer_id = COALESCE(%s, stripe_customer_id),
                       updated_at = now()
                 WHERE id = %s
                 RETURNING id,
                           user_id,
                           course_id,
                           bundle_id,
                           order_type,
                           amount_cents,
                           currency,
                           status,
                           stripe_checkout_id,
                           stripe_payment_intent,
                           stripe_subscription_id,
                           stripe_customer_id,
                           metadata,
                           created_at,
                           updated_at
                """,
                (checkout_id, payment_intent, subscription_id, customer_id, order_id),
            )
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        row = await _execute(conn)
        await conn.commit()
        return row


async def mark_order_refunded(
    order_id: str | UUID,
    *,
    payment_intent: str | None = None,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH existing AS (
                    SELECT status
                      FROM app.orders
                     WHERE id = %s
                     FOR UPDATE
                ),
                updated AS (
                    UPDATE app.orders
                       SET status = 'refunded',
                           stripe_payment_intent = COALESCE(%s, stripe_payment_intent),
                           updated_at = now()
                     WHERE id = %s
                 RETURNING id,
                           user_id,
                           course_id,
                           bundle_id,
                           order_type,
                           amount_cents,
                           currency,
                           status,
                           stripe_checkout_id,
                           stripe_payment_intent,
                           stripe_subscription_id,
                           stripe_customer_id,
                           metadata,
                           created_at,
                           updated_at
                )
                SELECT updated.*,
                       existing.status AS previous_status
                  FROM updated
             LEFT JOIN existing ON true
                """,
                (order_id, payment_intent, order_id),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None
