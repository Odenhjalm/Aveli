from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, Mapping, Sequence
from uuid import UUID

from psycopg import Error as PsycopgError
from psycopg import errors as psycopg_errors
from psycopg.rows import dict_row

from ..repositories import special_offers as special_offers_repo
from ..schemas.special_offers import (
    SpecialOfferCourse,
    SpecialOfferRead,
)


class SpecialOfferDomainError(Exception):
    status_code = 400

    def __init__(
        self,
        code: str,
        *,
        status_code: int | None = None,
        context: Mapping[str, Any] | None = None,
    ) -> None:
        super().__init__(code)
        if status_code is not None:
            self.status_code = status_code
        self.code = code
        self.context = dict(context or {})


async def create_offer(
    db: Any,
    teacher_id: UUID | str,
    course_ids: list[UUID | str],
    price_amount_cents: int,
) -> SpecialOfferRead:
    normalized_teacher_id = _normalize_uuid(
        teacher_id,
        code="special_offer_invalid_teacher_id",
    )
    normalized_course_ids = _normalize_ordered_course_ids(course_ids)
    normalized_price_amount = _validate_price_amount(price_amount_cents)

    async with _write_transaction(db) as conn:
        await _validate_selected_courses(
            conn,
            teacher_id=normalized_teacher_id,
            course_ids=normalized_course_ids,
        )
        try:
            created_row = await special_offers_repo.create_special_offer(
                conn,
                teacher_id=normalized_teacher_id,
                price_amount_cents=normalized_price_amount,
            )
            special_offer_id = str(created_row["id"])
            # IMPORTANT:
            # Course replacement relies on a DEFERRABLE constraint trigger in the database.
            # The intermediate state (0 rows) is allowed inside the transaction only.
            # Final commit enforces 1..5 rows and contiguous ordering.
            await special_offers_repo.replace_special_offer_courses(
                conn,
                special_offer_id=special_offer_id,
                ordered_course_ids=normalized_course_ids,
            )
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc

    return await get_offer(db, special_offer_id)


async def update_offer_courses(
    db: Any,
    special_offer_id: UUID | str,
    teacher_id: UUID | str,
    course_ids: list[UUID | str],
) -> SpecialOfferRead:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    normalized_teacher_id = _normalize_uuid(
        teacher_id,
        code="special_offer_invalid_teacher_id",
    )
    normalized_course_ids = _normalize_ordered_course_ids(course_ids)

    async with _write_transaction(db) as conn:
        await _require_owned_special_offer(
            conn,
            special_offer_id=normalized_special_offer_id,
            teacher_id=normalized_teacher_id,
        )
        await _validate_selected_courses(
            conn,
            teacher_id=normalized_teacher_id,
            course_ids=normalized_course_ids,
        )
        try:
            # IMPORTANT:
            # Course replacement relies on a DEFERRABLE constraint trigger in the database.
            # The intermediate state (0 rows) is allowed inside the transaction only.
            # Final commit enforces 1..5 rows and contiguous ordering.
            await special_offers_repo.replace_special_offer_courses(
                conn,
                special_offer_id=normalized_special_offer_id,
                ordered_course_ids=normalized_course_ids,
            )
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc

    return await get_offer(db, normalized_special_offer_id)


async def update_offer_price(
    db: Any,
    special_offer_id: UUID | str,
    teacher_id: UUID | str,
    price_amount_cents: int,
) -> SpecialOfferRead:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    normalized_teacher_id = _normalize_uuid(
        teacher_id,
        code="special_offer_invalid_teacher_id",
    )
    normalized_price_amount = _validate_price_amount(price_amount_cents)

    async with _write_transaction(db) as conn:
        await _require_owned_special_offer(
            conn,
            special_offer_id=normalized_special_offer_id,
            teacher_id=normalized_teacher_id,
        )
        try:
            await special_offers_repo.update_special_offer_price(
                conn,
                special_offer_id=normalized_special_offer_id,
                price_amount_cents=normalized_price_amount,
            )
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc

    return await get_offer(db, normalized_special_offer_id)


async def get_offer(
    db: Any,
    special_offer_id: UUID | str,
) -> SpecialOfferRead:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    async with _connection_scope(db) as conn:
        try:
            aggregate = await special_offers_repo.get_special_offer_with_courses(
                conn,
                special_offer_id=normalized_special_offer_id,
            )
        except LookupError as exc:
            raise SpecialOfferDomainError(
                "special_offer_not_found",
                status_code=404,
            ) from exc
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc
    return _build_read_model(aggregate)


