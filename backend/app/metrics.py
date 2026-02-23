from __future__ import annotations

try:  # pragma: no cover - optional dependency for metrics
    from prometheus_client import Counter, Gauge
except ImportError:  # pragma: no cover - fallback when prometheus_client missing
    class _NoopMetric:
        def __init__(self, *args, **kwargs):
            pass

        def inc(self, *args, **kwargs):
            return self

        def dec(self, *args, **kwargs):
            return self

        def set(self, *args, **kwargs):
            return self

        def labels(self, *args, **kwargs):
            return self

    def Counter(*args, **kwargs):  # type: ignore
        return _NoopMetric()

    def Gauge(*args, **kwargs):  # type: ignore
        return _NoopMetric()

livekit_webhook_processed_total = Counter(
    "livekit_webhook_processed_total",
    "Number of LiveKit webhook jobs processed successfully.",
)
livekit_webhook_failed_total = Counter(
    "livekit_webhook_failed_total",
    "Number of LiveKit webhook jobs that ultimately failed.",
)
livekit_webhook_retries_total = Counter(
    "livekit_webhook_retries_total",
    "Number of retries scheduled for LiveKit webhook jobs.",
)
livekit_webhook_pending_jobs = Gauge(
    "livekit_webhook_pending_jobs",
    "Count of LiveKit webhook jobs pending or in-flight.",
)
livekit_webhook_queue_size = Gauge(
    "livekit_webhook_queue_size",
    "Current in-memory queue size for LiveKit webhook worker.",
)

payment_command_created = Counter(
    "payment_command_created",
    "Number of shadow payment command records created.",
)
webhook_event_received = Counter(
    "webhook_event_received",
    "Number of Stripe webhook events received after signature verification.",
)
webhook_event_duplicate = Counter(
    "webhook_event_duplicate",
    "Number of duplicate Stripe webhook events detected in shadow ledger.",
)
webhook_event_applied = Counter(
    "webhook_event_applied",
    "Number of Stripe webhook events that reached legacy mutation flow successfully.",
)
