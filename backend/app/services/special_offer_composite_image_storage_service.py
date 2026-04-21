from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Final
from uuid import UUID

from ..config import settings
from ..services import storage_service
from ..utils import media_paths
from .special_offers_service import SpecialOfferDomainError

_CONTENT_TYPE: Final[str] = "image/jpeg"
_PLAYBACK_FORMAT: Final[str] = "jpg"
_SPECIAL_OFFER_FOLDER: Final[str] = "special-offers"


@dataclass(frozen=True, slots=True)
class SpecialOfferCompositeStorageWrite:
    media_asset_id: UUID
    state_hash: str
    original_bucket: str
    original_object_path: str
    playback_bucket: str
    playback_object_path: str
    content_type: str
    size_bytes: int


async def persist_special_offer_composite_bytes(
    *,
    special_offer_id: UUID | str,
    state_hash: str,
    media_asset_id: UUID | str,
    image_bytes: bytes,
) -> SpecialOfferCompositeStorageWrite:
    normalized_special_offer_id = _normalize_uuid(
        special_offer_id,
        code="special_offer_invalid_id",
    )
    normalized_media_asset_id = UUID(
        _normalize_uuid(
            media_asset_id,
            code="special_offer_domain_unavailable",
        )
    )
    normalized_state_hash = _normalize_state_hash(state_hash)
    normalized_image_bytes = _require_image_bytes(image_bytes)

    original_object_path = _build_object_path(
        stage="source",
        special_offer_id=normalized_special_offer_id,
        state_hash=normalized_state_hash,
        media_asset_id=normalized_media_asset_id,
    )
    playback_object_path = _build_object_path(
        stage="derived",
        special_offer_id=normalized_special_offer_id,
        state_hash=normalized_state_hash,
        media_asset_id=normalized_media_asset_id,
    )

    original_bucket = settings.media_source_bucket
    playback_bucket = settings.media_public_bucket
    original_storage = storage_service.get_storage_service(original_bucket)
    playback_storage = storage_service.get_storage_service(playback_bucket)

    try:
        await original_storage.upload_object(
            original_object_path,
            content=normalized_image_bytes,
            content_type=_CONTENT_TYPE,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
        await playback_storage.upload_object(
            playback_object_path,
            content=normalized_image_bytes,
            content_type=_CONTENT_TYPE,
            upsert=False,
            cache_seconds=settings.media_public_cache_seconds,
        )
    except storage_service.StorageServiceError as exc:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        ) from exc

    return SpecialOfferCompositeStorageWrite(
        media_asset_id=normalized_media_asset_id,
        state_hash=normalized_state_hash,
        original_bucket=original_bucket,
        original_object_path=original_object_path,
        playback_bucket=playback_bucket,
        playback_object_path=playback_object_path,
        content_type=_CONTENT_TYPE,
        size_bytes=len(normalized_image_bytes),
    )


def _build_object_path(
    *,
    stage: str,
    special_offer_id: str,
    state_hash: str,
    media_asset_id: UUID,
) -> str:
    raw_path = (
        Path("media")
        / stage
        / _SPECIAL_OFFER_FOLDER
        / special_offer_id
        / state_hash
        / f"{media_asset_id}.{_PLAYBACK_FORMAT}"
    ).as_posix()
    return media_paths.validate_new_upload_object_path(raw_path)


def _require_image_bytes(image_bytes: bytes) -> bytes:
    if not isinstance(image_bytes, bytes) or not image_bytes:
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        )
    return image_bytes


def _normalize_state_hash(value: str) -> str:
    normalized = str(value or "").strip().lower()
    if len(normalized) != 64 or any(ch not in "0123456789abcdef" for ch in normalized):
        raise SpecialOfferDomainError(
            "special_offer_output_conflict",
            status_code=409,
        )
    return normalized


def _normalize_uuid(value: UUID | str, *, code: str) -> str:
    try:
        return str(UUID(str(value).strip()))
    except (TypeError, ValueError, AttributeError) as exc:
        raise SpecialOfferDomainError(code, status_code=400) from exc


__all__ = [
    "SpecialOfferCompositeStorageWrite",
    "persist_special_offer_composite_bytes",
]
