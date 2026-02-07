"""Helpers for issuing and validating signed media URLs."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlparse

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


def _effective_signing_secret() -> str | None:
    """Return the secret used to sign media stream tokens.

    Prefer the explicit `media_signing_secret`. When unset, fall back to the
    Supabase service role key *only when Supabase is configured*, ensuring legacy
    lesson media can still be signed in production without requiring a second
    secret.
    """

    explicit = (settings.media_signing_secret or "").strip()
    if explicit:
        return explicit
    if settings.supabase_url is None:
        return None
    fallback = (settings.supabase_service_role_key or "").strip()
    return fallback or None


def is_signing_enabled() -> bool:
    """Return True if signed media URLs are enabled."""

    return bool(_effective_signing_secret()) and settings.media_signing_ttl_seconds > 0


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
    secret = _effective_signing_secret()
    if not secret:
        return None
    token = jwt.encode(payload, secret, algorithm="HS256")
    return f"/media/stream/{token}", expires_at


def verify_media_token(token: str) -> dict[str, Any]:
    """Decode and validate a media token, returning the payload."""

    if not is_signing_enabled():
        raise MediaTokenError("Media signing is disabled")

    secret = _effective_signing_secret()
    if not secret:
        raise MediaTokenError("Media signing is disabled")

    try:
        payload = jwt.decode(
            token,
            secret,
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


def _normalize_storage_path(storage_path: str | None) -> str | None:
    if not storage_path:
        return None
    raw = storage_path.strip()
    parsed = urlparse(raw)
    if parsed.scheme in {"http", "https"} and parsed.path:
        raw = parsed.path
    normalized = raw.replace("\\", "/").lstrip("/")
    for prefix in (
        "api/files/",
        "storage/v1/object/public/",
        "storage/v1/object/sign/",
    ):
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix) :].lstrip("/")
            break
    return normalized or None


def _strip_bucket_prefix(storage_path: str, bucket: str | None) -> str:
    normalized_bucket = (bucket or "").strip().strip("/")
    normalized_path = storage_path.strip("/")
    if not normalized_bucket:
        return normalized_path
    prefix = f"{normalized_bucket}/"
    if normalized_path.startswith(prefix):
        stripped = normalized_path[len(prefix) :].lstrip("/")
        return stripped or normalized_path
    return normalized_path


def _supabase_public_url_prefix(bucket: str) -> str | None:
    if settings.supabase_url is None:
        return None
    normalized_bucket = bucket.strip().strip("/")
    if not normalized_bucket:
        return None
    base = settings.supabase_url.unicode_string().rstrip("/")
    return f"{base}/storage/v1/object/public/{normalized_bucket}/"


def _public_download_path(
    storage_path: str | None,
    *,
    storage_bucket: str | None = None,
) -> str | None:
    normalized = _normalize_storage_path(storage_path)
    if not normalized:
        return None

    public_bucket = settings.media_public_bucket
    normalized_bucket = (storage_bucket or "").strip().strip("/") or None

    is_public_asset = False
    bucket_for_public_url = public_bucket
    if normalized_bucket:
        is_public_asset = normalized_bucket == public_bucket
        # Legacy rows sometimes stored the bucket name as a path prefix instead.
        if not is_public_asset and normalized.startswith(f"{public_bucket}/"):
            is_public_asset = True
    else:
        is_public_asset = normalized.startswith(_PUBLIC_DOWNLOAD_PREFIXES)

    if not is_public_asset:
        return None

    public_prefix = _supabase_public_url_prefix(bucket_for_public_url)
    if public_prefix:
        key = _strip_bucket_prefix(normalized, bucket_for_public_url)
        return f"{public_prefix}{key}"

    if normalized.startswith(_PUBLIC_DOWNLOAD_PREFIXES):
        return f"/api/files/{normalized}"
    return None


def public_download_url(storage_path: str | None) -> str | None:
    """Return a stable public URL for assets stored in the public bucket.

    When Supabase Storage is configured we prefer the Supabase public URL.
    Otherwise we fall back to `/api/files/...` (local dev uploads only).
    """

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


def attach_media_links(item: dict, *, purpose: str | None = None) -> None:
    """Mutate a lesson media dict with download and signed URLs."""

    if item.get("media_asset_id"):
        return

    media_id = item.get("id")
    if not media_id:
        return
    legacy_url = f"/studio/media/{media_id}"
    legacy_enabled = settings.media_allow_legacy_media
    public_url = _public_download_path(
        item.get("storage_path"),
        storage_bucket=item.get("storage_bucket"),
    )

    if public_url:
        item["download_url"] = public_url
        item["playback_url"] = public_url
    elif legacy_enabled:
        item["download_url"] = legacy_url
    else:
        item.pop("download_url", None)

    normalized_purpose = (purpose or "").strip().lower()
    if normalized_purpose not in {"editor_insert", "editor_preview", "student_render"}:
        normalized_purpose = "student_render"
    issued = issue_signed_url(media_id, purpose=normalized_purpose)
    if issued:
        signed_url, expires_at = issued
        item["signed_url"] = signed_url
        item["signed_url_expires_at"] = expires_at.isoformat()
        if "playback_url" not in item:
            item["playback_url"] = signed_url
    elif not legacy_enabled and "download_url" not in item:
        # No signer configured but legacy URLs disabled – fall back to the legacy path
        # so the frontend can still resolve media during local development.
        item["download_url"] = legacy_url
        item["playback_url"] = legacy_url


def attach_cover_links(course: dict) -> None:
    """Mutate a course dict with cover URL details.

    Legacy course covers stored `/studio/media/{lesson_media_id}` and were signed at
    read time, which caused expiring links on public pages. We now expose only
    stable public cover URLs and omit signed cover fields.
    """

    cover_url = course.get("cover_url")
    public_prefix = _public_cover_url_prefix()
    if public_prefix and cover_url and cover_url.startswith("/api/files/public-media/"):
        key = cover_url[len("/api/files/public-media/") :].lstrip("/")
        if key:
            course["cover_url"] = f"{public_prefix}{key}"
            cover_url = course["cover_url"]
    if cover_url and not _is_public_cover_url(cover_url):
        course["cover_url"] = None
    course.pop("signed_cover_url", None)
    course.pop("signed_cover_url_expires_at", None)
