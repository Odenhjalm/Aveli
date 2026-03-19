from __future__ import annotations

import base64
import html
import json
import re
from json import JSONDecodeError
from typing import Any, Iterable, Mapping

from ..config import settings


_SUPPORTED_LESSON_MEDIA_KINDS = frozenset({"image", "audio", "video"})
_LESSON_MEDIA_ID_FRAGMENT = r"[A-Za-z0-9_-]+(?:-[A-Za-z0-9_-]+)*"
_AUDIO_HTML_ELEMENT_PATTERN = re.compile(
    r"<audio\b[^>]*?(?:\/>|>.*?<\/audio>)",
    re.IGNORECASE | re.DOTALL,
)
_VIDEO_HTML_ELEMENT_PATTERN = re.compile(
    r"<video\b[^>]*?(?:\/>|>.*?<\/video>)",
    re.IGNORECASE | re.DOTALL,
)
_IMG_HTML_TAG_PATTERN = re.compile(
    r"<img\b[^>]*?>",
    re.IGNORECASE,
)
_FORBIDDEN_HTML_MEDIA_PATTERN = re.compile(r"<\s*(video|audio|img)\b", re.IGNORECASE)
_HTML_ATTRIBUTE_PATTERN = re.compile(
    r"""([a-zA-Z_:][a-zA-Z0-9_\-:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"""
)
_STUDIO_MEDIA_URL_PATTERN = re.compile(
    rf"""(?:https?:\/\/[^\s"'()]+)?\/studio\/media\/({_LESSON_MEDIA_ID_FRAGMENT})\b""",
    re.IGNORECASE,
)
_MEDIA_STREAM_URL_PATTERN = re.compile(
    r"""(?:https?:\/\/[^\s"'()]+)?\/media\/stream\/([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)""",
    re.IGNORECASE,
)
_MARKDOWN_IMAGE_PATTERN = re.compile(
    r"""!\[[^\]]*]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)""",
    re.IGNORECASE,
)
_TOKEN_PATTERN_BY_KIND = {
    kind: re.compile(rf"!{kind}\(({_LESSON_MEDIA_ID_FRAGMENT})\)", re.IGNORECASE)
    for kind in _SUPPORTED_LESSON_MEDIA_KINDS
}


def serialize_audio_embeds(content: str) -> str:
    """Normalize custom audio embeds into <audio> tags for Markdown consumers."""
    if not content or "audio" not in content:
        return content

    normalized = content
    document_converted, converted = _convert_quill_document_if_needed(content)
    if converted:
        normalized = document_converted

    inline_converted, inline_changed = _replace_inline_audio_tokens(normalized)
    if inline_changed:
        normalized = inline_converted

    return normalized


def _convert_quill_document_if_needed(raw: str) -> tuple[str, bool]:
    stripped = raw.strip()
    if not stripped:
        return raw, False

    try:
        parsed = json.loads(stripped)
    except JSONDecodeError:
        return raw, False

    operations: Iterable[Any] | None = None
    if isinstance(parsed, list):
        operations = parsed
    elif isinstance(parsed, dict):
        ops = parsed.get("ops")
        if isinstance(ops, list):
            operations = ops

    if not operations:
        return raw, False

    if not _contains_audio_embed(operations):
        return raw, False

    parts: list[str] = []
    for op in operations:
        if not isinstance(op, dict):
            continue
        insert = op.get("insert")
        if isinstance(insert, str):
            parts.append(insert)
            continue
        if isinstance(insert, dict):
            html_tag = _media_embed_to_html(insert)
            if html_tag is not None:
                parts.append(html_tag)
                continue
        # Preserve unknown inserts to avoid losing content.
        parts.append(json.dumps(op))

    return "".join(parts), True


def _replace_inline_audio_tokens(raw: str) -> tuple[str, bool]:
    decoder = json.JSONDecoder()
    idx = 0
    length = len(raw)
    pieces: list[str] = []
    changed = False

    while idx < length:
        char = raw[idx]
        if char != "{":
            pieces.append(char)
            idx += 1
            continue

        try:
            obj, end = decoder.raw_decode(raw, idx)
        except JSONDecodeError:
            pieces.append(char)
            idx += 1
            continue

        if isinstance(obj, dict):
            insert = obj.get("insert")
            if isinstance(insert, dict) and insert.get("audio") is not None:
                tag = _media_embed_to_html({"audio": insert["audio"]})
                if tag is not None:
                    pieces.append(tag)
                    changed = True
                    idx = end
                    continue
        pieces.append(raw[idx:end])
        idx = end

    return "".join(pieces), changed


