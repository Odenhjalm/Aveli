from __future__ import annotations

from psycopg.rows import dict_row

from ..db import get_conn, pool


async def get_customer_id_for_user(user_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT customer_id
              FROM app.stripe_customers
             WHERE user_id = %s
             LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
    return row["customer_id"] if row else None


async def get_user_id_by_customer(customer_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT user_id
              FROM app.stripe_customers
             WHERE customer_id = %s
             LIMIT 1
            """,
            (customer_id,),
        )
        row = await cur.fetchone()
    return str(row["user_id"]) if row else None


async def upsert_customer(user_id: str, customer_id: str) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.stripe_customers (user_id, customer_id, created_at, updated_at)
                VALUES (%s, %s, now(), now())
                ON CONFLICT (user_id)
                DO UPDATE SET customer_id = EXCLUDED.customer_id,
                              updated_at = now()
                """,
                (user_id, customer_id),
            )
            await conn.commit()
