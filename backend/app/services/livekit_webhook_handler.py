from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import sentry_sdk

from ..config import settings
from . import livekit_events


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


def _capture_exception(event_type: str | None, event_id: str | None, exc: Exception) -> None:
    if not _sentry_enabled():
        return
    with sentry_sdk.push_scope() as scope:
        scope.set_tag("webhook.provider", "livekit")
        scope.set_tag("webhook.status", "failed")
        scope.set_tag("alert_kind", "webhook_failure")
        if event_type:
            scope.set_tag("webhook.event_type", event_type)
        if event_id:
            scope.set_tag("webhook.event_id", event_id)
        sentry_sdk.capture_exception(exc)


def capture_livekit_rejection(reason: str) -> None:
    _capture_message(status="rejected", reason=reason, level="warning")


async def handle_livekit_webhook(
    payload: dict[str, Any],
    signature: str | None,
) -> dict[str, Any]:
    secret = settings.livekit_webhook_secret
    if not secret:
        _capture_message(status="rejected", reason="missing_secret")
        raise LiveKitWebhookError("Webhook secret not configured", status_code=401)
    if not signature or signature != secret:
        _capture_message(status="rejected", reason="invalid_signature")
        raise LiveKitWebhookError("Invalid signature", status_code=401)

    event = payload.get("event")
    if not event:
        _capture_message(status="rejected", reason="missing_event")
        raise LiveKitWebhookError("Missing event type", status_code=400)

    event_id = payload.get("id")
    try:
        await livekit_events.enqueue_webhook(payload)
    except RuntimeError as exc:
        _capture_exception(str(event) if event else None, str(event_id) if event_id else None, exc)
        raise LiveKitWebhookError(str(exc), status_code=503) from exc

    _capture_message(
        status="success",
        reason="queued",
        event_type=str(event),
        event_id=str(event_id) if event_id else None,
        level="info",
    )
    return {"queued": True}