def _contains_audio_embed(ops: Iterable[Any]) -> bool:
    for op in ops:
        if not isinstance(op, dict):
            continue
        insert = op.get("insert")
        if isinstance(insert, dict) and insert.get("audio") is not None:
            return True
    return False


def _media_embed_to_html(embed: dict[str, Any]) -> str | None:
    for kind in ("audio", "video", "image"):
        if kind not in embed:
            continue
        url = _resolve_media_url(embed[kind])
        if not url:
            return None
        escaped = html.escape(url, quote=True)
        if kind == "audio":
            return f'<audio controls src="{escaped}"></audio>'
        if kind == "video":
            return f'<video controls src="{escaped}"></video>'
        if kind == "image":
            return f'<img src="{escaped}" alt="" />'
    return None


def _resolve_media_url(value: Any) -> str | None:
    if isinstance(value, str):
        trimmed = value.strip()
        return trimmed or None
    if isinstance(value, dict):
        for key in ("source", "src", "url", "download_url"):
            candidate = value.get(key)
            if isinstance(candidate, str):
                trimmed = candidate.strip()
                if trimmed:
                    return trimmed
    return None


def _normalize_lesson_media_kind(value: Any) -> str | None:
    normalized = str(value or "").strip().lower()
    if normalized == "pdf":
        normalized = "document"
    if normalized in _SUPPORTED_LESSON_MEDIA_KINDS:
        return normalized
    return None


def _normalize_storage_path(
    *,
    storage_bucket: str | None,
    storage_path: str | None,
) -> str | None:
    bucket = str(storage_bucket or "").strip().strip("/")
    raw = str(storage_path or "").strip()
    if not raw:
        return None
    normalized = raw.replace("\\", "/").lstrip("/")
    if bucket and normalized.startswith(f"{bucket}/"):
        normalized = normalized[len(bucket) + 1 :].lstrip("/")
    return normalized or None


def _public_storage_url(*, storage_bucket: str, storage_path: str) -> str | None:
    if settings.supabase_url is None:
        return None
    base = settings.supabase_url.unicode_string().rstrip("/")
    bucket = storage_bucket.strip().strip("/")
    key = storage_path.lstrip("/")
    if not bucket or not key:
        return None
    return f"{base}/storage/v1/object/public/{bucket}/{key}"


def build_lesson_media_write_contract(
    rows: Iterable[Mapping[str, Any]],
) -> tuple[dict[str, str], dict[str, str]]:
    lesson_media_kinds: dict[str, str] = {}
    media_url_aliases: dict[str, str] = {}

    for row in rows:
        lesson_media_id = str(row.get("id") or "").strip()
        if not lesson_media_id:
            continue
        normalized_kind = _normalize_lesson_media_kind(row.get("kind"))
        if normalized_kind is None:
            continue

        lesson_media_kinds[lesson_media_id] = normalized_kind

        storage_bucket = str(row.get("storage_bucket") or "").strip() or None
        normalized_path = _normalize_storage_path(
            storage_bucket=storage_bucket,
            storage_path=row.get("storage_path"),
        )
        if not storage_bucket or not normalized_path:
            continue

        alias_candidates = {
            f"/api/files/{storage_bucket}/{normalized_path}",
            f"/storage/v1/object/public/{storage_bucket}/{normalized_path}",
        }
        absolute_public_url = _public_storage_url(
            storage_bucket=storage_bucket,
            storage_path=normalized_path,
        )
        if absolute_public_url:
            alias_candidates.add(absolute_public_url)

        for alias in alias_candidates:
            normalized_alias = _normalized_media_url_alias(alias)
            if normalized_alias:
                media_url_aliases[normalized_alias] = lesson_media_id

    return lesson_media_kinds, media_url_aliases


