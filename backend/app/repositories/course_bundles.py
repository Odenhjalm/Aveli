from __future__ import annotations

from typing import Any, Sequence

from psycopg.rows import dict_row

from ..db import get_conn, pool


BundleRow = dict[str, Any]
BundleCourseRow = dict[str, Any]


async def create_bundle(
    *,
    teacher_id: str,
    title: str,
    price_amount_cents: int,
) -> BundleRow:
    query = """
        INSERT INTO app.course_bundles (
            teacher_id,
            title,
            price_amount_cents,
            created_at,
            updated_at
        )
        VALUES (%s, %s, %s, now(), now())
        RETURNING id,
                  teacher_id,
                  title,
                  price_amount_cents,
                  sellable,
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
                    price_amount_cents,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row or {})


async def replace_bundle_courses(bundle_id: str, course_ids: Sequence[str]) -> None:
    rows = [
        (bundle_id, course_id, position)
        for position, course_id in enumerate(course_ids, start=1)
    ]
    delete_query = """
        DELETE FROM app.course_bundle_courses
         WHERE bundle_id = %s
    """
    insert_query = """
        INSERT INTO app.course_bundle_courses (bundle_id, course_id, position)
        VALUES (%s, %s, %s)
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        try:
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(delete_query, (bundle_id,))
                if rows:
                    await cur.executemany(insert_query, rows)
                await conn.commit()
        except Exception:
            await conn.rollback()
            raise


async def list_bundle_candidate_courses(course_ids: Sequence[str]) -> Sequence[BundleCourseRow]:
    normalized_ids = [str(course_id or "").strip() for course_id in course_ids]
    exact_ids = [course_id for course_id in normalized_ids if course_id]
    if not exact_ids:
        return []

    query = """
        SELECT c.id,
               c.teacher_id,
               c.visibility,
               c.content_ready,
               c.sellable
          FROM app.courses c
         WHERE c.id = any(%s::uuid[])
    """
    async with get_conn() as cur:
        await cur.execute(query, (exact_ids,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_bundle_composition(
    bundle_id: str,
    *,
    include_unsellable: bool = True,
) -> BundleRow | None:
    clauses = ["id = %s"]
    params: list[Any] = [bundle_id]
    if not include_unsellable:
        clauses.append("sellable is true")

    query = """
        SELECT id,
               teacher_id,
               title,
               price_amount_cents,
               sellable,
               created_at,
               updated_at
          FROM app.course_bundles
         WHERE {where_sql}
         LIMIT 1
    """.format(where_sql=" AND ".join(clauses))
    async with get_conn() as cur:
        await cur.execute(query, params)
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_bundle_mapping_subject(bundle_id: str) -> BundleRow | None:
    query = """
        SELECT id,
               teacher_id,
               title,
               price_amount_cents,
               sellable,
               stripe_product_id,
               active_stripe_price_id,
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


async def list_bundle_compositions(
    *,
    teacher_id: str | None = None,
) -> Sequence[BundleRow]:
    clauses: list[str] = []
    params: list[Any] = []
    if teacher_id:
        clauses.append("teacher_id = %s")
        params.append(teacher_id)
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    query = f"""
        SELECT id,
               teacher_id,
               title,
               price_amount_cents,
               sellable,
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


async def list_bundle_courses_composition(bundle_id: str) -> Sequence[BundleCourseRow]:
    query = """
        SELECT b.bundle_id,
               b.course_id,
               b.position,
               c.teacher_id,
               c.slug,
               c.title,
               c.visibility,
               c.content_ready,
               c.sellable AS course_sellable,
               c.price_amount_cents
          FROM app.course_bundle_courses b
          JOIN app.courses c ON c.id = b.course_id
         WHERE b.bundle_id = %s
         ORDER BY b.position, c.title
    """
    async with get_conn() as cur:
        await cur.execute(query, (bundle_id,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_bundle_checkout_courses(bundle_id: str) -> Sequence[BundleCourseRow]:
    query = """
        SELECT b.bundle_id,
               b.course_id,
               b.position,
               c.teacher_id,
               c.slug,
               c.title,
               c.visibility,
               c.content_ready,
               c.sellable AS course_sellable,
               c.price_amount_cents
          FROM app.course_bundle_courses b
          JOIN app.courses c ON c.id = b.course_id
         WHERE b.bundle_id = %s
         ORDER BY b.position, c.title
    """
    async with get_conn() as cur:
        await cur.execute(query, (bundle_id,))
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def update_bundle_details(
    bundle_id: str,
    *,
    title: str | None = None,
    price_amount_cents: int | None = None,
) -> BundleRow | None:
    assignments: list[str] = []
    params: list[Any] = []
    if title is not None:
        assignments.append("title = %s")
        params.append(title)
    if price_amount_cents is not None:
        assignments.append("price_amount_cents = %s")
        params.append(price_amount_cents)

    if not assignments:
        return await get_bundle_mapping_subject(bundle_id)

    assignments.append("updated_at = now()")
    params.append(bundle_id)
    query = f"""
        UPDATE app.course_bundles
           SET {", ".join(assignments)}
         WHERE id = %s
        RETURNING id
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_bundle_mapping_subject(bundle_id)


async def update_bundle_stripe_mapping(
    bundle_id: str,
    *,
    stripe_product_id: str,
    active_stripe_price_id: str,
) -> BundleRow | None:
    query = """
        UPDATE app.course_bundles
           SET stripe_product_id = %s,
               active_stripe_price_id = %s,
               updated_at = now()
         WHERE id = %s
        RETURNING id
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    stripe_product_id,
                    active_stripe_price_id,
                    bundle_id,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_bundle_mapping_subject(bundle_id)


async def update_bundle_sellability(
    bundle_id: str,
    *,
    sellable: bool,
) -> BundleRow | None:
    query = """
        UPDATE app.course_bundles
           SET sellable = %s,
               updated_at = now()
         WHERE id = %s
        RETURNING id
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (sellable, bundle_id))
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_bundle_mapping_subject(bundle_id)


async def update_bundle_price_amount(
    bundle_id: str,
    *,
    price_amount_cents: int,
) -> BundleRow | None:
    query = """
        UPDATE app.course_bundles
           SET price_amount_cents = %s,
               updated_at = now()
         WHERE id = %s
        RETURNING id
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (price_amount_cents, bundle_id))
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_bundle_mapping_subject(bundle_id)


async def delete_bundle(bundle_id: str) -> bool:
    query = """
        DELETE FROM app.course_bundles
         WHERE id = %s
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (bundle_id,))
            deleted = cur.rowcount > 0
            await conn.commit()
    return deleted


__all__ = [
    "BundleRow",
    "BundleCourseRow",
    "create_bundle",
    "delete_bundle",
    "get_bundle_composition",
    "get_bundle_mapping_subject",
    "list_bundle_candidate_courses",
    "replace_bundle_courses",
    "list_bundle_compositions",
    "list_bundle_courses_composition",
    "list_bundle_checkout_courses",
    "update_bundle_details",
    "update_bundle_price_amount",
    "update_bundle_sellability",
    "update_bundle_stripe_mapping",
]
