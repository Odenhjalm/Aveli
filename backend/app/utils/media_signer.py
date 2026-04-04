"""Helpers for public media links and preview-only metadata."""

from __future__ import annotations

from typing import Any
from urllib.parse import urlparse

from ..config import settings

_PUBLIC_DOWNLOAD_PREFIXES = (
    "users/",
    "avatars/",
    "public-media/",
    "hero/",
    "logos/",
)


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

    if is_public_asset:
        key = _strip_bucket_prefix(normalized, bucket_for_public_url)
        return f"/api/files/{bucket_for_public_url}/{key}"

    if normalized.startswith(_PUBLIC_DOWNLOAD_PREFIXES):
        return f"/api/files/{normalized}"
    return None


def public_download_url(storage_path: str | None) -> str | None:
    """Return a stable public URL for assets stored in the public bucket.

    When Supabase Storage is configured we prefer the Supabase public URL.
    Otherwise we fall back to `/api/files/...` (local dev uploads only).
    """

    return _public_download_path(storage_path)


def attach_media_links(item: dict, *, purpose: str | None = None) -> None:
    """Mutate a lesson media dict with preview-only public-link metadata."""

    del purpose
    media_id = item.get("id")
    if not media_id:
        return
    media_state = (item.get("media_state") or "").strip().lower()
    has_media_asset = item.get("media_asset_id") is not None
    if not has_media_asset:
        item.pop("preferredUrl", None)
        item.pop("preferred_url", None)
        item.pop("url", None)
        return
    if media_state and media_state != "ready":
        item.pop("preferredUrl", None)
        item.pop("preferred_url", None)
        item.pop("url", None)
        return

    public_url = _public_download_path(
        item.get("storage_path"),
        storage_bucket=item.get("storage_bucket"),
    )
    kind = str(item.get("kind") or "").strip().lower()
    content_type = str(item.get("content_type") or "").strip().lower()
    is_image = kind == "image" or content_type.startswith("image/")

    if is_image and public_url:
        item["preferredUrl"] = public_url
        item["url"] = public_url
        return

    item.pop("preferredUrl", None)
    item.pop("preferred_url", None)
    item.pop("url", None)


def strip_renderable_media_links(
    item: dict[str, Any],
    *,
    include_preview_fields: bool = False,
) -> None:
    """Remove fields that could be mistaken for renderability authority.

    Callers should use this after they have determined the current surface is
    not allowed to present the media as renderable.
    """

    for field in (
        "url",
    ):
        item.pop(field, None)

    if not include_preview_fields:
        return

    for field in (
        "preferredUrl",
        "preferred_url",
        "resolved_preview_url",
        "resolvedPreviewUrl",
        "thumbnail_url",
        "thumbnailUrl",
        "poster_frame",
        "posterFrame",
    ):
        item.pop(field, None)


def attach_cover_links(course: dict) -> None:
    """Strip retired legacy cover-link fields from a course dict."""

    course.pop("signed_cover_url", None)
    course.pop("signed_cover_url_expires_at", None)
