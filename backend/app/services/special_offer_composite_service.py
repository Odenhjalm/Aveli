from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, Sequence
from uuid import UUID, uuid4

from psycopg import Error as PsycopgError
from psycopg import errors as psycopg_errors
from psycopg.rows import dict_row

from .special_offer_composition_service import compose_special_offer_image
from .special_offer_composite_image_storage_service import (
    SpecialOfferCompositeStorageWrite,
    persist_special_offer_composite_bytes,
)
from .special_offer_media_ready_service import finalize_special_offer_media_ready
from .special_offer_source_resolution_service import (
    ResolvedSource,
    resolve_special_offer_sources,
)
from .special_offers_service import SpecialOfferDomainError, get_offer


async def create_special_offer_composite(
    db: Any,
    *,
    special_offer_id: UUID | str,
    source_bytes: list[bytes],
    price_amount_cents: int,
    overwrite: bool = False,
) -> dict[str, Any]:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    normalized_price_amount = _validate_price_amount(price_amount_cents)
    normalized_overwrite = bool(overwrite)

    offer = await get_offer(db, normalized_special_offer_id)
    resolved_sources = await resolve_special_offer_sources(
        db,
        normalized_special_offer_id,
    )
    _validate_source_alignment(
        source_bytes=source_bytes,
        resolved_sources=resolved_sources,
        expected_course_count=len(offer.courses),
    )
    state_hash_snapshot = str(offer.state_hash)

    attempt_id = await _create_attempt(
        db,
        special_offer_id=normalized_special_offer_id,
        state_hash=state_hash_snapshot,
    )

    try:
        composed_bytes = await compose_special_offer_image(
            source_bytes=list(source_bytes),
            price_amount_cents=normalized_price_amount,
        )
        media_asset_id = uuid4()
        storage_write = await persist_special_offer_composite_bytes(
            special_offer_id=normalized_special_offer_id,
            state_hash=state_hash_snapshot,
            media_asset_id=media_asset_id,
            image_bytes=composed_bytes,
        )

        async with _write_transaction(db) as conn:
            await _set_attempt_status(
                conn,
                attempt_id=attempt_id,
                status="processing",
            )
            locked_offer = await _lock_special_offer(
                conn,
                special_offer_id=normalized_special_offer_id,
            )
            current_state_hash = str(locked_offer["state_hash"])
            if current_state_hash != state_hash_snapshot:
                raise SpecialOfferDomainError(
                    "special_offer_output_conflict",
                    status_code=409,
                )

            existing_output = await _get_active_output_for_update(
                conn,
                special_offer_id=normalized_special_offer_id,
            )
            if existing_output is not None and not normalized_overwrite:
                raise SpecialOfferDomainError(
                    "special_offer_asset_already_exists",
                    status_code=409,
                )

            await _insert_pending_media_asset(
                conn,
                storage_write=storage_write,
            )
            ready_asset = await finalize_special_offer_media_ready(
                conn,
                media_asset_id=storage_write.media_asset_id,
                original_object_path=storage_write.original_object_path,
                playback_object_path=storage_write.playback_object_path,
            )

            if existing_output is not None:
                await _delete_active_output(
                    conn,
                    output_id=str(existing_output["id"]),
                )

            output_row = await _insert_active_output(
                conn,
                special_offer_id=normalized_special_offer_id,
                media_asset_id=str(storage_write.media_asset_id),
                state_hash=current_state_hash,
            )
            # IMPORTANT:
            # Active output binding and persisted sources rely on DEFERRABLE
            # source-set contract triggers in the database.
            # The output row and the full 1..N source set must be written in the
            # same transaction so commit-time validation sees the exact final set.
            await _insert_source_rows(
                conn,
                output_id=str(output_row["id"]),
                resolved_sources=resolved_sources,
            )
            await _set_attempt_status(
                conn,
                attempt_id=attempt_id,
                status="succeeded",
            )

        return {
            "special_offer_id": UUID(normalized_special_offer_id),
            "output_id": output_row["id"],
            "media_asset_id": ready_asset["id"],
            "state_hash": current_state_hash,
            "attempt_id": UUID(attempt_id),
            "status": "succeeded",
            "source_count": len(resolved_sources),
            "overwrite_applied": existing_output is not None,
        }
    except SpecialOfferDomainError:
        await _mark_attempt_failed(db, attempt_id=attempt_id)
        raise
    except PsycopgError as exc:
        await _mark_attempt_failed(db, attempt_id=attempt_id)
        raise _map_database_error(exc) from exc
    except Exception as exc:
        await _mark_attempt_failed(db, attempt_id=attempt_id)
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        ) from exc


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


async def _create_attempt(
    db: Any,
    *,
    special_offer_id: str,
    state_hash: str,
) -> str:
    query = """
        insert into app.special_offer_composite_image_attempts (
            special_offer_id,
            state_hash,
            status
        )
        values (
            %s::uuid,
            %s,
            'accepted'
        )
        returning id
    """
    async with _write_transaction(db) as conn:
        try:
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(query, (special_offer_id, state_hash))
                row = await cur.fetchone()
        except PsycopgError as exc:
            raise _map_database_error(exc) from exc
    if row is None:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    return str(row["id"])


