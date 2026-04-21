from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg import Error as PsycopgError
from psycopg import errors as psycopg_errors
from psycopg.rows import dict_row

from ..config import settings
from ..services import storage_service
from .special_offers_service import SpecialOfferDomainError

_READY_COLUMNS = """
    result.id,
    result.media_type::text as media_type,
    result.purpose::text as purpose,
    result.original_object_path,
    result.ingest_format,
    result.playback_object_path,
    result.playback_format,
    result.state::text as state
"""


async def finalize_special_offer_media_ready(
    conn: Any,
    *,
    media_asset_id: UUID | str,
    original_object_path: str,
    playback_object_path: str,
) -> dict[str, Any]:
    normalized_media_asset_id = _normalize_uuid(
        media_asset_id,
        code="special_offer_ready_transition_failed",
    )
    normalized_original_object_path = _normalize_object_path(
        original_object_path,
        code="special_offer_ready_transition_failed",
    )
    normalized_playback_object_path = _normalize_object_path(
        playback_object_path,
        code="special_offer_ready_transition_failed",
    )

    asset = await _get_media_asset_for_update(
        conn,
        media_asset_id=normalized_media_asset_id,
    )
    _validate_asset_before_ready(
        asset,
        original_object_path=normalized_original_object_path,
    )
    await _verify_storage_success(
        original_object_path=normalized_original_object_path,
        playback_object_path=normalized_playback_object_path,
    )
    ready_asset = await _transition_asset_to_ready(
        conn,
        media_asset_id=normalized_media_asset_id,
        playback_object_path=normalized_playback_object_path,
    )

    if str(ready_asset.get("state") or "").strip().lower() != "ready":
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(ready_asset.get("playback_format") or "").strip().lower() != "jpg":
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(ready_asset.get("playback_object_path") or "").strip() != normalized_playback_object_path:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    return ready_asset


async def _get_media_asset_for_update(
    conn: Any,
    *,
    media_asset_id: str,
) -> dict[str, Any]:
    query = """
        select
            ma.id,
            ma.media_type::text as media_type,
            ma.purpose::text as purpose,
            ma.original_object_path,
            ma.ingest_format,
            ma.playback_object_path,
            ma.playback_format,
            ma.state::text as state
        from app.media_assets as ma
        where ma.id = %s::uuid
        for update
    """
    try:
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (media_asset_id,))
            row = await cur.fetchone()
    except PsycopgError as exc:
        raise _map_database_error(exc) from exc

    if row is None:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    return dict(row)


def _validate_asset_before_ready(
    asset: dict[str, Any],
    *,
    original_object_path: str,
) -> None:
    if str(asset.get("media_type") or "").strip().lower() != "image":
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(asset.get("purpose") or "").strip().lower() != "special_offer_composite_image":
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(asset.get("state") or "").strip().lower() != "pending_upload":
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(asset.get("ingest_format") or "").strip().lower() != "jpg":
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(asset.get("original_object_path") or "").strip() != original_object_path:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )


async def _verify_storage_success(
    *,
    original_object_path: str,
    playback_object_path: str,
) -> None:
    original_storage = storage_service.get_storage_service(settings.media_source_bucket)
    playback_storage = storage_service.get_storage_service(settings.media_public_bucket)

    try:
        original_metadata = await original_storage.inspect_object(original_object_path)
        playback_metadata = await playback_storage.inspect_object(playback_object_path)
    except storage_service.StorageObjectNotFoundError as exc:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        ) from exc
    except storage_service.StorageServiceError as exc:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        ) from exc

    if str(original_metadata.path or "").strip() != original_object_path:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if not playback_metadata.size_bytes or playback_metadata.size_bytes <= 0:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(playback_metadata.path or "").strip() != playback_object_path:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    if str(playback_metadata.content_type or "").strip().lower() != "image/jpeg":
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )


async def _transition_asset_to_ready(
    conn: Any,
    *,
    media_asset_id: str,
    playback_object_path: str,
) -> dict[str, Any]:
    query = f"""
        select {_READY_COLUMNS}
        from app.canonical_worker_transition_media_asset(
            %s::uuid,
            'ready'::app.media_state,
            %s,
            'jpg',
            null,
            null,
            clock_timestamp()
        ) as result
    """
    try:
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (media_asset_id, playback_object_path))
            row = await cur.fetchone()
    except PsycopgError as exc:
        if isinstance(
            exc,
            (
                psycopg_errors.CheckViolation,
                psycopg_errors.RaiseException,
            ),
        ):
            raise SpecialOfferDomainError(
                "special_offer_ready_transition_failed",
                status_code=409,
            ) from exc
        raise _map_database_error(exc) from exc

    if row is None:
        raise SpecialOfferDomainError(
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    return dict(row)


def _normalize_uuid(value: UUID | str, *, code: str) -> str:
    try:
        return str(UUID(str(value).strip()))
    except (TypeError, ValueError, AttributeError) as exc:
        raise SpecialOfferDomainError(code, status_code=400) from exc


def _normalize_object_path(value: str, *, code: str) -> str:
    normalized = str(value or "").strip().replace("\\", "/").lstrip("/")
    if not normalized:
        raise SpecialOfferDomainError(code, status_code=409)
    return normalized


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
            "special_offer_ready_transition_failed",
            status_code=409,
        )
    return SpecialOfferDomainError(
        "special_offer_domain_unavailable",
        status_code=503,
    )


__all__ = [
    "finalize_special_offer_media_ready",
]