def normalize_lesson_markdown_for_storage(
    markdown: str,
    *,
    lesson_media_kinds: Mapping[str, str] | None = None,
    media_url_aliases: Mapping[str, str] | None = None,
) -> str:
    if not markdown:
        return markdown

    allowed_kinds = {
        str(media_id).strip(): normalized_kind
        for media_id, kind in (lesson_media_kinds or {}).items()
        if (normalized_kind := _normalize_lesson_media_kind(kind)) is not None
    }
    url_aliases = {
        normalized_alias: str(media_id).strip()
        for alias, media_id in (media_url_aliases or {}).items()
        if (normalized_alias := _normalized_media_url_alias(alias)) is not None
        and str(media_id).strip()
    }

    normalized = markdown.replace("\r\n", "\n").replace("\r", "\n")
    normalized = _replace_html_media(
        normalized,
        pattern=_AUDIO_HTML_ELEMENT_PATTERN,
        expected_kind="audio",
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=url_aliases,
    )
    normalized = _replace_html_media(
        normalized,
        pattern=_VIDEO_HTML_ELEMENT_PATTERN,
        expected_kind="video",
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=url_aliases,
    )
    normalized = _replace_html_media(
        normalized,
        pattern=_IMG_HTML_TAG_PATTERN,
        expected_kind="image",
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=url_aliases,
    )
    normalized = _normalize_markdown_images(
        normalized,
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=url_aliases,
    )
    _assert_no_html_media(normalized)
    _validate_typed_lesson_media_tokens(normalized, lesson_media_kinds=allowed_kinds)
    return normalized


def _parse_html_attributes(raw_html: str) -> dict[str, str]:
    attrs: dict[str, str] = {}
    for match in _HTML_ATTRIBUTE_PATTERN.finditer(raw_html):
        key = match.group(1)
        if not key:
            continue
        value = match.group(2) or match.group(3) or match.group(4) or ""
        attrs[key.lower()] = value
    return attrs


def _normalize_media_source_attribute(attrs: Mapping[str, str]) -> str:
    for key in ("src", "data-src", "data-url", "data-download-url"):
        value = attrs.get(key)
        if value and value.strip():
            return value.strip()
    return ""


