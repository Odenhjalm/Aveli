from __future__ import annotations

from typing import Any, Iterable

from psycopg import errors

from ..db import get_conn


def _livekit_paused_error() -> RuntimeError:
    return RuntimeError("LiveKit runtime is paused; queue mutation is forbidden")


async def release_processing_webhook_jobs() -> None:
    """
    Paused LiveKit runtime forbids resetting or mutating webhook jobs.
    """
    raise _livekit_paused_error()


async def get_webhook_job_counts() -> dict[str, int]:
    try:
        async with get_conn() as cur:
            await cur.execute(
                """
                select
                  count(*) filter (where status in ('pending', 'processing')) as pending,
                  count(*) filter (where status = 'failed') as failed
                from app.livekit_webhook_jobs
                """
            )
            row = await cur.fetchone()
    except errors.UndefinedTable:
        return {"pending": 0, "failed": 0}
    return {"pending": row["pending"], "failed": row["failed"]}


async def get_webhook_queue_snapshot() -> dict[str, Any]:
    try:
        async with get_conn() as cur:
            await cur.execute(
                """
                SELECT
                  count(*) FILTER (WHERE status = 'pending') AS pending,
                  count(*) FILTER (WHERE status = 'processing') AS processing,
                  count(*) FILTER (WHERE status = 'failed') AS failed,
                  min(next_run_at) FILTER (WHERE status = 'pending') AS next_due_at,
                  max(updated_at) FILTER (WHERE status = 'failed') AS last_failed_at
                FROM app.livekit_webhook_jobs
                """
            )
            row = await cur.fetchone()
    except errors.UndefinedTable:
        return {
            "pending": 0,
            "processing": 0,
            "failed": 0,
            "next_due_at": None,
            "last_failed_at": None,
        }
    return {
        "pending": int(row["pending"] or 0) if row else 0,
        "processing": int(row["processing"] or 0) if row else 0,
        "failed": int(row["failed"] or 0) if row else 0,
        "next_due_at": row["next_due_at"] if row else None,
        "last_failed_at": row["last_failed_at"] if row else None,
    }


async def list_recent_failed_webhook_jobs(limit: int = 20) -> list[dict[str, Any]]:
    capped_limit = max(1, min(int(limit or 20), 100))
    try:
        async with get_conn() as cur:
            await cur.execute(
                """
                SELECT
                  id,
                  event,
                  attempt,
                  status,
                  last_error,
                  last_attempt_at,
                  updated_at
                FROM app.livekit_webhook_jobs
                WHERE status = 'failed'
                ORDER BY updated_at DESC, id DESC
                LIMIT %s::int
                """,
                (capped_limit,),
            )
            rows = await cur.fetchall()
    except errors.UndefinedTable:
        return []
    return [dict(row) for row in rows]


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