async def _mark_attempt_failed(
    db: Any,
    *,
    attempt_id: str,
) -> None:
    query = """
        update app.special_offer_composite_image_attempts
           set status = 'failed',
               finished_at = now()
         where id = %s::uuid
           and status in ('accepted', 'processing')
    """
    try:
        async with _write_transaction(db) as conn:
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(query, (attempt_id,))
    except Exception:
        return


async def _set_attempt_status(
    conn: Any,
    *,
    attempt_id: str,
    status: str,
) -> None:
    finished_at = "now()" if status in {"succeeded", "failed"} else "null"
    query = f"""
        update app.special_offer_composite_image_attempts
           set status = %s,
               finished_at = {finished_at}
         where id = %s::uuid
    """
    async with conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (status, attempt_id))
        if cur.rowcount != 1:
            raise SpecialOfferDomainError(
                "special_offer_domain_unavailable",
                status_code=503,
            )


async def _lock_special_offer(
    conn: Any,
    *,
    special_offer_id: str,
) -> dict[str, Any]:
    query = """
        select
            so.id,
            so.teacher_id,
            so.price_amount_cents,
            so.state_hash
        from app.special_offers as so
        where so.id = %s::uuid
        for update
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (special_offer_id,))
        row = await cur.fetchone()
    if row is None:
        raise SpecialOfferDomainError(
            "special_offer_not_found",
            status_code=404,
        )
    return dict(row)


async def _get_active_output_for_update(
    conn: Any,
    *,
    special_offer_id: str,
) -> dict[str, Any] | None:
    query = """
        select
            o.id,
            o.media_asset_id,
            o.state_hash
        from app.special_offer_composite_image_outputs as o
        where o.special_offer_id = %s::uuid
        for update
    """
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (special_offer_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def _insert_pending_media_asset(
    conn: Any,
    *,
    storage_write: SpecialOfferCompositeStorageWrite,
) -> dict[str, Any]:
    query = """
        insert into app.media_assets (
            id,
            media_type,
            purpose,
            original_object_path,
            ingest_format,
            state
        )
        values (
            %s::uuid,
            'image'::app.media_type,
            'special_offer_composite_image'::app.media_purpose,
            %s,
            'jpg',
            'pending_upload'::app.media_state
        )
        returning
            id,
            media_type::text as media_type,
            purpose::text as purpose,
            original_object_path,
            ingest_format,
            playback_object_path,
            playback_format,
            state::text as state
    """
    try:
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    str(storage_write.media_asset_id),
                    storage_write.original_object_path,
                ),
            )
            row = await cur.fetchone()
    except PsycopgError as exc:
        raise _map_database_error(exc) from exc
    if row is None:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    return dict(row)


async def _delete_active_output(
    conn: Any,
    *,
    output_id: str,
) -> None:
    query = """
        delete from app.special_offer_composite_image_outputs
        where id = %s::uuid
    """
    async with conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (output_id,))
        if cur.rowcount != 1:
            raise SpecialOfferDomainError(
                "special_offer_output_conflict",
                status_code=409,
            )


async def _insert_active_output(
    conn: Any,
    *,
    special_offer_id: str,
    media_asset_id: str,
    state_hash: str,
) -> dict[str, Any]:
    query = """
        insert into app.special_offer_composite_image_outputs (
            special_offer_id,
            media_asset_id,
            state_hash
        )
        values (
            %s::uuid,
            %s::uuid,
            %s
        )
        returning
            id,
            special_offer_id,
            media_asset_id,
            state_hash
    """
    try:
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (special_offer_id, media_asset_id, state_hash))
            row = await cur.fetchone()
    except PsycopgError as exc:
        if isinstance(exc, psycopg_errors.UniqueViolation):
            raise SpecialOfferDomainError(
                "special_offer_output_conflict",
                status_code=409,
            ) from exc
        raise _map_database_error(exc) from exc
    if row is None:
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )
    return dict(row)


async def _insert_source_rows(
    conn: Any,
    *,
    output_id: str,
    resolved_sources: Sequence[ResolvedSource],
) -> None:
    rows = [
        (
            output_id,
            source.position,
            str(source.course_id),
            str(source.media_asset_id),
        )
        for source in resolved_sources
    ]
    query = """
        insert into app.special_offer_composite_image_sources (
            output_id,
            source_position,
            source_course_id,
            source_media_asset_id
        )
        values (
            %s::uuid,
            %s,
            %s::uuid,
            %s::uuid
        )
    """
    try:
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.executemany(query, rows)
    except PsycopgError as exc:
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=409,
        ) from exc


def _validate_source_alignment(
    *,
    source_bytes: Sequence[bytes],
    resolved_sources: Sequence[ResolvedSource],
    expected_course_count: int,
) -> None:
    if expected_course_count < 1 or expected_course_count > 5:
        raise SpecialOfferDomainError(
            "special_offer_invalid_course_count",
            status_code=400,
        )
    if len(resolved_sources) != expected_course_count:
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )
    if len(source_bytes) != len(resolved_sources):
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )


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
    "create_special_offer_composite",
]
