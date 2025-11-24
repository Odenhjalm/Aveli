from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg.rows import dict_row

from ..db import pool


async def grant_course_entitlement(
    user_id: str | UUID,
    course_slug: str,
    stripe_customer_id: str | None,
    payment_intent_id: str | None,
) -> dict[str, Any]:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.course_entitlements (
                    user_id,
                    course_slug,
                    stripe_customer_id,
                    stripe_payment_intent_id,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, now(), now())
                ON CONFLICT (user_id, course_slug)
                DO UPDATE SET
                    stripe_customer_id = COALESCE(EXCLUDED.stripe_customer_id, app.course_entitlements.stripe_customer_id),
                    stripe_payment_intent_id = COALESCE(EXCLUDED.stripe_payment_intent_id, app.course_entitlements.stripe_payment_intent_id),
                    updated_at = now()
                RETURNING id,
                          user_id,
                          course_slug,
                          stripe_customer_id,
                          stripe_payment_intent_id,
                          created_at,
                          updated_at
                """,
                (user_id, course_slug, stripe_customer_id, payment_intent_id),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row)


async def list_entitlements_for_user(user_id: str | UUID) -> list[str]:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT course_slug
                  FROM app.course_entitlements
                 WHERE user_id = %s
                 ORDER BY course_slug
                """,
                (user_id,),
            )
            rows = await cur.fetchall()
            await conn.commit()
    return [row["course_slug"] for row in rows]


__all__ = ["grant_course_entitlement", "list_entitlements_for_user"]
