from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import sentry_sdk


@dataclass
class LiveKitWebhookError(RuntimeError):
    detail: str
    status_code: int


def _sentry_enabled() -> bool:
    return sentry_sdk.Hub.current.client is not None


def _capture_message(
    *,
    status: str,
    reason: str,
    event_type: str | None = None,
    event_id: str | None = None,
    level: str = "warning",
) -> None:
    if not _sentry_enabled():
        return
    with sentry_sdk.push_scope() as scope:
        scope.set_tag("webhook.provider", "livekit")
        scope.set_tag("webhook.status", status)
        scope.set_tag("webhook.reason", reason)
        if event_type:
            scope.set_tag("webhook.event_type", event_type)
        if event_id:
            scope.set_tag("webhook.event_id", event_id)
        sentry_sdk.capture_message(f"LiveKit webhook {status}: {reason}", level=level)


def capture_livekit_rejection(reason: str) -> None:
    _capture_message(status="rejected", reason=reason, level="warning")


async def handle_livekit_webhook(
    payload: dict[str, Any],
    signature: str | None,
) -> dict[str, Any]:
    del payload, signature
    _capture_message(
        status="ignored",
        reason="runtime_paused",
        level="info",
    )
    return {
        "queued": False,
        "status": "paused",
        "reason": "livekit_runtime_paused",
    }
