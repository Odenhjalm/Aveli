from __future__ import annotations

import logging
from pathlib import Path
from urllib.parse import urlparse

from . import storage_service
from ..config import settings

logger = logging.getLogger(__name__)

_SIGNED_URL_TTL_SECONDS = 60 * 60
_KNOWN_BUCKETS = {
    "course-media",
    "lesson-media",
    "public-media",
    settings.media_source_bucket,
    settings.media_public_bucket,
}
_PUBLIC_PATH_PREFIXES = ("users/", "avatars/", "hero/", "logos/")
_SOURCE_PATH_PREFIXES = ("media/", "courses/", "lessons/", "home-player/")
_DERIVED_AUDIO_PREFIX = "media/derived/audio"


def _normalize_storage_path(storage_path: str) -> str:
    raw = str(storage_path or "").strip()
    if not raw:
        raise ValueError("storage_path is required")

    parsed = urlparse(raw)
    if parsed.scheme in {"http", "https"} and parsed.path:
        raw = parsed.path

    normalized = raw.replace("\\", "/").lstrip("/")
    for prefix in (
        "api/files/",
        "storage/v1/object/public/",
        "storage/v1/object/sign/",
        "storage/v1/object/authenticated/",
    ):
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix) :].lstrip("/")
            break

    if not normalized:
        raise ValueError("storage_path is required")
    return normalized


def _detect_bucket_and_key(
    storage_path: str,
    *,
    storage_bucket: str | None = None,
) -> tuple[str, str]:
    normalized_path = _normalize_storage_path(storage_path)
    explicit_bucket = (storage_bucket or "").strip().strip("/") or None

    if explicit_bucket:
        prefix = f"{explicit_bucket}/"
        key = (
            normalized_path[len(prefix) :].lstrip("/")
            if normalized_path.startswith(prefix)
            else normalized_path
        )
        if key:
            return explicit_bucket, key

    first_segment, _, remainder = normalized_path.partition("/")
    if first_segment in _KNOWN_BUCKETS and remainder:
        return first_segment, remainder

    if normalized_path.startswith(_PUBLIC_PATH_PREFIXES):
        return settings.media_public_bucket, normalized_path

    if normalized_path.startswith(_SOURCE_PATH_PREFIXES):
        return settings.media_source_bucket, normalized_path

    return settings.media_source_bucket, normalized_path


def is_derived_audio_path(storage_path: str) -> bool:
    normalized = _normalize_storage_path(storage_path)
    return normalized == _DERIVED_AUDIO_PREFIX or normalized.startswith(
        f"{_DERIVED_AUDIO_PREFIX}/"
    )


def is_direct_home_mp3_path(
    storage_path: str,
    *,
    storage_bucket: str | None = None,
    content_type: str | None = None,
) -> bool:
    normalized_type = str(content_type or "").strip().lower()
    if normalized_type != "audio/mpeg":
        return False
    _, key = _detect_bucket_and_key(storage_path, storage_bucket=storage_bucket)
    return key.startswith("home-player/")


async def resolve_media_url(storage_path: str) -> str:
    bucket, key = _detect_bucket_and_key(storage_path)
    presigned = await storage_service.get_storage_service(bucket).get_presigned_url(
        key,
        ttl=_SIGNED_URL_TTL_SECONDS,
        filename=Path(key).name,
        download=False,
    )
    return presigned.url

