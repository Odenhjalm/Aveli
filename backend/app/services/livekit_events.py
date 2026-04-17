from __future__ import annotations

from typing import Any

from .. import metrics

_PAUSED_DETAIL = "LiveKit runtime is paused; webhook execution is inert"


class LiveKitPausedError(RuntimeError):
    """Raised when a caller attempts to activate the paused LiveKit surface."""


def _paused_error() -> LiveKitPausedError:
    return LiveKitPausedError(_PAUSED_DETAIL)


def get_metrics() -> dict[str, Any]:
    metrics.livekit_webhook_queue_size.set(0)
    metrics.livekit_webhook_pending_jobs.set(0)
    return {
        "worker_running": False,
        "queue_size": 0,
        "pending_jobs": 0,
        "failed_jobs": 0,
        "last_failure": None,
        "verification_mode": False,
        "write_suppressed": True,
    }


async def start_worker(*, verification_mode: bool = False) -> None:
    del verification_mode
    metrics.livekit_webhook_queue_size.set(0)
    metrics.livekit_webhook_pending_jobs.set(0)


async def stop_worker() -> None:
    metrics.livekit_webhook_queue_size.set(0)
    metrics.livekit_webhook_pending_jobs.set(0)


async def enqueue_webhook(payload: dict[str, Any]) -> None:
    del payload
    raise _paused_error()


async def process_livekit_event(payload: dict[str, Any]) -> None:
    del payload
    raise _paused_error()
