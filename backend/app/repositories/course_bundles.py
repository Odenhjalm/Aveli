from __future__ import annotations

from typing import Any, Mapping, Sequence

from psycopg.rows import dict_row

from ..db import get_conn, pool


BundleRow = dict[str, Any]
BundleCourseRow = dict[str, Any]


async def create_bundle(
    *,
    teacher_id: str,
    title: str,
    description: str | None,
    price_amount_cents: int,
    currency: str,
    stripe_product_id: str | None = None,
    stripe_price_id: str | None = None,
    is_active: bool = True,
) -> BundleRow:
    query = """
        INSERT INTO app.course_bundles (
            teacher_id,
            title,
            description,
            price_amount_cents,
            currency,
            stripe_product_id,
            stripe_price_id,
            is_active,
            created_at,
            updated_at
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now(), now())
        RETURNING id,
                  teacher_id,
                  title,
                  description,
                  price_amount_cents,
                  currency,
                  stripe_product_id,
                  stripe_price_id,
                  is_active,
                  created_at,
                  updated_at
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    teacher_id,
                    title,
                    description,
                    price_amount_cents,
                    currency,
                    stripe_product_id,
                    stripe_price_id,
                    is_active,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row or {})


async def update_bundle(bundle_id: str, payload: Mapping[str, Any]) -> BundleRow | None:
    if not payload:
        return await get_bundle(bundle_id)

    updates: list[str] = []
    params: list[Any] = []
    for key in (
        "title",
        "description",
        "price_amount_cents",
        "currency",
        "stripe_product_id",
        "stripe_price_id",
        "is_active",
    ):
        if key in payload:
            updates.append(f"{key} = %s")
            params.append(payload[key])

    if not updates:
        return await get_bundle(bundle_id)

    params.append(bundle_id)
    query = f"""
        UPDATE app.course_bundles
           SET {', '.join(updates)},
               updated_at = now()
         WHERE id = %s
        RETURNING id,
                  teacher_id,
                  title,
                  description,
                  price_amount_cents,
                  currency,
                  stripe_product_id,
                  stripe_price_id,
                  is_active,
                  created_at,
                  updated_at
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def get_bundle(bundle_id: str) -> BundleRow | None:
    query = """
        SELECT id,
               teacher_id,
               title,
               description,
               price_amount_cents,
               currency,
               stripe_product_id,
               stripe_price_id,
               is_active,
               created_at,
               updated_at
          FROM app.course_bundles
         WHERE id = %s
         LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (bundle_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def list_bundles(
    *,
    teacher_id: str | None = None,
    active_only: bool = True,
) -> Sequence[BundleRow]:
    clauses: list[str] = []
    params: list[Any] = []
    if teacher_id:
        clauses.append("teacher_id = %s")
        params.append(teacher_id)
    if active_only:
        clauses.append("is_active = true")
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    query = f"""
        SELECT id,
               teacher_id,
               title,
               description,
               price_amount_cents,
               currency,
               stripe_product_id,
               stripe_price_id,
               is_active,
               created_at,
               updated_at
          FROM app.course_bundles
          {where}
      ORDER BY updated_at DESC
    """
    async with get_conn() as cur:
        await cur.execute(query, params)
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def add_course_to_bundle(bundle_id: str, course_id: str, *, position: int | None = None) -> None:
    position_value = position if position is not None else 0
    query = """
        INSERT INTO app.course_bundle_courses (bundle_id, course_id, position)
        VALUES (%s, %s, %s)
        ON CONFLICT (bundle_id, course_id) DO UPDATE
           SET position = EXCLUDED.position
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (bundle_id, course_id, position_value))
            await conn.commit()


async def list_bundle_courses(bundle_id: str) -> Sequence[BundleCourseRow]:
    query = """
        SELECT b.bundle_id,
               b.course_id,
               b.position,
               c.slug,
               c.title,
               c.price_amount_cents,
               c.currency,
               c.stripe_price_id,
               c.stripe_product_id
          FROM app.course_bundle_courses b
          JOIN app.courses c ON c.id = b.course_id
         WHERE b.bundle_id = %s
         ORDER BY b.position, c.title
    """
    async with get_conn() as cur:
        await cur.execute(query, (bundle_id,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


__all__ = [
    "BundleRow",
    "BundleCourseRow",
    "create_bundle",
    "update_bundle",
    "get_bundle",
    "list_bundles",
    "add_course_to_bundle",
    "list_bundle_courses",
]
