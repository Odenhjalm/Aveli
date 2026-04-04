from __future__ import annotations

from typing import Any, Iterable
from urllib.parse import urljoin


_RELATIVE_MEDIA_URL_FIELDS = (
    "download_url",
    "signed_url",
    "url",
    "external_url",
    "cover_image_url",
    "asset_url",
    "preferred_url",
    "preferredUrl",
    "thumbnail_url",
    "thumbnailUrl",
    "poster_frame",
    "posterFrame",
)


def absolutize_media_urls(item: dict[str, Any], *, base_url: str) -> None:
    normalized_base = base_url.strip()
    if not normalized_base:
        return
    for field in _RELATIVE_MEDIA_URL_FIELDS:
        value = item.get(field)
        if not isinstance(value, str):
            continue
        trimmed = value.strip()
        if not trimmed or not trimmed.startswith("/"):
            continue
        item[field] = urljoin(normalized_base, trimmed)


def absolutize_media_url_items(
    items: Iterable[dict[str, Any]],
    *,
    base_url: str,
) -> None:
    for item in items:
        absolutize_media_urls(item, base_url=base_url)
