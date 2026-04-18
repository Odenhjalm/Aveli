from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any

from ..config import settings
from ..observability import log_buffer
from ..repositories import (
    media_assets as media_assets_repo,
    media_resolution_failures as media_resolution_failures_repo,
)
from . import livekit_events, media_transcode_worker, membership_expiry_warnings

_DEFAULT_LIMIT = 20
_MAX_LIMIT = 50
_MEDIA_FAILURE_LIMIT = 25
_CLEANUP_ACTIVITY_LIMIT = 100
_CLEANUP_WINDOWS = {
    "1h": timedelta(hours=1),
    "6h": timedelta(hours=6),
    "24h": timedelta(hours=24),
    "7d": timedelta(days=7),
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _parse_timestamp(value: str | None) -> datetime:
    if not value:
        return datetime.min.replace(tzinfo=timezone.utc)
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _clamp_limit(limit: int | None) -> int:
    return max(1, min(int(limit or _DEFAULT_LIMIT), _MAX_LIMIT))


def _normalize_window(window: str | None) -> tuple[str, timedelta]:
    normalized = str(window or "24h").strip().lower()
    if normalized not in _CLEANUP_WINDOWS:
        raise ValueError(
            f"Unsupported window '{window}'. Expected one of: {', '.join(_CLEANUP_WINDOWS)}"
        )
    return normalized, _CLEANUP_WINDOWS[normalized]


def _normalize_log_item(event: dict[str, Any], *, source: str) -> dict[str, Any]:
    return {
        "source": source,
        "timestamp": event.get("timestamp"),
        "severity": event.get("level"),
        "component": event.get("component"),
        "event": event.get("event"),
        "message": event.get("message"),
        "details": log_buffer.sanitize_value(event.get("fields") or {}),
    }


def _normalize_media_asset_failure(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "source": "media_assets",
        "timestamp": _iso(row.get("updated_at")),
        "severity": "ERROR",
        "component": "media_processing",
        "event": "media_asset_failed",
        "message": log_buffer.sanitize_string(str(row.get("error_message") or "Media asset failed")),
        "details": {
            "failure_type": "asset_processing",
            "asset_id": str(row.get("id")),
            "course_id": str(row.get("course_id")) if row.get("course_id") else None,
            "lesson_id": str(row.get("lesson_id")) if row.get("lesson_id") else None,
            "media_type": row.get("media_type"),
            "purpose": row.get("purpose"),
            "state": row.get("state"),
            "processing_attempts": int(row.get("processing_attempts") or 0),
            "processing_locked_at": _iso(row.get("processing_locked_at")),
            "next_retry_at": _iso(row.get("next_retry_at")),
            "source_bucket": row.get("storage_bucket"),
            "source_path": row.get("original_object_path"),
            "playback_bucket": row.get("storage_bucket"),
            "playback_path": row.get("playback_object_path"),
            "home_player_upload_id": (
                str(row.get("home_player_upload_id"))
                if row.get("home_player_upload_id")
                else None
            ),
            "home_player_upload_title": row.get("home_player_upload_title"),
            "home_player_upload_active": row.get("home_player_upload_active"),
        },
    }


def _normalize_resolution_failure(row: dict[str, Any]) -> dict[str, Any]:
    reason = str(row.get("reason") or "unsupported")
    return {
        "source": "media_resolution_failures",
        "timestamp": _iso(row.get("created_at")),
        "severity": "ERROR",
        "component": "media_processing",
        "event": f"media_resolution_{reason}",
        "message": f"Media resolution failed ({reason})",
        "details": {
            "failure_type": "resolution",
            "id": int(row.get("id") or 0),
            "lesson_media_id": (
                str(row.get("lesson_media_id")) if row.get("lesson_media_id") else None
            ),
            "asset_id": str(row.get("media_asset_id")) if row.get("media_asset_id") else None,
            "lesson_id": str(row.get("lesson_id")) if row.get("lesson_id") else None,
            "course_id": str(row.get("course_id")) if row.get("course_id") else None,
            "mode": row.get("mode"),
            "reason": reason,
            "details": log_buffer.sanitize_value(row.get("details") or {}),
        },
    }


def _matches_asset_id(event: dict[str, Any], asset_id: str) -> bool:
    details = event.get("details") or {}
    for key in ("asset_id", "media_id", "media_asset_id"):
        if str(details.get(key) or "").strip() == asset_id:
            return True
    return False


def _sorted_items(items: list[dict[str, Any]], *, limit: int | None = None) -> list[dict[str, Any]]:
    sorted_items = sorted(
        items,
        key=lambda item: (_parse_timestamp(item.get("timestamp")), item.get("event") or ""),
        reverse=True,
    )
    if limit is None:
        return sorted_items
    return sorted_items[:limit]


def _status_from_flags(
    *,
    worker_running: bool,
    last_error: dict[str, Any] | None,
    degraded_signal: bool = False,
    enabled: bool = True,
    verification_mode: bool = False,
    write_suppressed: bool = False,
) -> str:
    if verification_mode and write_suppressed:
        if not worker_running:
            return "stopped"
        if last_error is not None:
            return "degraded"
        return "ok"
    if not enabled:
        return "disabled"
    if not worker_running:
        return "stopped"
    if degraded_signal or last_error is not None:
        return "degraded"
    return "ok"


async def get_recent_errors(limit: int | None = None) -> dict[str, Any]:
    bounded_limit = _clamp_limit(limit)
    log_items = [
        _normalize_log_item(event, source="log_buffer")
        for event in log_buffer.list_events(limit=bounded_limit * 4, min_level="ERROR")
    ]
    media_items = [
        _normalize_media_asset_failure(row)
        for row in await media_assets_repo.list_media_failures(limit=bounded_limit)
    ]
    resolution_items = [
        _normalize_resolution_failure(row)
        for row in await media_resolution_failures_repo.list_recent_media_resolution_failures(
            limit=bounded_limit
        )
    ]
    recent_errors = _sorted_items(
        [*log_items, *media_items, *resolution_items],
        limit=bounded_limit,
    )
    return {
        "generated_at": _iso(_now()),
        "limit_applied": bounded_limit,
        "recent_errors": recent_errors,
        "sources_consulted": [
            "log_buffer",
            "media_assets",
            "media_resolution_failures",
        ],
    }


async def get_media_failures(asset_id: str | None = None) -> dict[str, Any]:
    normalized_asset_id = str(asset_id or "").strip() or None
    asset_failures = [
        _normalize_media_asset_failure(row)
        for row in await media_assets_repo.list_media_failures(
            limit=_MEDIA_FAILURE_LIMIT,
            media_id=normalized_asset_id,
        )
    ]
    resolution_failures = [
        _normalize_resolution_failure(row)
        for row in await media_resolution_failures_repo.list_recent_media_resolution_failures(
            limit=_MEDIA_FAILURE_LIMIT,
            media_asset_id=normalized_asset_id,
        )
    ]
    related_log_events = [
        _normalize_log_item(event, source="log_buffer")
        for event in log_buffer.list_events(
            limit=_MEDIA_FAILURE_LIMIT,
            min_level="WARNING",
            components={"media_processing", "upload_pipeline"},
        )
    ]
    if normalized_asset_id is not None:
        related_log_events = [
            event for event in related_log_events if _matches_asset_id(event, normalized_asset_id)
        ]
    media_failures = _sorted_items(
        [*asset_failures, *resolution_failures, *related_log_events]
    )
    summary = Counter(
        str((item.get("details") or {}).get("failure_type") or item.get("source"))
        for item in media_failures
    )
    return {
        "generated_at": _iso(_now()),
        "asset_id": normalized_asset_id,
        "media_failures": media_failures,
        "summary": dict(sorted(summary.items())),
    }


async def get_cleanup_activity(window: str | None = None) -> dict[str, Any]:
    normalized_window, delta = _normalize_window(window)
    start = _now() - delta
    events = [
        _normalize_log_item(event, source="log_buffer")
        for event in log_buffer.list_events(
            limit=_CLEANUP_ACTIVITY_LIMIT,
            components={"cleanup"},
            since_epoch_seconds=start.timestamp(),
        )
    ]
    summary = Counter(item.get("event") or "unknown" for item in events)
    return {
        "generated_at": _iso(_now()),
        "window": normalized_window,
        "window_start": _iso(start),
        "cleanup_activity": _sorted_items(events),
        "summary": {
            "total_events": len(events),
            "event_counts": dict(sorted(summary.items())),
        },
    }


async def get_worker_health() -> dict[str, Any]:
    transcode_metrics = await media_transcode_worker.get_metrics()
    webhook_metrics = livekit_events.get_metrics()
    membership_metrics = membership_expiry_warnings.get_metrics()

    transcode_enabled = bool(transcode_metrics.get("final_state"))
    transcode_last_error = transcode_metrics.get("last_error")
    transcode_queue = transcode_metrics.get("queue_summary") or {}
    transcode_verification_mode = bool(transcode_metrics.get("verification_mode"))
    transcode_write_suppressed = bool(transcode_metrics.get("write_suppressed"))
    transcode_status = _status_from_flags(
        worker_running=bool(transcode_metrics.get("worker_running")),
        last_error=transcode_last_error,
        degraded_signal=bool(
            int(transcode_queue.get("failed") or 0) > 0
            or int(transcode_queue.get("stale_processing_locks") or 0) > 0
        ),
        enabled=transcode_enabled,
        verification_mode=transcode_verification_mode,
        write_suppressed=transcode_write_suppressed,
    )

    webhook_verification_mode = bool(webhook_metrics.get("verification_mode"))
    webhook_write_suppressed = bool(webhook_metrics.get("write_suppressed"))
    webhook_status = _status_from_flags(
        worker_running=bool(webhook_metrics.get("worker_running")),
        last_error=webhook_metrics.get("last_failure"),
        verification_mode=webhook_verification_mode,
        write_suppressed=webhook_write_suppressed,
    )

    membership_verification_mode = bool(membership_metrics.get("verification_mode"))
    membership_write_suppressed = bool(membership_metrics.get("write_suppressed"))
    membership_status = _status_from_flags(
        worker_running=bool(membership_metrics.get("worker_running")),
        last_error=membership_metrics.get("last_error"),
        verification_mode=membership_verification_mode,
        write_suppressed=membership_write_suppressed,
    )

    worker_health = {
        "media_transcode": {
            "status": transcode_status,
            "worker_running": bool(transcode_metrics.get("worker_running")),
            "enabled_by_mcp_mode": bool(transcode_metrics.get("enabled_by_mcp_mode")),
            "enabled_by_env": bool(transcode_metrics.get("enabled_by_env")),
            "enabled_by_config": bool(transcode_metrics.get("enabled_by_config")),
            "final_state": bool(transcode_metrics.get("final_state")),
            "poll_interval_seconds": int(transcode_metrics.get("poll_interval_seconds") or 0),
            "batch_size": int(transcode_metrics.get("batch_size") or 0),
            "max_attempts": int(transcode_metrics.get("max_attempts") or 0),
            "queue_summary": {
                "pending_upload": int(transcode_queue.get("pending_upload") or 0),
                "uploaded": int(transcode_queue.get("uploaded") or 0),
                "processing": int(transcode_queue.get("processing") or 0),
                "failed": int(transcode_queue.get("failed") or 0),
                "ready": int(transcode_queue.get("ready") or 0),
                "stale_processing_locks": int(
                    transcode_queue.get("stale_processing_locks") or 0
                ),
                "oldest_unfinished_created_at": _iso(
                    transcode_queue.get("oldest_unfinished_created_at")
                ),
            },
            "last_error": transcode_last_error,
            "verification_mode": transcode_verification_mode,
            "write_suppressed": transcode_write_suppressed,
        },
        "livekit_webhooks": {
            "status": webhook_status,
            "worker_running": bool(webhook_metrics.get("worker_running")),
            "queue_size": int(webhook_metrics.get("queue_size") or 0),
            "pending_jobs": int(webhook_metrics.get("pending_jobs") or 0),
            "failed_jobs": int(webhook_metrics.get("failed_jobs") or 0),
            "last_failure": log_buffer.sanitize_value(webhook_metrics.get("last_failure")),
            "verification_mode": webhook_verification_mode,
            "write_suppressed": webhook_write_suppressed,
        },
        "membership_expiry_warnings": {
            "status": membership_status,
            "worker_running": bool(membership_metrics.get("worker_running")),
            "poll_interval_seconds": int(
                membership_metrics.get("poll_interval_seconds") or 0
            ),
            "last_error": membership_metrics.get("last_error"),
            "verification_mode": membership_verification_mode,
            "write_suppressed": membership_write_suppressed,
        },
    }
    return {
        "generated_at": _iso(_now()),
        "worker_health": worker_health,
        "safety": {
            "logs_mcp_enabled": bool(settings.logs_mcp_enabled),
            "log_buffer_max_events": 500,
        },
    }
