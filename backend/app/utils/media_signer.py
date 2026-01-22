"""Helpers for issuing and validating signed media URLs."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from jose import JWTError, jwt

from ..config import settings

_PUBLIC_DOWNLOAD_PREFIXES = (
    "users/",
    "avatars/",
    "public-media/",
    "hero/",
    "logos/",
)


class MediaTokenError(Exception):
    """Raised when a signed media token is invalid or expired."""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def is_signing_enabled() -> bool:
    """Return True if signed media URLs are enabled."""

    return (
        bool(settings.media_signing_secret) and settings.media_signing_ttl_seconds > 0
    )


def issue_signed_url(
    media_id: str, *, purpose: str = "media"
) -> tuple[str, datetime] | None:
    """Create a signed URL for the given media id.

    Returns a tuple `(url, expires_at)` or ``None`` when signing is disabled.
    """

    if not is_signing_enabled():
        return None

    media_id = str(media_id)
    expires_at = _now() + timedelta(seconds=settings.media_signing_ttl_seconds)
    now = _now()
    payload: dict[str, Any] = {
        "sub": media_id,
        "purpose": purpose,
        "exp": int(expires_at.timestamp()),
        "iat": int(now.timestamp()),
    }
    token = jwt.encode(payload, settings.media_signing_secret, algorithm="HS256")
    return f"/media/stream/{token}", expires_at


def verify_media_token(token: str) -> dict[str, Any]:
    """Decode and validate a media token, returning the payload."""

    if not is_signing_enabled():
        raise MediaTokenError("Media signing is disabled")

    try:
        payload = jwt.decode(
            token,
            settings.media_signing_secret,
            algorithms=["HS256"],
        )
    except JWTError as exc:
        raise MediaTokenError("Invalid or expired media token") from exc

    if "sub" not in payload:
        raise MediaTokenError("Malformed media token")
    return payload


def extract_media_id_from_url(url: str | None) -> str | None:
    """Extract media id from legacy `/studio/media/{id}` URLs."""

    if not url:
        return None
    base = url.split("?")[0]
    prefix = "/studio/media/"
    if base.startswith(prefix):
        return base[len(prefix) :].split("/")[0]
    return None


def _public_download_path(storage_path: str | None) -> str | None:
    if not storage_path:
        return None
    normalized = storage_path.replace("\\", "/").lstrip("/")
    if not normalized:
        return None
    if normalized.startswith(_PUBLIC_DOWNLOAD_PREFIXES):
        return f"/api/files/{normalized}"
    return None


def public_download_url(storage_path: str | None) -> str | None:
    """Return /api/files URL when the asset resides in a public bucket."""

    return _public_download_path(storage_path)


def _public_cover_url_prefix() -> str | None:
    if settings.supabase_url is None:
        return None
    base = settings.supabase_url.unicode_string().rstrip("/")
    bucket = settings.media_public_bucket
    return f"{base}/storage/v1/object/public/{bucket}/"


def _is_public_cover_url(url: str | None) -> bool:
    if not url:
        return False
    normalized = url.strip()
    if not normalized:
        return False
    if normalized.startswith("/api/files/public-media/"):
        return True
    public_prefix = _public_cover_url_prefix()
    if public_prefix and normalized.startswith(public_prefix):
        return True
    return False


def attach_media_links(item: dict) -> None:
    """Mutate a lesson media dict with download and signed URLs."""

    if item.get("media_asset_id"):
        return

    media_id = item.get("id")
    if not media_id:
        return
    legacy_url = f"/studio/media/{media_id}"
    legacy_enabled = settings.media_allow_legacy_media
    public_url = _public_download_path(item.get("storage_path"))

    if public_url:
        item["download_url"] = public_url
    elif legacy_enabled:
        item["download_url"] = legacy_url
    else:
        item.pop("download_url", None)

    issued = issue_signed_url(media_id)
    if issued:
        signed_url, expires_at = issued
        item["signed_url"] = signed_url
        item["signed_url_expires_at"] = expires_at.isoformat()
    elif not legacy_enabled and "download_url" not in item:
        # No signer configured but legacy URLs disabled – fall back to the legacy path
        # so the frontend can still resolve media during local development.
        item["download_url"] = legacy_url


def attach_cover_links(course: dict) -> None:
    """Mutate a course dict with cover URL details.

    Legacy course covers stored `/studio/media/{lesson_media_id}` and were signed at
    read time, which caused expiring links on public pages. We now expose only
    stable public cover URLs and omit signed cover fields.
    """

    cover_url = course.get("cover_url")
    if cover_url and not _is_public_cover_url(cover_url):
        course["cover_url"] = None
    course.pop("signed_cover_url", None)
    course.pop("signed_cover_url_expires_at", None)
