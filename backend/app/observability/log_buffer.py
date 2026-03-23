from __future__ import annotations

import logging
import re
import time
from collections import deque
from datetime import date, datetime
from threading import Lock
from typing import Any, Iterable
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

_BUFFER_MAX_EVENTS = 500
_BUILTIN_LOG_RECORD_KEYS = {
    "name",
    "msg",
    "args",
    "levelname",
    "levelno",
    "pathname",
    "filename",
    "module",
    "exc_info",
    "exc_text",
    "stack_info",
    "lineno",
    "funcName",
    "created",
    "msecs",
    "relativeCreated",
    "thread",
    "threadName",
    "processName",
    "process",
    "message",
    "asctime",
}
_SENSITIVE_FIELD_NAMES = {
    "access_token",
    "api_key",
    "authorization",
    "cookie",
    "email",
    "owner_id",
    "password",
    "refresh_token",
    "secret",
    "set-cookie",
    "signature",
    "signed_url",
    "teacher_id",
    "token",
    "user_id",
}
_SENSITIVE_QUERY_KEYS = {
    "access_token",
    "api_key",
    "authorization",
    "jwt",
    "key",
    "secret",
    "sig",
    "signature",
    "token",
}
_EMAIL_RE = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
_BEARER_RE = re.compile(r"\bBearer\s+[A-Za-z0-9._\-+/=]+\b", re.IGNORECASE)
_ASSIGNMENT_RE = re.compile(
    r"\b("
    r"access_token|api_key|authorization|cookie|email|owner_id|password|"
    r"refresh_token|secret|set-cookie|signature|signed_url|teacher_id|token|user_id"
    r")=([^\s]+)",
    re.IGNORECASE,
)
_KEY_VALUE_RE = re.compile(r"\b([a-zA-Z_][a-zA-Z0-9_]*)=([^\s]+)")
_URL_RE = re.compile(r"https?://[^\s]+", re.IGNORECASE)
_EVENTS: deque[dict[str, Any]] = deque(maxlen=_BUFFER_MAX_EVENTS)
_EVENTS_LOCK = Lock()
_HANDLER: "OperationalLogBufferHandler | None" = None


def _now_iso() -> str:
    return datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def _normalize_level(value: str | int | None) -> int:
    if value is None:
        return logging.NOTSET
    if isinstance(value, int):
        return value
    normalized = str(value).strip().upper()
    return int(getattr(logging, normalized, logging.NOTSET))


def _sanitize_url(raw: str) -> str:
    try:
        parsed = urlsplit(raw)
    except ValueError:
        return raw
    if not parsed.scheme or not parsed.netloc:
        return raw
    if not parsed.query:
        return raw
    redacted = []
    changed = False
    for key, value in parse_qsl(parsed.query, keep_blank_values=True):
        if key.strip().lower() in _SENSITIVE_QUERY_KEYS:
            redacted.append((key, "[REDACTED]"))
            changed = True
        else:
            redacted.append((key, value))
    if not changed:
        return raw
    return urlunsplit(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            urlencode(redacted, doseq=True),
            parsed.fragment,
        )
    )


def sanitize_string(value: str, *, limit: int = 500) -> str:
    text = str(value or "")
    text = _URL_RE.sub(lambda match: _sanitize_url(match.group(0)), text)
    text = _EMAIL_RE.sub("[REDACTED_EMAIL]", text)
    text = _BEARER_RE.sub("Bearer [REDACTED]", text)
    text = _ASSIGNMENT_RE.sub(lambda match: f"{match.group(1)}=[REDACTED]", text)
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def sanitize_value(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str):
        return sanitize_string(value)
    if isinstance(value, dict):
        sanitized: dict[str, Any] = {}
        for key in sorted(value.keys(), key=lambda item: str(item)):
            key_str = str(key)
            normalized_key = key_str.strip().lower()
            if normalized_key in _SENSITIVE_FIELD_NAMES:
                sanitized[key_str] = "[REDACTED]"
            else:
                sanitized[key_str] = sanitize_value(value[key])
        return sanitized
    if isinstance(value, (list, tuple, set)):
        return [sanitize_value(item) for item in list(value)[:20]]
    return sanitize_string(str(value))


