from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, Mapping, Sequence
from uuid import UUID

import httpx
from psycopg import Error as PsycopgError
from psycopg import errors as psycopg_errors
from psycopg.rows import dict_row

from ..config import settings
from ..repositories import special_offers as special_offers_repo
from .special_offer_composite_service import create_special_offer_composite
from .special_offer_source_resolution_service import (
    ResolvedSource,
    resolve_special_offer_sources,
)
from .special_offers_service import SpecialOfferDomainError, get_offer
from .storage_service import (
    StorageObjectNotFoundError,
    StorageServiceError,
    get_storage_service,
    storage_http_limits,
    storage_http_timeout,
)


async def create_special_offer_execution(
    db: Any,
    *,
    teacher_id: UUID | str,
    course_ids: Sequence[UUID | str],
    price_amount_cents: int,
) -> dict[str, Any]:
    created_offer = await _create_offer_state(
        db,
        teacher_id=teacher_id,
        course_ids=course_ids,
        price_amount_cents=price_amount_cents,
    )
    return await generate_special_offer_image(
        db,
        special_offer_id=created_offer.id,
        teacher_id=created_offer.teacher_id,
    )


async def update_special_offer_execution(
    db: Any,
    *,
    special_offer_id: UUID | str,
    teacher_id: UUID | str,
    course_ids: Sequence[UUID | str] | None = None,
    price_amount_cents: int | None = None,
) -> dict[str, Any]:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    normalized_teacher_id = _normalize_uuid(
        teacher_id,
        code="special_offer_invalid_teacher_id",
    )

    current_offer = await get_offer(db, normalized_special_offer_id)
    current_course_ids = [str(course.course_id) for course in current_offer.courses]

    normalized_course_ids: list[str] | None = None
    if course_ids is not None:
        normalized_course_ids = _normalize_ordered_course_ids(course_ids)

    normalized_price_amount: int | None = None
    if price_amount_cents is not None:
        normalized_price_amount = _validate_price_amount(price_amount_cents)

    courses_changed = (
        normalized_course_ids is not None
        and normalized_course_ids != current_course_ids
    )
    price_changed = (
        normalized_price_amount is not None
        and normalized_price_amount != current_offer.price_amount_cents
    )
    if not courses_changed and not price_changed:
        return await get_special_offer_execution_state(
            db,
            special_offer_id=normalized_special_offer_id,
        )

    async with _write_transaction(db) as conn:
        await _require_owned_special_offer(
            conn,
            special_offer_id=normalized_special_offer_id,
            teacher_id=normalized_teacher_id,
        )
        if courses_changed:
            await _validate_selected_courses(
                conn,
                teacher_id=normalized_teacher_id,
                course_ids=normalized_course_ids or [],
            )
        try:
            if price_changed:
                await special_offers_repo.update_special_offer_price(
                    conn,
                    special_offer_id=normalized_special_offer_id,
                    price_amount_cents=normalized_price_amount,
                )
            if courses_changed:
                # IMPORTANT:
                # Course replacement relies on the DEFERRABLE course-set trigger.
                # The transaction may observe an intermediate empty set, but the
                # final commit must satisfy the 1..5 contiguous-position contract.
                await special_offers_repo.replace_special_offer_courses(
                    conn,
                    special_offer_id=normalized_special_offer_id,
                    ordered_course_ids=normalized_course_ids or [],
                )
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc

    return await get_special_offer_execution_state(
        db,
        special_offer_id=normalized_special_offer_id,
    )


async def generate_special_offer_image(
    db: Any,
    *,
    special_offer_id: UUID | str,
    teacher_id: UUID | str,
) -> dict[str, Any]:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    normalized_teacher_id = _normalize_uuid(
        teacher_id,
        code="special_offer_invalid_teacher_id",
    )

    offer = await get_offer(db, normalized_special_offer_id)
    await _ensure_owned_offer(
        db,
        special_offer_id=normalized_special_offer_id,
        teacher_id=normalized_teacher_id,
    )
    active_output = await _get_active_output(
        db,
        special_offer_id=normalized_special_offer_id,
    )
    if active_output is not None:
        raise SpecialOfferDomainError(
            "special_offer_asset_already_exists",
            status_code=409,
        )

    source_bytes = await _load_canonical_source_bytes(
        db,
        special_offer_id=normalized_special_offer_id,
    )
    result = await create_special_offer_composite(
        db,
        special_offer_id=normalized_special_offer_id,
        source_bytes=source_bytes,
        price_amount_cents=offer.price_amount_cents,
        overwrite=False,
    )
    return await _build_execution_state(
        db,
        special_offer_id=normalized_special_offer_id,
        latest_result=result,
    )


