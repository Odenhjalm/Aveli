from __future__ import annotations

from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any, AsyncIterator, Mapping, Sequence
from uuid import UUID

from psycopg import Error as PsycopgError
from psycopg import errors as psycopg_errors
from psycopg.rows import dict_row

from ..repositories import special_offers as special_offers_repo
from .special_offers_service import SpecialOfferDomainError


@dataclass(frozen=True, slots=True)
class ResolvedSource:
    course_id: UUID
    position: int
    media_asset_id: UUID


async def resolve_special_offer_sources(
    db: Any,
    special_offer_id: UUID | str,
) -> list[ResolvedSource]:
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
            ordered_courses = list(aggregate.get("courses", []))
            if not ordered_courses:
                raise SpecialOfferDomainError(
                    "special_offer_invalid_course_count",
                    status_code=400,
                )

            ordered_course_ids = [
                _normalize_uuid(
                    course_row["course_id"],
                    code="special_offer_source_invalid_media",
                )
                for course_row in ordered_courses
            ]
            source_rows = await _fetch_course_cover_rows(
                conn,
                ordered_course_ids=ordered_course_ids,
            )
        except LookupError as exc:
            raise SpecialOfferDomainError(
                "special_offer_not_found",
                status_code=404,
            ) from exc
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc

    source_rows_by_course_id = {
        _normalize_uuid(
            row["course_id"],
            code="special_offer_source_invalid_media",
        ): dict(row)
        for row in source_rows
        if row.get("course_id") is not None
    }

    resolved_sources: list[ResolvedSource] = []
    for course_row in ordered_courses:
        course_id = _normalize_uuid(
            course_row["course_id"],
            code="special_offer_source_invalid_media",
        )
        position = _normalize_position(course_row["position"])
        source_row = source_rows_by_course_id.get(course_id)
        if source_row is None:
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )

        cover_media_id = source_row.get("cover_media_id")
        if cover_media_id is None:
            raise SpecialOfferDomainError(
                "special_offer_source_missing_cover",
                status_code=400,
            )

        media_asset_id = source_row.get("media_asset_id")
        if media_asset_id is None:
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )

        media_type = str(source_row.get("media_type") or "").strip()
        if media_type != "image":
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )

        media_purpose = str(source_row.get("purpose") or "").strip()
        if media_purpose != "course_cover":
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )

        media_state = str(source_row.get("state") or "").strip()
        if media_state != "ready":
            raise SpecialOfferDomainError(
                "special_offer_source_not_ready",
                status_code=400,
            )

        resolved_sources.append(
            ResolvedSource(
                course_id=UUID(course_id),
                position=position,
                media_asset_id=UUID(str(media_asset_id)),
            )
        )

    if len(resolved_sources) != len(ordered_courses):
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )

    return resolved_sources


async def _fetch_course_cover_rows(
    conn: Any,
    *,
    ordered_course_ids: Sequence[str],
) -> list[Mapping[str, Any]]:
    query = """
        SELECT c.id AS course_id,
               c.cover_media_id,
               ma.id AS media_asset_id,
               ma.state,
               ma.media_type,
               ma.purpose
          FROM app.courses AS c
          LEFT JOIN app.media_assets AS ma
            ON ma.id = c.cover_media_id
         WHERE c.id = ANY(%s::uuid[])
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (list(ordered_course_ids),))
        rows = await cur.fetchall()
    return [dict(row) for row in (rows or [])]


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


def _normalize_position(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    if value < 1:
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    return value


def _normalize_uuid(value: UUID | str, *, code: str) -> str:
    try:
        return str(UUID(str(value).strip()))
    except (TypeError, ValueError, AttributeError) as exc:
        raise SpecialOfferDomainError(code, status_code=400) from exc


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
    "ResolvedSource",
    "resolve_special_offer_sources",
]