def _extract_record_fields(record: logging.LogRecord) -> dict[str, Any]:
    extras = {
        key: value
        for key, value in record.__dict__.items()
        if key not in _BUILTIN_LOG_RECORD_KEYS
    }
    parsed_fields: dict[str, Any] = {
        key: value
        for key, value in _KEY_VALUE_RE.findall(record.getMessage())
    }
    fields = dict(parsed_fields)
    fields.update(extras)
    sanitized = sanitize_value(fields)
    return sanitized if isinstance(sanitized, dict) else {}


def _component_for_record(logger_name: str, message: str) -> str:
    normalized_logger = logger_name.strip().lower()
    normalized_message = message.strip().lower()
    if normalized_logger.endswith("media_cleanup") or normalized_message.startswith(
        "media_cleanup_"
    ):
        return "cleanup"
    if normalized_logger.endswith("media_transcode_worker"):
        return "media_processing"
    if normalized_logger.endswith(("api_media", "upload", "studio")) and "upload" in normalized_message:
        return "upload_pipeline"
    if normalized_logger.endswith(("livekit_events", "membership_expiry_warnings")):
        return "worker"
    return "application"


def _event_name_for_record(logger_name: str, message: str, component: str) -> str:
    stripped = message.strip()
    token = stripped.split(maxsplit=1)[0].rstrip(":") if stripped else ""
    if token and re.fullmatch(r"[A-Z0-9_]+", token):
        return token.lower()
    slug_source = " ".join(stripped.split()[:4]) if stripped else logger_name
    slug = re.sub(r"[^a-z0-9]+", "_", slug_source.lower()).strip("_")
    return f"{component}_{slug or 'event'}"


def _serialize_event(event: dict[str, Any]) -> dict[str, Any]:
    return {
        "timestamp": event["timestamp"],
        "level": event["level"],
        "logger": event["logger"],
        "component": event["component"],
        "event": event["event"],
        "message": event["message"],
        "fields": event["fields"],
    }


class OperationalLogBufferHandler(logging.Handler):
    def emit(self, record: logging.LogRecord) -> None:  # pragma: no cover - log plumbing
        try:
            message = sanitize_string(record.getMessage())
            fields = _extract_record_fields(record)
            component = _component_for_record(record.name, message)
            event_name = _event_name_for_record(record.name, message, component)
            event = {
                "observed_at": time.time(),
                "timestamp": _now_iso(),
                "level": record.levelname,
                "logger": record.name,
                "component": component,
                "event": event_name,
                "message": message,
                "fields": fields,
            }
            with _EVENTS_LOCK:
                _EVENTS.append(event)
        except Exception:
            self.handleError(record)


def get_event_buffer_handler() -> OperationalLogBufferHandler:
    global _HANDLER
    if _HANDLER is None:
        _HANDLER = OperationalLogBufferHandler(level=logging.INFO)
    return _HANDLER


def clear_events() -> None:
    with _EVENTS_LOCK:
        _EVENTS.clear()


def list_events(
    *,
    limit: int = 20,
    min_level: str | int | None = None,
    components: Iterable[str] | None = None,
    logger_names: Iterable[str] | None = None,
    event_names: Iterable[str] | None = None,
    since_epoch_seconds: float | None = None,
) -> list[dict[str, Any]]:
    capped_limit = max(1, min(int(limit or 20), _BUFFER_MAX_EVENTS))
    min_level_number = _normalize_level(min_level)
    allowed_components = {str(item).strip().lower() for item in (components or []) if str(item).strip()}
    allowed_loggers = {str(item).strip() for item in (logger_names or []) if str(item).strip()}
    allowed_events = {str(item).strip().lower() for item in (event_names or []) if str(item).strip()}

    with _EVENTS_LOCK:
        snapshot = list(_EVENTS)

    results: list[dict[str, Any]] = []
    for event in reversed(snapshot):
        if since_epoch_seconds is not None and event["observed_at"] < since_epoch_seconds:
            continue
        if _normalize_level(event["level"]) < min_level_number:
            continue
        if allowed_components and event["component"].lower() not in allowed_components:
            continue
        if allowed_loggers and event["logger"] not in allowed_loggers:
            continue
        if allowed_events and event["event"].lower() not in allowed_events:
            continue
        results.append(_serialize_event(event))
        if len(results) >= capped_limit:
            break
    return results