async def regenerate_special_offer_image(
    db: Any,
    *,
    special_offer_id: UUID | str,
    teacher_id: UUID | str,
    confirm_overwrite: bool = False,
) -> dict[str, Any]:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    normalized_teacher_id = _normalize_uuid(
        teacher_id,
        code="special_offer_invalid_teacher_id",
    )
    if not bool(confirm_overwrite):
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )

    offer = await get_offer(db, normalized_special_offer_id)
    await _ensure_owned_offer(
        db,
        special_offer_id=normalized_special_offer_id,
        teacher_id=normalized_teacher_id,
    )
    active_output = await _get_active_output(
        db,
        special_offer_id=normalized_special_offer_id,
    )
    if active_output is None:
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )

    source_bytes = await _load_canonical_source_bytes(
        db,
        special_offer_id=normalized_special_offer_id,
    )
    result = await create_special_offer_composite(
        db,
        special_offer_id=normalized_special_offer_id,
        source_bytes=source_bytes,
        price_amount_cents=offer.price_amount_cents,
        overwrite=True,
    )
    return await _build_execution_state(
        db,
        special_offer_id=normalized_special_offer_id,
        latest_result=result,
    )


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
        elif latest_attempt is not None and str(latest_attempt.get("status")) == "succeeded":
            overwrite_applied = await _has_prior_succeeded_attempt(
                conn,
                special_offer_id=special_offer_id,
                attempt_id=str(latest_attempt["id"]),
            )

    active_output_id = active_output["id"] if active_output else None
    active_media_asset_id = active_output["media_asset_id"] if active_output else None
    active_output_hash = str(active_output["state_hash"]) if active_output else None
    image_current = active_output_hash == str(offer.state_hash)
    image_required = not image_current

    attempt_id = latest_result.get("attempt_id") if latest_result is not None else None
    if attempt_id is None and latest_attempt is not None:
        attempt_id = latest_attempt["id"]

    status = latest_result.get("status") if latest_result is not None else None
    if status is None and latest_attempt is not None:
        status = str(latest_attempt["status"])
    if status is None:
        status = "succeeded" if image_current else "none"

    source_count = (
        int(latest_result["source_count"])
        if latest_result is not None and "source_count" in latest_result
        else len(offer.courses)
    )

    return {
        "special_offer_id": offer.id,
        "active_output_id": active_output_id,
        "active_media_asset_id": active_media_asset_id,
        "state_hash": str(offer.state_hash),
        "attempt_id": attempt_id,
        "status": status,
        "source_count": source_count,
        "overwrite_applied": overwrite_applied,
        "image_current": image_current,
        "image_required": image_required,
    }


