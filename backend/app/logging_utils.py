from __future__ import annotations

import json
import logging
from logging.config import dictConfig
from typing import Any, Dict

from .observability import get_event_buffer_handler


class JSONFormatter(logging.Formatter):
    """
    Render log records as JSON strings, preserving structured extras.
    """

    def format(self, record: logging.LogRecord) -> str:  # pragma: no cover - formatting only
        data = {
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "timestamp": self.formatTime(record, self.datefmt),
        }
        if record.exc_info:
            data["exc_info"] = self.formatException(record.exc_info)

        extras = {
            key: value
            for key, value in record.__dict__.items()
            if key
            not in {
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
            }
        }
        if extras:
            data["context"] = extras
        return json.dumps(data, ensure_ascii=False)


def setup_logging() -> None:
    """
    Configure global logging to emit JSON lines with INFO level by default.
    Safe to call multiple times.
    """

    config: Dict[str, Any] = {
        "version": 1,
        "disable_existing_loggers": False,
        "filters": {
            "request_context": {
                "()": "app.logging_context.RequestContextFilter",
            }
        },
        "formatters": {
            "json": {
                "()": "app.logging_utils.JSONFormatter",
                "datefmt": "%Y-%m-%dT%H:%M:%S%z",
            }
        },
        "handlers": {
            "default": {
                "class": "logging.StreamHandler",
                "formatter": "json",
                "filters": ["request_context"],
                "level": "INFO",
            },
            "observability": {
                "()": "app.observability.log_buffer.get_event_buffer_handler",
                "filters": ["request_context"],
                "level": "INFO",
            },
        },
        "root": {
            "handlers": ["default", "observability"],
            "level": "INFO",
        },
    }
    get_event_buffer_handler()
    dictConfig(config)
