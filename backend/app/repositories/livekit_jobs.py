from __future__ import annotations

from typing import Any, Iterable


def _livekit_paused_error() -> RuntimeError:
    return RuntimeError("LiveKit runtime is paused; queue mutation is forbidden")


async def release_processing_webhook_jobs() -> None:
    """
    Paused LiveKit runtime forbids resetting or mutating webhook jobs.
    """
    raise _livekit_paused_error()


async def get_webhook_job_counts() -> dict[str, int]:
    return {"pending": 0, "failed": 0}


async def get_webhook_queue_snapshot() -> dict[str, Any]:
    return {
        "pending": 0,
        "processing": 0,
        "failed": 0,
        "next_due_at": None,
        "last_failed_at": None,
    }


async def list_recent_failed_webhook_jobs(limit: int = 20) -> list[dict[str, Any]]:
    del limit
    return []


async def create_webhook_job(payload: dict[str, Any]) -> dict[str, Any]:
    del payload
    raise _livekit_paused_error()


async def lock_webhook_job(job_id: str) -> dict[str, Any] | None:
    del job_id
    raise _livekit_paused_error()


async def fetch_and_lock_due_webhook_jobs(limit: int = 20) -> Iterable[dict[str, Any]]:
    del limit
    raise _livekit_paused_error()


async def delete_webhook_job(job_id: str) -> None:
    del job_id
    raise _livekit_paused_error()


async def schedule_webhook_retry(
    job_id: str,
    *,
    attempt: int,
    next_run_at: object,
    last_error: str,
) -> None:
    del job_id, attempt, next_run_at, last_error
    raise _livekit_paused_error()


async def mark_webhook_job_failed(
    job_id: str,
    *,
    attempt: int,
    last_error: str,
) -> None:
    del job_id, attempt, last_error
    raise _livekit_paused_error()
