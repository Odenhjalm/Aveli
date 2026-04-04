from __future__ import annotations

import html
import json
import re
from json import JSONDecodeError
from typing import Any, Iterable, Mapping
from urllib.parse import unquote, urlparse


_SUPPORTED_LESSON_MEDIA_KINDS = frozenset({"image", "audio", "video", "document"})
_LESSON_MEDIA_ID_FRAGMENT = r"[A-Za-z0-9_-]+(?:-[A-Za-z0-9_-]+)*"
_LESSON_MEDIA_ID_PATTERN = re.compile(rf"^{_LESSON_MEDIA_ID_FRAGMENT}$")
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
_MARKDOWN_IMAGE_PATTERN = re.compile(
    r"""!\[[^\]]*]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)""",
    re.IGNORECASE,
)
_MARKDOWN_LINK_PATTERN = re.compile(
    r"""(?<!!)\[[^\]]*]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)""",
    re.IGNORECASE,
)
_ANY_TYPED_TOKEN_PATTERN = re.compile(r"!([a-z]+)\(([^)]*)\)", re.IGNORECASE)
_TOKEN_PATTERN_BY_KIND = {
    kind: re.compile(rf"!{kind}\(({_LESSON_MEDIA_ID_FRAGMENT})\)", re.IGNORECASE)
    for kind in _SUPPORTED_LESSON_MEDIA_KINDS
}
_MEDIA_FILE_EXTENSION_PATTERN = re.compile(
    r"\.(?:png|jpe?g|webp|gif|svg|mp3|wav|m4a|mp4|pdf)(?:$|[?#])",
    re.IGNORECASE,
)
_STORAGE_OBJECT_URL_PATH_PATTERN = re.compile(
    r"/storage/v1/object/(?:public|authenticated|sign)/[^/]+/.+",
    re.IGNORECASE,
)
_STORAGE_PATH_PREFIXES = (
    "lessons/",
    "media/",
    "courses/",
    "home-player/",
    "users/",
)


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
        for key in ("source", "src", "url"):
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
        _register_lesson_media_aliases(
            lesson_media_id=lesson_media_id,
            row=row,
            media_url_aliases=media_url_aliases,
        )

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
    aliases = {
        str(alias).strip(): str(lesson_media_id).strip()
        for alias, lesson_media_id in (media_url_aliases or {}).items()
        if str(alias).strip() and str(lesson_media_id).strip()
    }

    normalized = markdown.replace("\r\n", "\n").replace("\r", "\n")
    normalized = _replace_html_media(
        normalized,
        pattern=_AUDIO_HTML_ELEMENT_PATTERN,
        expected_kind="audio",
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=aliases,
    )
    normalized = _replace_html_media(
        normalized,
        pattern=_VIDEO_HTML_ELEMENT_PATTERN,
        expected_kind="video",
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=aliases,
    )
    normalized = _replace_html_media(
        normalized,
        pattern=_IMG_HTML_TAG_PATTERN,
        expected_kind="image",
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=aliases,
    )
    normalized = _normalize_markdown_images(
        normalized,
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=aliases,
    )
    normalized = _normalize_markdown_links(
        normalized,
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=aliases,
    )
    _assert_no_html_media(normalized)
    _assert_no_raw_markdown_media_refs(
        normalized,
        lesson_media_kinds=allowed_kinds,
        media_url_aliases=aliases,
    )
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


def _resolve_lesson_media_id(
    *,
    raw_reference: str,
    expected_kind: str | None,
    attrs: Mapping[str, str] | None = None,
    source: str | None = None,
    lesson_media_kinds: Mapping[str, str],
    media_url_aliases: Mapping[str, str],
) -> str:
    explicit_id = None
    if attrs:
        explicit_id = attrs.get("data-lesson-media-id") or attrs.get("data-lesson_media_id")
    lesson_media_id = explicit_id.strip() if explicit_id and explicit_id.strip() else None
    if lesson_media_id is None and source:
        lesson_media_id = _resolve_lesson_media_id_from_source(
            source=source,
            media_url_aliases=media_url_aliases,
        )
    if not lesson_media_id:
        raise ValueError(
            "Lesson content media must use canonical typed refs; "
            f"could not normalize {raw_reference!r}"
        )

    normalized_kind = (
        _normalize_lesson_media_kind(expected_kind) if expected_kind is not None else None
    )
    actual_kind = lesson_media_kinds.get(lesson_media_id)
    if actual_kind is None:
        raise ValueError(
            f"Lesson content references lesson media {lesson_media_id!r} that is not attached to this lesson"
        )
    if normalized_kind is not None and actual_kind != normalized_kind:
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


def _normalize_markdown_links(
    markdown: str,
    *,
    lesson_media_kinds: Mapping[str, str],
    media_url_aliases: Mapping[str, str],
) -> str:
    def _replacement(match: re.Match[str]) -> str:
        raw = match.group(0) or ""
        source = (match.group(1) or "").strip()
        if not source or not _is_candidate_markdown_media_link(source):
            return raw

        lesson_media_id = _resolve_lesson_media_id(
            raw_reference=raw,
            expected_kind=None,
            source=source,
            lesson_media_kinds=lesson_media_kinds,
            media_url_aliases=media_url_aliases,
        )
        actual_kind = lesson_media_kinds.get(lesson_media_id)
        if actual_kind is None:
            raise ValueError(
                f"Lesson content references lesson media {lesson_media_id!r} that is not attached to this lesson"
            )
        return f"!{actual_kind}({lesson_media_id})"

    return _MARKDOWN_LINK_PATTERN.sub(_replacement, markdown)


