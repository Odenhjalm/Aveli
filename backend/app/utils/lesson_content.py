from __future__ import annotations

import html
import json
from json import JSONDecodeError
from typing import Any, Iterable


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
