from __future__ import annotations

from pathlib import Path
from types import MappingProxyType
from urllib.parse import urlparse


AUDIO_EXTENSION_TO_CONTENT_TYPE = MappingProxyType(
    {
        ".mp3": "audio/mpeg",
        ".wav": "audio/wav",
        ".wave": "audio/wav",
        ".m4a": "audio/mp4",
        ".aac": "audio/aac",
        ".ogg": "audio/ogg",
        ".oga": "audio/ogg",
        ".opus": "audio/ogg",
        ".flac": "audio/flac",
        ".weba": "audio/webm",
        ".webm": "audio/webm",
    }
)

SUPPORTED_AUDIO_CONTENT_TYPES = frozenset(AUDIO_EXTENSION_TO_CONTENT_TYPE.values())
GENERIC_BINARY_CONTENT_TYPES = frozenset(
    {"application/octet-stream", "binary/octet-stream"}
)


def normalize_content_type(value: str | None) -> str | None:
    normalized = (value or "").strip().lower()
    return normalized or None


def normalize_extension(value: str | None) -> str | None:
    raw = (value or "").strip().lower()
    if not raw:
        return None
    return raw if raw.startswith(".") else f".{raw}"


def detect_extension(storage_path: str | None) -> str | None:
    raw = str(storage_path or "").strip()
    if not raw:
        return None
    parsed = urlparse(raw)
    if parsed.scheme in {"http", "https"} and parsed.path:
        raw = parsed.path
    suffix = Path(raw).suffix.lower()
    return suffix or None


def audio_content_type_from_extension(value: str | None) -> str | None:
    normalized = normalize_extension(value)
    if normalized is None:
        return None
    return AUDIO_EXTENSION_TO_CONTENT_TYPE.get(normalized)


def audio_content_type_from_path(storage_path: str | None) -> str | None:
    return audio_content_type_from_extension(detect_extension(storage_path))


def is_supported_audio_content_type(value: str | None) -> bool:
    normalized = normalize_content_type(value)
    return normalized in SUPPORTED_AUDIO_CONTENT_TYPES


def resolve_runtime_audio_content_type(
    *,
    kind: str | None,
    content_type: str | None,
    storage_path: str | None,
) -> str | None:
    normalized_kind = (kind or "").strip().lower()
    normalized_type = normalize_content_type(content_type)
    if normalized_kind != "audio":
        return normalized_type
    if normalized_type and normalized_type not in GENERIC_BINARY_CONTENT_TYPES:
        return normalized_type
    return audio_content_type_from_path(storage_path) or normalized_type
