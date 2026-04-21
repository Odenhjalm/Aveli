from __future__ import annotations

from typing import Any, Sequence
from uuid import UUID

from psycopg.rows import dict_row


SpecialOfferRow = dict[str, Any]
SpecialOfferCourseRow = dict[str, Any]
SpecialOfferAggregate = dict[str, Any]

_SPECIAL_OFFER_COLUMNS = """
    so.id,
    so.teacher_id,
    so.price_amount_cents,
    so.state_hash,
    so.created_at,
    so.updated_at
"""

_SPECIAL_OFFER_COURSE_COLUMNS = """
    soc.special_offer_id,
    soc.course_id,
    soc.position
"""


async def create_special_offer(
    conn: Any,
    teacher_id: UUID | str,
    price_amount_cents: int,
) -> SpecialOfferRow:
    query = f"""
        INSERT INTO app.special_offers (
            teacher_id,
            price_amount_cents
        )
        VALUES (%s::uuid, %s)
        RETURNING {_SPECIAL_OFFER_COLUMNS}
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(
            query,
            (
                str(teacher_id),
                price_amount_cents,
            ),
        )
        row = await cur.fetchone()
    if row is None:
        raise RuntimeError("special_offer_create_missing_row")
    return dict(row)


async def replace_special_offer_courses(
    conn: Any,
    special_offer_id: UUID | str,
    ordered_course_ids: Sequence[UUID | str],
) -> None:
    rows = [
        (
            str(special_offer_id),
            str(course_id),
            position,
        )
        for position, course_id in enumerate(ordered_course_ids, start=1)
    ]
    delete_query = """
        DELETE FROM app.special_offer_courses
         WHERE special_offer_id = %s::uuid
    """
    insert_query = """
        INSERT INTO app.special_offer_courses (
            special_offer_id,
            course_id,
            position
        )
        VALUES (%s::uuid, %s::uuid, %s)
    """
    async with conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(delete_query, (str(special_offer_id),))
        if rows:
            await cur.executemany(insert_query, rows)


async def update_special_offer_price(
    conn: Any,
    special_offer_id: UUID | str,
    price_amount_cents: int,
) -> SpecialOfferRow:
    query = f"""
        UPDATE app.special_offers AS so
           SET price_amount_cents = %s
         WHERE so.id = %s::uuid
        RETURNING {_SPECIAL_OFFER_COLUMNS}
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(
            query,
            (
                price_amount_cents,
                str(special_offer_id),
            ),
        )
        row = await cur.fetchone()
    if row is None:
        raise LookupError("special_offer_not_found")
    return dict(row)


async def get_special_offer_with_courses(
    conn: Any,
    special_offer_id: UUID | str,
) -> SpecialOfferAggregate:
    offer_row = await _get_special_offer_row(conn, special_offer_id)
    if offer_row is None:
        raise LookupError("special_offer_not_found")

    courses_query = f"""
        SELECT {_SPECIAL_OFFER_COURSE_COLUMNS}
          FROM app.special_offer_courses AS soc
         WHERE soc.special_offer_id = %s::uuid
         ORDER BY soc.position ASC, soc.course_id ASC
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(courses_query, (str(special_offer_id),))
        course_rows = await cur.fetchall()

    aggregate = dict(offer_row)
    aggregate["courses"] = [dict(row) for row in (course_rows or [])]
    return aggregate


async def _get_special_offer_row(
    conn: Any,
    special_offer_id: UUID | str,
) -> SpecialOfferRow | None:
    query = f"""
        SELECT {_SPECIAL_OFFER_COLUMNS}
          FROM app.special_offers AS so
         WHERE so.id = %s::uuid
         LIMIT 1
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (str(special_offer_id),))
        row = await cur.fetchone()
    return dict(row) if row else None


__all__ = [
    "SpecialOfferAggregate",
    "SpecialOfferCourseRow",
    "SpecialOfferRow",
    "create_special_offer",
    "get_special_offer_with_courses",
    "replace_special_offer_courses",
    "update_special_offer_price",
]