@asynccontextmanager
async def _connection_scope(db: Any) -> AsyncIterator[Any]:
    if (
        hasattr(db, "cursor")
        and hasattr(db, "commit")
        and hasattr(db, "rollback")
    ):
        yield db
        return
    if hasattr(db, "connection"):
        async with db.connection() as conn:  # type: ignore[attr-defined]
            yield conn
        return
    raise SpecialOfferDomainError(
        "special_offer_invalid_db_handle",
        status_code=500,
    )


@asynccontextmanager
async def _write_transaction(db: Any) -> AsyncIterator[Any]:
    async with _connection_scope(db) as conn:
        try:
            yield conn
        except Exception:
            await conn.rollback()
            raise
        else:
            await conn.commit()


async def _require_owned_special_offer(
    conn: Any,
    *,
    special_offer_id: str,
    teacher_id: str,
) -> None:
    query = """
        SELECT so.teacher_id
          FROM app.special_offers AS so
         WHERE so.id = %s::uuid
         LIMIT 1
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (special_offer_id,))
        row = await cur.fetchone()

    if row is None:
        raise SpecialOfferDomainError(
            "special_offer_not_found",
            status_code=404,
        )
    if str(row.get("teacher_id") or "").strip() != teacher_id:
        raise SpecialOfferDomainError(
            "special_offer_forbidden",
            status_code=403,
        )


async def _validate_selected_courses(
    conn: Any,
    *,
    teacher_id: str,
    course_ids: Sequence[str],
) -> None:
    query = """
        SELECT c.id,
               c.teacher_id
          FROM app.courses AS c
         WHERE c.id = ANY(%s::uuid[])
         ORDER BY c.id ASC
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (list(course_ids),))
        rows = await cur.fetchall()

    if len(rows or []) != len(course_ids):
        raise SpecialOfferDomainError(
            "special_offer_course_not_found",
            status_code=404,
        )

    for row in rows or []:
        if str(row.get("teacher_id") or "").strip() != teacher_id:
            raise SpecialOfferDomainError(
                "special_offer_course_teacher_mismatch",
                status_code=403,
            )


def _normalize_ordered_course_ids(course_ids: Sequence[UUID | str]) -> list[str]:
    if isinstance(course_ids, (str, bytes)):
        raise SpecialOfferDomainError(
            "special_offer_invalid_course_ids",
            status_code=400,
        )
    normalized_course_ids = [
        _normalize_uuid(course_id, code="special_offer_invalid_course_id")
        for course_id in course_ids
    ]
    if len(normalized_course_ids) < 1 or len(normalized_course_ids) > 5:
        raise SpecialOfferDomainError(
            "special_offer_invalid_course_count",
            status_code=400,
        )
    if len(normalized_course_ids) != len(set(normalized_course_ids)):
        raise SpecialOfferDomainError(
            "special_offer_duplicate_courses",
            status_code=400,
        )
    return normalized_course_ids


def _validate_price_amount(price_amount_cents: Any) -> int:
    if isinstance(price_amount_cents, bool) or not isinstance(price_amount_cents, int):
        raise SpecialOfferDomainError(
            "special_offer_invalid_price_amount",
            status_code=400,
        )
    if price_amount_cents <= 0:
        raise SpecialOfferDomainError(
            "special_offer_invalid_price_amount",
            status_code=400,
        )
    return price_amount_cents


def _normalize_uuid(value: UUID | str, *, code: str) -> str:
    try:
        return str(UUID(str(value).strip()))
    except (TypeError, ValueError, AttributeError) as exc:
        raise SpecialOfferDomainError(code, status_code=400) from exc


def _build_read_model(aggregate: Mapping[str, Any]) -> SpecialOfferRead:
    return SpecialOfferRead(
        id=aggregate["id"],
        teacher_id=aggregate["teacher_id"],
        price_amount_cents=int(aggregate["price_amount_cents"]),
        state_hash=str(aggregate["state_hash"]),
        courses=[
            SpecialOfferCourse(
                course_id=course_row["course_id"],
                position=int(course_row["position"]),
            )
            for course_row in aggregate.get("courses", [])
        ],
    )


def _map_database_error(exc: PsycopgError) -> SpecialOfferDomainError:
    if isinstance(exc, (psycopg_errors.UndefinedTable, psycopg_errors.UndefinedColumn)):
        return SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    if isinstance(
        exc,
        (
            psycopg_errors.CheckViolation,
            psycopg_errors.ForeignKeyViolation,
            psycopg_errors.NotNullViolation,
            psycopg_errors.UniqueViolation,
        ),
    ):
        return SpecialOfferDomainError(
            "special_offer_domain_constraint_violation",
            status_code=400,
        )
    return SpecialOfferDomainError(
        "special_offer_domain_persistence_failed",
        status_code=503,
    )


__all__ = [
    "SpecialOfferDomainError",
    "create_offer",
    "get_offer",
    "update_offer_courses",
    "update_offer_price",
]