def _extract_media_id_from_token(token: str) -> str | None:
    parts = token.split(".")
    if len(parts) != 3:
        return None
    payload = parts[1]
    payload += "=" * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
        parsed = json.loads(decoded.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(parsed, dict):
        return None
    subject = parsed.get("sub")
    if isinstance(subject, str) and subject.strip():
        return subject.strip()
    return None


def _normalized_media_url_alias(url: str | None) -> str | None:
    if not url:
        return None
    trimmed = str(url).strip()
    if not trimmed:
        return None
    without_query = trimmed.split("?", 1)[0].split("#", 1)[0]
    if not without_query:
        return None
    studio_match = _STUDIO_MEDIA_URL_PATTERN.search(without_query)
    if studio_match:
        lesson_media_id = studio_match.group(1)
        if lesson_media_id:
            return f"/studio/media/{lesson_media_id}"
    stream_match = _MEDIA_STREAM_URL_PATTERN.search(without_query)
    if stream_match:
        token = stream_match.group(1)
        lesson_media_id = _extract_media_id_from_token(token) if token else None
        if lesson_media_id:
            return f"/media/stream/{token}"

    http_match = re.match(r"^https?://[^/]+(/.*)$", without_query, re.IGNORECASE)
    if http_match:
        path = http_match.group(1)
        return path if path else None
    if without_query.startswith("/"):
        return without_query
    return f"/{without_query}"


def _resolve_lesson_media_id_from_source(
    source: str,
    *,
    lesson_media_kinds: Mapping[str, str],
    media_url_aliases: Mapping[str, str],
) -> str | None:
    if not source:
        return None

    studio_match = _STUDIO_MEDIA_URL_PATTERN.search(source)
    if studio_match:
        lesson_media_id = studio_match.group(1)
        if lesson_media_id:
            return lesson_media_id

    stream_match = _MEDIA_STREAM_URL_PATTERN.search(source)
    if stream_match:
        token = stream_match.group(1)
        if token:
            return _extract_media_id_from_token(token)

    normalized_alias = _normalized_media_url_alias(source)
    if normalized_alias and normalized_alias in media_url_aliases:
        return media_url_aliases[normalized_alias]

    if normalized_alias and normalized_alias.startswith("/api/files/"):
        return media_url_aliases.get(normalized_alias)

    if normalized_alias and normalized_alias in lesson_media_kinds:
        return normalized_alias
    return None


def _resolve_lesson_media_id(
    *,
    raw_reference: str,
    expected_kind: str,
    attrs: Mapping[str, str] | None = None,
    source: str | None = None,
    lesson_media_kinds: Mapping[str, str],
    media_url_aliases: Mapping[str, str],
) -> str:
    normalized_kind = _normalize_lesson_media_kind(expected_kind)
    if normalized_kind is None:
        raise ValueError(f"Unsupported lesson media kind: {expected_kind}")

    explicit_id = None
    if attrs:
        explicit_id = attrs.get("data-lesson-media-id") or attrs.get("data-lesson_media_id")
    lesson_media_id = (
        explicit_id.strip()
        if explicit_id and explicit_id.strip()
        else _resolve_lesson_media_id_from_source(
            source or "",
            lesson_media_kinds=lesson_media_kinds,
            media_url_aliases=media_url_aliases,
        )
    )
    if not lesson_media_id:
        raise ValueError(
            f"Lesson content {normalized_kind} refs must use canonical lesson_media ids; "
            f"could not normalize {raw_reference!r}"
        )

    actual_kind = lesson_media_kinds.get(lesson_media_id)
    if actual_kind is None:
        raise ValueError(
            f"Lesson content references lesson media {lesson_media_id!r} that is not attached to this lesson"
        )
    if actual_kind != normalized_kind:
        raise ValueError(
            f"Lesson content {normalized_kind} ref {lesson_media_id!r} does not match attached lesson media kind {actual_kind!r}"
        )
    return lesson_media_id


def _replace_html_media(
    markdown: str,
    *,
    pattern: re.Pattern[str],
    expected_kind: str,
    lesson_media_kinds: Mapping[str, str],
    media_url_aliases: Mapping[str, str],
) -> str:
    def _replacement(match: re.Match[str]) -> str:
        raw = match.group(0) or ""
        attrs = _parse_html_attributes(raw)
        source = _normalize_media_source_attribute(attrs)
        lesson_media_id = _resolve_lesson_media_id(
            raw_reference=raw,
            expected_kind=expected_kind,
            attrs=attrs,
            source=source,
            lesson_media_kinds=lesson_media_kinds,
            media_url_aliases=media_url_aliases,
        )
        return f"!{expected_kind}({lesson_media_id})"

    return pattern.sub(_replacement, markdown)


def _normalize_markdown_images(
    markdown: str,
    *,
    lesson_media_kinds: Mapping[str, str],
    media_url_aliases: Mapping[str, str],
) -> str:
    def _replacement(match: re.Match[str]) -> str:
        raw = match.group(0) or ""
        source = match.group(1) or ""
        lesson_media_id = _resolve_lesson_media_id(
            raw_reference=raw,
            expected_kind="image",
            source=source.strip(),
            lesson_media_kinds=lesson_media_kinds,
            media_url_aliases=media_url_aliases,
        )
        return f"!image({lesson_media_id})"

    return _MARKDOWN_IMAGE_PATTERN.sub(_replacement, markdown)


def _assert_no_html_media(markdown: str) -> None:
    if _FORBIDDEN_HTML_MEDIA_PATTERN.search(markdown):
        raise ValueError(
            "Lesson content media must use canonical typed refs; raw HTML media tags are not allowed"
        )


def _validate_typed_lesson_media_tokens(
    markdown: str,
    *,
    lesson_media_kinds: Mapping[str, str],
) -> None:
    for expected_kind, pattern in _TOKEN_PATTERN_BY_KIND.items():
        for match in pattern.finditer(markdown):
            lesson_media_id = match.group(1)
            if not lesson_media_id:
                continue
            actual_kind = lesson_media_kinds.get(lesson_media_id)
            if actual_kind is None:
                raise ValueError(
                    f"Lesson content references lesson media {lesson_media_id!r} that is not attached to this lesson"
                )
            if actual_kind != expected_kind:
                raise ValueError(
                    f"Lesson content {expected_kind} ref {lesson_media_id!r} does not match attached lesson media kind {actual_kind!r}"
                )