async def _create_offer_state(
    db: Any,
    *,
    teacher_id: UUID | str,
    course_ids: Sequence[UUID | str],
    price_amount_cents: int,
) -> Any:
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
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    insert into app.special_offers (
                        teacher_id,
                        price_amount_cents
                    )
                    values (
                        %s::uuid,
                        %s
                    )
                    returning id
                    """,
                    (
                        normalized_teacher_id,
                        normalized_price_amount,
                    ),
                )
                row = await cur.fetchone()
            if row is None:
                raise SpecialOfferDomainError(
                    "special_offer_domain_unavailable",
                    status_code=503,
                )
            special_offer_id = str(row["id"])
            # IMPORTANT:
            # Course replacement relies on the DEFERRABLE course-set trigger.
            # The transaction may observe an intermediate empty set, but the
            # final commit must satisfy the 1..5 contiguous-position contract.
            await special_offers_repo.replace_special_offer_courses(
                conn,
                special_offer_id=special_offer_id,
                ordered_course_ids=normalized_course_ids,
            )
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc

    return await get_offer(db, special_offer_id)


async def _load_canonical_source_bytes(
    db: Any,
    *,
    special_offer_id: str,
) -> list[bytes]:
    resolved_sources = await resolve_special_offer_sources(db, special_offer_id)
    media_rows = await _get_source_media_rows(
        db,
        media_asset_ids=[str(source.media_asset_id) for source in resolved_sources],
    )
    media_rows_by_id = {
        str(row["id"]): dict(row)
        for row in media_rows
    }

    source_bytes: list[bytes] = []
    for source in resolved_sources:
        media_row = media_rows_by_id.get(str(source.media_asset_id))
        if media_row is None:
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )
        playback_object_path = str(media_row.get("playback_object_path") or "").strip()
        if not playback_object_path:
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )
        source_bytes.append(
            await _download_source_bytes(playback_object_path=playback_object_path)
        )

    if len(source_bytes) != len(resolved_sources):
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    return source_bytes


async def _get_source_media_rows(
    db: Any,
    *,
    media_asset_ids: Sequence[str],
) -> list[dict[str, Any]]:
    query = """
        select
            ma.id,
            ma.playback_object_path,
            ma.playback_format,
            ma.media_type::text as media_type,
            ma.purpose::text as purpose,
            ma.state::text as state
        from app.media_assets as ma
        where ma.id = any(%s::uuid[])
    """
    async with _connection_scope(db) as conn:
        try:
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(query, (list(media_asset_ids),))
                rows = await cur.fetchall()
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc

    normalized_rows = [dict(row) for row in (rows or [])]
    if len(normalized_rows) != len(media_asset_ids):
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    for row in normalized_rows:
        if str(row.get("media_type") or "").strip() != "image":
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )
        if str(row.get("purpose") or "").strip() != "course_cover":
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )
        if str(row.get("state") or "").strip() != "ready":
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )
    return normalized_rows


async def _download_source_bytes(
    *,
    playback_object_path: str,
) -> bytes:
    storage = get_storage_service(settings.media_public_bucket)
    try:
        signed = await storage.get_presigned_url(
            playback_object_path,
            ttl=max(60, int(settings.media_playback_url_ttl_seconds)),
            download=False,
        )
    except StorageObjectNotFoundError as exc:
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        ) from exc
    except StorageServiceError as exc:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        ) from exc

    async with httpx.AsyncClient(
        timeout=storage_http_timeout(),
        limits=storage_http_limits(),
    ) as client:
        try:
            response = await client.get(signed.url)
        except httpx.HTTPError as exc:
            raise SpecialOfferDomainError(
                "special_offer_domain_unavailable",
                status_code=503,
            ) from exc

    if response.status_code == 404:
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    if response.status_code >= 400:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    if not response.content:
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    return response.content


async def _ensure_owned_offer(
    db: Any,
    *,
    special_offer_id: str,
    teacher_id: str,
) -> None:
    async with _connection_scope(db) as conn:
        await _require_owned_special_offer(
            conn,
            special_offer_id=special_offer_id,
            teacher_id=teacher_id,
        )


async def _get_active_output(
    db: Any,
    *,
    special_offer_id: str,
) -> dict[str, Any] | None:
    async with _connection_scope(db) as conn:
        return await _fetch_active_output_row(
            conn,
            special_offer_id=special_offer_id,
        )


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
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (special_offer_id,))
        row = await cur.fetchone()
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
            a.created_at
        from app.special_offer_composite_image_attempts as a
        where a.special_offer_id = %s::uuid
          and a.state_hash = %s
        order by a.created_at desc, a.id desc
        limit 1
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (special_offer_id, state_hash))
        row = await cur.fetchone()
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
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (special_offer_id, attempt_id))
        row = await cur.fetchone()
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
        select so.teacher_id
        from app.special_offers as so
        where so.id = %s::uuid
        limit 1
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
            "special_offer_output_conflict",
            status_code=409,
        )


async def _validate_selected_courses(
    conn: Any,
    *,
    teacher_id: str,
    course_ids: Sequence[str],
) -> None:
    query = """
        select
            c.id,
            c.teacher_id
        from app.courses as c
        where c.id = any(%s::uuid[])
        order by c.id asc
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (list(course_ids),))
        rows = await cur.fetchall()
    if len(rows or []) != len(course_ids):
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    for row in rows or []:
        if str(row.get("teacher_id") or "").strip() != teacher_id:
            raise SpecialOfferDomainError(
                "special_offer_output_conflict",
                status_code=409,
            )


def _normalize_ordered_course_ids(course_ids: Sequence[UUID | str]) -> list[str]:
    if isinstance(course_ids, (str, bytes)):
        raise SpecialOfferDomainError(
            "special_offer_invalid_course_count",
            status_code=400,
        )
    normalized_course_ids = [
        _normalize_uuid(course_id, code="special_offer_invalid_id")
        for course_id in course_ids
    ]
    if len(normalized_course_ids) < 1 or len(normalized_course_ids) > 5:
        raise SpecialOfferDomainError(
            "special_offer_invalid_course_count",
            status_code=400,
        )
    if len(normalized_course_ids) != len(set(normalized_course_ids)):
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
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


def _map_database_error(exc: PsycopgError) -> SpecialOfferDomainError:
    if isinstance(exc, (psycopg_errors.UndefinedTable, psycopg_errors.UndefinedColumn)):
        return SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    if isinstance(exc, psycopg_errors.UniqueViolation):
        return SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )
    if isinstance(
        exc,
        (
            psycopg_errors.CheckViolation,
            psycopg_errors.ForeignKeyViolation,
            psycopg_errors.NotNullViolation,
            psycopg_errors.RaiseException,
        ),
    ):
        return SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )
    return SpecialOfferDomainError(
        "special_offer_domain_unavailable",
        status_code=503,
    )


__all__ = [
    "create_special_offer_execution",
    "generate_special_offer_image",
    "get_special_offer_execution_state",
    "regenerate_special_offer_image",
    "update_special_offer_execution",
]