def _assert_no_raw_markdown_media_refs(
    markdown: str,
    *,
    lesson_media_kinds: Mapping[str, str],
    media_url_aliases: Mapping[str, str],
) -> None:
    for match in _MARKDOWN_IMAGE_PATTERN.finditer(markdown):
        raw = match.group(0) or ""
        if raw:
            raise ValueError(
                "Lesson content media must use canonical typed refs; raw image URLs are not allowed"
            )

    for match in _MARKDOWN_LINK_PATTERN.finditer(markdown):
        raw = match.group(0) or ""
        source = (match.group(1) or "").strip()
        if not raw or not source:
            continue
        if _is_candidate_markdown_media_link(source):
            raise ValueError(
                "Lesson content media must use canonical typed refs; raw document links are not allowed"
            )


def markdown_contains_legacy_document_media_links(markdown: str) -> bool:
    if not markdown:
        return False

    for match in _MARKDOWN_LINK_PATTERN.finditer(markdown):
        source = (match.group(1) or "").strip()
        if not source:
            continue
        if _is_candidate_markdown_media_link(source):
            return True
    return False


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
    for match in _ANY_TYPED_TOKEN_PATTERN.finditer(markdown):
        raw_kind = (match.group(1) or "").strip().lower()
        raw_id = (match.group(2) or "").strip()
        normalized_kind = _normalize_lesson_media_kind(raw_kind)
        if normalized_kind is None or not _LESSON_MEDIA_ID_PATTERN.fullmatch(raw_id):
            raise ValueError(
                "Lesson content media must use canonical typed refs; only !image(id), !audio(id), !video(id), and !document(id) are allowed"
            )

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


def _register_media_url_alias(
    media_url_aliases: dict[str, str],
    *,
    lesson_media_id: str,
    candidate: str | None,
) -> None:
    normalized = _normalize_alias_candidate(candidate)
    if normalized:
        media_url_aliases.setdefault(normalized, lesson_media_id)


def _register_lesson_media_aliases(
    *,
    lesson_media_id: str,
    row: Mapping[str, Any],
    media_url_aliases: dict[str, str],
) -> None:
    _register_media_url_alias(
        media_url_aliases,
        lesson_media_id=lesson_media_id,
        candidate=f"/studio/media/{lesson_media_id}",
    )
    _register_media_url_alias(
        media_url_aliases,
        lesson_media_id=lesson_media_id,
        candidate=f"studio/media/{lesson_media_id}",
    )

    storage_bucket = str(row.get("storage_bucket") or "").strip()
    storage_path = str(row.get("storage_path") or "").strip().lstrip("/")
    if not storage_bucket or not storage_path:
        return

    _register_media_url_alias(
        media_url_aliases,
        lesson_media_id=lesson_media_id,
        candidate=f"/api/files/{storage_bucket}/{storage_path}",
    )
    _register_media_url_alias(
        media_url_aliases,
        lesson_media_id=lesson_media_id,
        candidate=f"/storage/v1/object/public/{storage_bucket}/{storage_path}",
    )
    _register_media_url_alias(
        media_url_aliases,
        lesson_media_id=lesson_media_id,
        candidate=f"/storage/v1/object/authenticated/{storage_bucket}/{storage_path}",
    )


def _normalize_alias_candidate(candidate: str | None) -> str | None:
    raw = str(candidate or "").strip()
    if not raw:
        return None
    raw = raw.strip("<>")
    parsed = urlparse(raw)
    path = unquote(parsed.path or raw).strip()
    if not path:
        return None
    if not path.startswith("/"):
        path = f"/{path.lstrip('/')}"
    return re.sub(r"/{2,}", "/", path)


def _resolve_lesson_media_id_from_source(
    *,
    source: str,
    media_url_aliases: Mapping[str, str],
) -> str | None:
    studio_match = _STUDIO_MEDIA_URL_PATTERN.search(source)
    if studio_match:
        candidate = studio_match.group(1)
        if candidate:
            return candidate.strip()

    normalized = _normalize_alias_candidate(source)
    if normalized:
        lesson_media_id = media_url_aliases.get(normalized)
        if lesson_media_id:
            return lesson_media_id
    return None


def _looks_like_storage_path(source: str) -> bool:
    normalized = source.strip().lstrip("/")
    if not normalized:
        return False
    lowered = normalized.lower()
    return lowered.startswith(_STORAGE_PATH_PREFIXES) and bool(
        _MEDIA_FILE_EXTENSION_PATTERN.search(lowered)
    )


def _is_candidate_markdown_media_link(source: str) -> bool:
    normalized = source.strip()
    if not normalized:
        return False
    lowered = normalized.lower()
    if _STUDIO_MEDIA_URL_PATTERN.search(normalized):
        return True
    normalized_alias = _normalize_alias_candidate(normalized)
    if normalized_alias and normalized_alias.startswith("/media/"):
        return True
    if lowered.startswith("/api/files/") or "/api/files/" in lowered:
        return True
    if normalized_alias and _STORAGE_OBJECT_URL_PATH_PATTERN.search(normalized_alias):
        return True
    if _looks_like_storage_path(normalized):
        return True
    return bool(_MEDIA_FILE_EXTENSION_PATTERN.search(lowered))
