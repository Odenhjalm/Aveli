"""HTTP header helpers shared across routers."""

from __future__ import annotations

from pathlib import Path
from urllib.parse import quote


def build_content_disposition(filename: str | None, *, disposition: str = "inline") -> str:
    """Return a RFC 6266 compatible Content-Disposition header value."""

    fallback = (filename or "").strip() or "media"
    fallback = Path(fallback).name or "media"
    ascii_safe = "".join(ch if 32 <= ord(ch) <= 126 and ch not in {";", '"'} else "_" for ch in fallback)
    ascii_safe = ascii_safe or "media"
    quoted = quote(fallback, safe="/")
    header = f'{disposition}; filename="{ascii_safe}"'
    if quoted and quoted != ascii_safe:
        header += f"; filename*=UTF-8''{quoted}"
    return header


__all__ = ["build_content_disposition"]
