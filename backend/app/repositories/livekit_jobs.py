from __future__ import annotations

from datetime import datetime
from typing import Any, Iterable

from psycopg import errors
from psycopg.types.json import Jsonb

from ..db import get_conn


async def release_processing_webhook_jobs() -> None:
    """
    Reset jobs that were marked as processing (e.g., server crashed mid-run).
    """
    async with get_conn() as cur:
        await cur.execute(
            """
            update app.livekit_webhook_jobs
            set status = 'pending',
                locked_at = null,
                updated_at = now(),
                next_run_at = least(next_run_at, now())
            where status = 'processing'
            """
        )


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
                LIMIT %s
                """,
                (capped_limit,),
            )
            rows = await cur.fetchall()
    except errors.UndefinedTable:
        return []
    return [dict(row) for row in rows]


async def create_webhook_job(payload: dict[str, Any]) -> dict[str, Any]:
    event_type = payload.get("event")
    if not event_type:
        raise ValueError("LiveKit webhook payload missing event")
    async with get_conn() as cur:
        await cur.execute(
            """
            insert into app.livekit_webhook_jobs (event, payload)
            values (%s, %s)
            returning id, payload, attempt, next_run_at
            """,
            (event_type, Jsonb(payload)),
        )
        row = await cur.fetchone()
    return dict(row)


async def lock_webhook_job(job_id: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            update app.livekit_webhook_jobs
            set status = 'processing',
                locked_at = now(),
                last_attempt_at = now(),
                updated_at = now()
            where id = %s
              and (locked_at is null or locked_at < now() - interval '5 minutes')
              and status in ('pending', 'processing')
            returning id, payload, attempt
            """,
            (job_id,),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def fetch_and_lock_due_webhook_jobs(limit: int = 20) -> Iterable[dict[str, Any]]:
    async with get_conn() as cur:
        await cur.execute(
            """
            with candidates as (
                select id
                from app.livekit_webhook_jobs
                where status = 'pending'
                  and locked_at is null
                  and next_run_at <= now()
                order by next_run_at asc
                limit %s
                for update skip locked
            )
            update app.livekit_webhook_jobs as j
            set status = 'processing',
                locked_at = now(),
                last_attempt_at = now(),
                updated_at = now()
            from candidates
            where j.id = candidates.id
            returning j.id, j.payload, j.attempt
            """,
            (limit,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def delete_webhook_job(job_id: str) -> None:
    async with get_conn() as cur:
        await cur.execute(
            "delete from app.livekit_webhook_jobs where id = %s",
            (job_id,),
        )


async def schedule_webhook_retry(
    job_id: str,
    *,
    attempt: int,
    next_run_at: datetime,
    last_error: str,
) -> None:
    async with get_conn() as cur:
        await cur.execute(
            """
            update app.livekit_webhook_jobs
            set attempt = %s,
                status = 'pending',
                locked_at = null,
                next_run_at = %s,
                last_error = %s,
                updated_at = now()
            where id = %s
            """,
            (attempt, next_run_at, last_error, job_id),
        )


async def mark_webhook_job_failed(
    job_id: str,
    *,
    attempt: int,
    last_error: str,
) -> None:
    async with get_conn() as cur:
        await cur.execute(
            """
            update app.livekit_webhook_jobs
            set attempt = %s,
                status = 'failed',
                locked_at = null,
                next_run_at = null,
                last_error = %s,
                updated_at = now()
            where id = %s
            """,
            (attempt, last_error, job_id),
        )
