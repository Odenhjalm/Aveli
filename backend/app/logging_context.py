from __future__ import annotations

import logging
from contextvars import ContextVar, Token
from typing import Any

import sentry_sdk

_log_context: ContextVar[dict[str, Any]] = ContextVar("log_context", default={})


class RequestContextFilter(logging.Filter):
    """Inject request metadata from ContextVars into every log record."""

    def filter(self, record: logging.LogRecord) -> bool:  # pragma: no cover - formatting only
        context = _log_context.get({})
        record.request_id = context.get("request_id")
        record.user_id = context.get("user_id")
        return True


def push_request_context(request_id: str) -> Token:
    return _log_context.set({"request_id": request_id, "user_id": None})


def pop_request_context(token: Token) -> None:
    _log_context.reset(token)


def set_user_context(user_id: str | None) -> None:
    context = _log_context.get({})
    if context:
        context["user_id"] = user_id
    else:  # fallback when middleware is bypassed (tests)
        _log_context.set({"request_id": None, "user_id": user_id})
    sentry_sdk.set_user({"id": user_id} if user_id else None)


__all__ = [
    "RequestContextFilter",
    "push_request_context",
    "pop_request_context",
    "set_user_context",
]
