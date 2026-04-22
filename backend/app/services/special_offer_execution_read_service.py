from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, Mapping
from uuid import UUID

from psycopg import Error as PsycopgError
from psycopg import errors as psycopg_errors
from psycopg.rows import dict_row

from .special_offer_text_catalog import get_special_offer_status_text_id
from .special_offers_service import SpecialOfferDomainError, get_offer


async def get_special_offer_execution_state(
    db: Any,
    *,
    special_offer_id: UUID | str,
) -> dict[str, Any]:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    return await _build_execution_state(
        db,
        special_offer_id=normalized_special_offer_id,
    )


async def _build_execution_state(
    db: Any,
    *,
    special_offer_id: str,
    latest_result: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    offer = await get_offer(db, special_offer_id)
    canonical_source_count = len(offer.courses)

    async with _connection_scope(db) as conn:
        active_output = await _fetch_active_output_row(
            conn,
            special_offer_id=special_offer_id,
        )
        latest_attempt = await _fetch_latest_attempt_for_state(
            conn,
            special_offer_id=special_offer_id,
            state_hash=str(offer.state_hash),
        )
        overwrite_applied = False
        if latest_result is not None:
            overwrite_applied = bool(latest_result.get("overwrite_applied"))
        elif latest_attempt is not None and str(latest_attempt.get("status") or "").strip() == "succeeded":
            overwrite_applied = await _has_prior_succeeded_attempt(
                conn,
                special_offer_id=special_offer_id,
                attempt_id=_stringify_uuid(latest_attempt.get("id")),
            )

    active_output_id = _stringify_uuid(active_output.get("id")) if active_output else None
    active_media_asset_id = (
        _stringify_uuid(active_output.get("media_asset_id"))
        if active_output
        else None
    )
    active_output_hash = (
        str(active_output.get("state_hash") or "").strip()
        if active_output
        else ""
    )
    image_current = bool(active_output) and active_output_hash == str(offer.state_hash)
    image_required = not image_current

    if image_current and _normalize_source_count(active_output.get("persisted_source_count")) != canonical_source_count:
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )

    source_count = canonical_source_count
    if latest_result is not None and "source_count" in latest_result:
        latest_source_count = _normalize_source_count(latest_result.get("source_count"))
        if latest_source_count != canonical_source_count:
            raise SpecialOfferDomainError(
                "special_offer_output_conflict",
                status_code=409,
            )
        source_count = latest_source_count

    attempt_id = None
    if latest_result is not None and latest_result.get("attempt_id") is not None:
        attempt_id = _stringify_uuid(latest_result.get("attempt_id"))
    elif latest_attempt is not None:
        attempt_id = _stringify_uuid(latest_attempt.get("id"))

    status = None
    if latest_result is not None:
        status = latest_result.get("status")
    elif latest_attempt is not None:
        status = str(latest_attempt.get("status"))
    else:
        status = None
    text_id = get_special_offer_status_text_id(
        status=status,
        overwrite_applied=overwrite_applied,
        has_active_output=bool(active_output),
    )

    return {
        "special_offer_id": _stringify_uuid(offer.id),
        "active_output_id": active_output_id,
        "active_media_asset_id": active_media_asset_id,
        "state_hash": str(offer.state_hash),
        "attempt_id": attempt_id,
        "status": status,
        "text_id": text_id,
        "source_count": source_count,
        "overwrite_applied": overwrite_applied,
        "image_current": image_current,
        "image_required": image_required,
    }


async def _fetch_active_output_row(
    conn: Any,
    *,
    special_offer_id: str,
) -> dict[str, Any] | None:
    query = """
        select
            o.id,
            o.media_asset_id,
            o.state_hash,
            count(s.id)::int as persisted_source_count
        from app.special_offer_composite_image_outputs as o
        left join app.special_offer_composite_image_sources as s
          on s.output_id = o.id
        where o.special_offer_id = %s::uuid
        group by o.id, o.media_asset_id, o.state_hash
    """
    try:
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (special_offer_id,))
            row = await cur.fetchone()
    except PsycopgError as exc:
        raise _map_database_error(exc) from exc
    return dict(row) if row else None


async def _fetch_latest_attempt_for_state(
    conn: Any,
    *,
    special_offer_id: str,
    state_hash: str,
) -> dict[str, Any] | None:
    query = """
        select
            a.id,
            a.status,
            a.created_at at time zone 'UTC' as created_at_utc
        from app.special_offer_composite_image_attempts as a
        where a.special_offer_id = %s::uuid
          and a.state_hash = %s
        order by a.created_at desc, a.id desc
        limit 1
    """
    try:
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (special_offer_id, state_hash))
            row = await cur.fetchone()
    except PsycopgError as exc:
        raise _map_database_error(exc) from exc
    return dict(row) if row else None


async def _has_prior_succeeded_attempt(
    conn: Any,
    *,
    special_offer_id: str,
    attempt_id: str,
) -> bool:
    query = """
        select exists (
            select 1
            from app.special_offer_composite_image_attempts as a
            where a.special_offer_id = %s::uuid
              and a.status = 'succeeded'
              and a.id <> %s::uuid
        ) as has_prior_success
    """
    try:
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (special_offer_id, attempt_id))
            row = await cur.fetchone()
    except PsycopgError as exc:
        raise _map_database_error(exc) from exc
    return bool(row and row.get("has_prior_success"))


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
        "special_offer_domain_unavailable",
        status_code=503,
    )


def _normalize_uuid(value: UUID | str, *, code: str) -> str:
    try:
        return str(UUID(str(value).strip()))
    except (TypeError, ValueError, AttributeError) as exc:
        raise SpecialOfferDomainError(code, status_code=400) from exc


def _stringify_uuid(value: Any) -> str:
    try:
        return str(UUID(str(value).strip()))
    except (TypeError, ValueError, AttributeError) as exc:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        ) from exc


def _normalize_source_count(value: Any) -> int:
    try:
        normalized = int(value)
    except (TypeError, ValueError) as exc:
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        ) from exc
    if normalized < 0:
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )
    return normalized


def _map_database_error(exc: PsycopgError) -> SpecialOfferDomainError:
    if isinstance(exc, (psycopg_errors.UndefinedTable, psycopg_errors.UndefinedColumn)):
        return SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    return SpecialOfferDomainError(
        "special_offer_domain_unavailable",
        status_code=503,
    )


__all__ = [
    "get_special_offer_execution_state",
]
