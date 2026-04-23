from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from typing import Any
from urllib.parse import urlsplit
from uuid import UUID


SCHEMA_VERSION = "lesson_document_v1"
EMPTY_LESSON_DOCUMENT: dict[str, Any] = {
    "schema_version": SCHEMA_VERSION,
    "blocks": [],
}

_ALLOWED_BLOCK_TYPES = frozenset(
    {"paragraph", "heading", "bullet_list", "ordered_list", "media", "cta"}
)
_INLINE_CONTAINER_BLOCK_TYPES = frozenset({"paragraph", "heading"})
_ALLOWED_BASIC_MARKS = frozenset({"bold", "italic", "underline"})
_ALLOWED_MEDIA_TYPES = frozenset({"image", "audio", "video", "document"})
_ALLOWED_MEDIA_STATES = frozenset({"uploaded", "processing", "ready"})


class LessonDocumentValidationError(ValueError):
    pass


def canonicalize_lesson_document_json(content_document: Any) -> dict[str, Any]:
    if content_document is None:
        return dict(EMPTY_LESSON_DOCUMENT)
    if not isinstance(content_document, Mapping):
        raise LessonDocumentValidationError("Lesson content_document must be an object")
    try:
        encoded = json.dumps(
            content_document,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
        decoded = json.loads(encoded)
    except (TypeError, ValueError) as exc:
        raise LessonDocumentValidationError(
            "Lesson content_document must be JSON serializable"
        ) from exc
    if not isinstance(decoded, dict):
        raise LessonDocumentValidationError("Lesson content_document must be an object")
    return decoded


def canonical_lesson_document_bytes(content_document: Mapping[str, Any]) -> bytes:
    return json.dumps(
        content_document,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def validate_lesson_document(
    content_document: Any,
    *,
    media_rows: Sequence[Mapping[str, Any]] = (),
) -> dict[str, Any]:
    document = canonicalize_lesson_document_json(content_document)
    _validate_root(document)
    media_index = _media_index(media_rows)
    for index, block in enumerate(document["blocks"]):
        _validate_block(block, path=f"blocks[{index}]", media_index=media_index)
    return document


def _validate_root(document: dict[str, Any]) -> None:
    _require_exact_keys(document, {"schema_version", "blocks"}, "document")
    if document["schema_version"] != SCHEMA_VERSION:
        raise LessonDocumentValidationError("Unsupported lesson document schema_version")
    if not isinstance(document["blocks"], list):
        raise LessonDocumentValidationError("Lesson document blocks must be a list")


def _validate_block(
    block: Any,
    *,
    path: str,
    media_index: Mapping[str, str],
) -> None:
    if not isinstance(block, Mapping):
        raise LessonDocumentValidationError(f"{path} must be an object")

    block_type = _required_string(block, "type", path)
    if block_type not in _ALLOWED_BLOCK_TYPES:
        raise LessonDocumentValidationError(f"{path}.type is not supported")

    if block_type in _INLINE_CONTAINER_BLOCK_TYPES:
        _validate_inline_container_block(block, path=path, block_type=block_type)
        return
    if block_type in {"bullet_list", "ordered_list"}:
        _validate_list_block(block, path=path, block_type=block_type)
        return
    if block_type == "media":
        _validate_media_block(block, path=path, media_index=media_index)
        return
    if block_type == "cta":
        _validate_cta_block(block, path=path)
        return

    raise LessonDocumentValidationError(f"{path}.type is not supported")


def _validate_inline_container_block(
    block: Mapping[str, Any],
    *,
    path: str,
    block_type: str,
) -> None:
    allowed_keys = {"type", "id", "children"}
    if block_type == "heading":
        allowed_keys.add("level")
    _require_exact_keys(block, allowed_keys, path)

    if "id" in block:
        _required_string(block, "id", path)
    if block_type == "heading":
        level = block.get("level")
        if not isinstance(level, int) or isinstance(level, bool) or not 1 <= level <= 6:
            raise LessonDocumentValidationError(f"{path}.level must be 1 through 6")

    _validate_inline_children(block.get("children"), path=f"{path}.children")


def _validate_list_block(
    block: Mapping[str, Any],
    *,
    path: str,
    block_type: str,
) -> None:
    allowed_keys = {"type", "id", "items"}
    if block_type == "ordered_list":
        allowed_keys.add("start")
    _require_exact_keys(block, allowed_keys, path)

    if "id" in block:
        _required_string(block, "id", path)
    if block_type == "ordered_list" and "start" in block:
        start = block["start"]
        if not isinstance(start, int) or isinstance(start, bool) or start < 1:
            raise LessonDocumentValidationError(f"{path}.start must be a positive integer")

    items = block.get("items")
    if not isinstance(items, list) or not items:
        raise LessonDocumentValidationError(f"{path}.items must be a non-empty list")

    for index, item in enumerate(items):
        item_path = f"{path}.items[{index}]"
        if not isinstance(item, Mapping):
            raise LessonDocumentValidationError(f"{item_path} must be an object")
        _require_exact_keys(item, {"id", "children"}, item_path)
        if "id" in item:
            _required_string(item, "id", item_path)
        _validate_inline_children(item.get("children"), path=f"{item_path}.children")


def _validate_media_block(
    block: Mapping[str, Any],
    *,
    path: str,
    media_index: Mapping[str, str],
) -> None:
    _require_exact_keys(block, {"type", "id", "media_type", "lesson_media_id"}, path)
    if "id" in block:
        _required_string(block, "id", path)

    media_type = _required_string(block, "media_type", path)
    if media_type not in _ALLOWED_MEDIA_TYPES:
        raise LessonDocumentValidationError(f"{path}.media_type is not supported")

    lesson_media_id = _required_uuid_string(block, "lesson_media_id", path)
    expected_media_type = media_index.get(lesson_media_id)
    if expected_media_type is None:
        raise LessonDocumentValidationError(
            f"{path}.lesson_media_id does not belong to this lesson"
        )
    if expected_media_type != media_type:
        raise LessonDocumentValidationError(
            f"{path}.media_type does not match governed lesson media"
        )


def _validate_cta_block(block: Mapping[str, Any], *, path: str) -> None:
    _require_exact_keys(block, {"type", "id", "label", "target_url"}, path)
    if "id" in block:
        _required_string(block, "id", path)

    label = _required_string(block, "label", path)
    if not label.strip():
        raise LessonDocumentValidationError(f"{path}.label must not be blank")
    _validate_url_like(_required_string(block, "target_url", path), path=f"{path}.target_url")


def _validate_inline_children(value: Any, *, path: str) -> None:
    if not isinstance(value, list):
        raise LessonDocumentValidationError(f"{path} must be a list")
    for index, child in enumerate(value):
        child_path = f"{path}[{index}]"
        if not isinstance(child, Mapping):
            raise LessonDocumentValidationError(f"{child_path} must be an object")
        _require_exact_keys(child, {"text", "marks"}, child_path)
        if not isinstance(child.get("text"), str):
            raise LessonDocumentValidationError(f"{child_path}.text must be a string")
        _validate_marks(child.get("marks", []), path=f"{child_path}.marks")


def _validate_marks(value: Any, *, path: str) -> None:
    if value is None:
        return
    if not isinstance(value, list):
        raise LessonDocumentValidationError(f"{path} must be a list")

    seen: set[str] = set()
    for index, mark in enumerate(value):
        mark_path = f"{path}[{index}]"
        if isinstance(mark, str):
            if mark == "link":
                raise LessonDocumentValidationError(f"{mark_path} link mark requires href")
            mark_type = mark
        elif isinstance(mark, Mapping):
            _require_exact_keys(mark, {"type", "href"}, mark_path)
            mark_type = _required_string(mark, "type", mark_path)
            if mark_type != "link":
                raise LessonDocumentValidationError(f"{mark_path}.type is not supported")
            _validate_url_like(_required_string(mark, "href", mark_path), path=f"{mark_path}.href")
        else:
            raise LessonDocumentValidationError(f"{mark_path} must be a mark string or object")

        if mark_type not in _ALLOWED_BASIC_MARKS and mark_type != "link":
            raise LessonDocumentValidationError(f"{mark_path} is not a supported mark")
        if mark_type in seen:
            raise LessonDocumentValidationError(f"{mark_path} duplicates mark {mark_type}")
        seen.add(mark_type)


def _media_index(media_rows: Sequence[Mapping[str, Any]]) -> dict[str, str]:
    indexed: dict[str, str] = {}
    for row in media_rows:
        lesson_media_id = str(row.get("lesson_media_id") or row.get("id") or "").strip()
        if not lesson_media_id:
            continue
        try:
            UUID(lesson_media_id)
        except (TypeError, ValueError) as exc:
            raise LessonDocumentValidationError("Lesson media id is invalid") from exc

        media_type = str(row.get("media_type") or row.get("kind") or "").strip().lower()
        state = str(row.get("state") or "").strip().lower()
        if media_type not in _ALLOWED_MEDIA_TYPES:
            raise LessonDocumentValidationError("Lesson media type is invalid")
        if state and state not in _ALLOWED_MEDIA_STATES:
            continue
        indexed[lesson_media_id] = media_type
    return indexed


def _required_string(value: Mapping[str, Any], key: str, path: str) -> str:
    item = value.get(key)
    if not isinstance(item, str):
        raise LessonDocumentValidationError(f"{path}.{key} must be a string")
    return item


def _required_uuid_string(value: Mapping[str, Any], key: str, path: str) -> str:
    item = _required_string(value, key, path).strip()
    try:
        UUID(item)
    except (TypeError, ValueError) as exc:
        raise LessonDocumentValidationError(f"{path}.{key} must be a UUID") from exc
    return item


def _require_exact_keys(
    value: Mapping[str, Any],
    allowed_keys: set[str],
    path: str,
) -> None:
    keys = set(value.keys())
    required_keys = allowed_keys - {"id", "marks", "start"}
    missing = required_keys - keys
    unknown = keys - allowed_keys
    if missing:
        raise LessonDocumentValidationError(
            f"{path} is missing required keys: {', '.join(sorted(missing))}"
        )
    if unknown:
        raise LessonDocumentValidationError(
            f"{path} has unsupported keys: {', '.join(sorted(unknown))}"
        )


def _validate_url_like(value: str, *, path: str) -> None:
    target = value.strip()
    if not target:
        raise LessonDocumentValidationError(f"{path} must not be blank")
    parsed = urlsplit(target)
    if parsed.scheme:
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise LessonDocumentValidationError(f"{path} must be an http(s) URL")
        return
    if target.startswith("/") and not target.startswith("//"):
        return
    raise LessonDocumentValidationError(f"{path} must be absolute http(s) or root-relative")
