from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping, Sequence

_SEVERITY_RANK = {"error": 0, "warning": 1, "info": 2}


def now() -> datetime:
    return datetime.now(timezone.utc)


def iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def normalize_text(value: Any) -> str | None:
    normalized = str(value or "").strip()
    return normalized or None


def severity(value: Any) -> str:
    normalized = str(value or "error").strip().lower()
    if normalized in {"error", "warning", "info"}:
        return normalized
    return "error"


def unique_sorted_strings(values: Iterable[Any]) -> list[str]:
    return sorted(
        {
            normalized
            for value in values
            if (normalized := normalize_text(value)) is not None
        }
    )


def violation(
    code: str,
    message: str,
    *,
    source: str,
    severity_value: str = "error",
    subject: Mapping[str, Any] | None = None,
    details: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "code": str(code),
        "message": str(message),
        "severity": severity(severity_value),
        "source": str(source),
        "subject": dict(subject or {}),
        "details": dict(details or {}),
    }


def inconsistency(
    code: str,
    message: str,
    *,
    source: str,
    details: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "code": str(code),
        "message": str(message),
        "source": str(source),
        "details": dict(details or {}),
    }


def wrap_upstream_inconsistency(
    item: Mapping[str, Any],
    *,
    source: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    subject = {
        "course_id": normalize_text(item.get("course_id")),
        "lesson_id": normalize_text(item.get("lesson_id")),
        "lesson_media_id": normalize_text(item.get("lesson_media_id")),
        "asset_id": normalize_text(item.get("asset_id")),
        "runtime_media_id": normalize_text(item.get("runtime_media_id")),
    }
    compact_subject = {key: value for key, value in subject.items() if value is not None}
    details = dict(item.get("details") or {})
    code = str(item.get("code") or "domain_inconsistency")
    message = str(item.get("message") or "Domain inconsistency detected")
    return (
        violation(
            code,
            message,
            source=source,
            severity_value=str(item.get("severity") or "error"),
            subject=compact_subject,
            details=details,
        ),
        inconsistency(
            code,
            message,
            source=source,
            details=details,
        ),
    )


def sort_violations(items: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        [dict(item) for item in items],
        key=lambda item: (
            _SEVERITY_RANK.get(severity(item.get("severity")), 99),
            str(item.get("code") or ""),
            json.dumps(item.get("subject") or {}, sort_keys=True),
        ),
    )


def sort_inconsistencies(items: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        [dict(item) for item in items],
        key=lambda item: (
            str(item.get("code") or ""),
            str(item.get("source") or ""),
            json.dumps(item.get("details") or {}, sort_keys=True),
        ),
    )


def status_from_violations(
    items: Sequence[Mapping[str, Any]],
    *,
    missing_subject: bool = False,
) -> str:
    if missing_subject:
        return "missing"
    severities = {severity(item.get("severity")) for item in items}
    if "error" in severities:
        return "error"
    if "warning" in severities:
        return "warning"
    return "ok"


def failure_count(summary: Mapping[str, Any] | None) -> int:
    if not summary:
        return 0
    total = 0
    for value in summary.values():
        try:
            total += int(value or 0)
        except (TypeError, ValueError):
            continue
    return total


def media_transcode_status(worker_health_payload: Mapping[str, Any]) -> str | None:
    worker_health = worker_health_payload.get("worker_health") or {}
    media_transcode = worker_health.get("media_transcode") or {}
    return normalize_text(media_transcode.get("status"))
