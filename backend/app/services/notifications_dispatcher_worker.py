from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

from psycopg.rows import dict_row

from ..config import settings
from ..db import pool
from ..observability import log_buffer

logger = logging.getLogger(__name__)

_worker_task: asyncio.Task[None] | None = None
_verification_mode = False
_worker_run_started_at: float | None = None
_DEFAULT_BATCH_SIZE = 50
_MAX_ATTEMPTS = 5


async def _deliver_stub(delivery: dict[str, Any]) -> None:
    del delivery


async def _verification_idle_loop() -> None:
    while True:
        try:
            await asyncio.sleep(3600)
        except asyncio.CancelledError:
            break


async def start_worker(*, verification_mode: bool = False) -> None:
    global _worker_task, _verification_mode, _worker_run_started_at
    if _worker_task is not None:
        return
    _verification_mode = verification_mode
    _worker_run_started_at = time.time()
    if verification_mode:
        _worker_task = asyncio.create_task(_verification_idle_loop())
        logger.info("Notification dispatcher started in no-write verification mode")
        return
    _worker_task = asyncio.create_task(_poll_loop())
    logger.info("Notification dispatcher started")


async def stop_worker() -> None:
    global _worker_task, _verification_mode, _worker_run_started_at
    if _worker_task is None:
        return
    _worker_task.cancel()
    try:
        await _worker_task
    except asyncio.CancelledError:
        pass
    _worker_task = None
    _verification_mode = False
    _worker_run_started_at = None
    logger.info("Notification dispatcher stopped")


async def run_once(*, limit: int = _DEFAULT_BATCH_SIZE) -> int:
    normalized_limit = max(1, int(limit))
    processed = 0

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select d.id::text as delivery_id,
                       d.notification_id::text as notification_id,
                       d.channel,
                       d.status,
                       d.attempts,
                       n.user_id::text as user_id,
                       n.type as notification_type,
                       n.payload_json,
                       n.dedup_key
                  from app.notification_deliveries as d
                  join app.notifications as n
                    on n.id = d.notification_id
                 where d.status = 'pending'
                   and d.attempts < %s
                 order by d.attempts asc, d.id asc
                 limit %s
                 for update of d skip locked
                """,
                (_MAX_ATTEMPTS, normalized_limit),
            )
            deliveries = [dict(row) for row in await cur.fetchall()]

            for delivery in deliveries:
                error_text = None
                status = "sent"
                try:
                    await _deliver_stub(delivery)
                except Exception as exc:  # pragma: no cover - defensive stub boundary
                    status = "failed"
                    error_text = str(exc)[:1000]
                    logger.exception(
                        "Notification delivery failed delivery_id=%s",
                        delivery["delivery_id"],
                    )

                await cur.execute(
                    """
                    update app.notification_deliveries
                       set status = %s,
                           attempts = attempts + 1,
                           last_attempt_at = clock_timestamp(),
                           error_text = %s
                     where id = %s::uuid
                       and status = 'pending'
                    """,
                    (status, error_text, delivery["delivery_id"]),
                )
                processed += cur.rowcount

        await conn.commit()

    logger.info(
        "NOTIFICATION_DISPATCHER_RUN_SUMMARY",
        extra={"processed": processed},
    )
    return processed


async def _poll_loop() -> None:
    while True:
        try:
            await run_once()
        except asyncio.CancelledError:
            break
        except Exception as exc:  # pragma: no cover - defensive worker logging
            logger.exception("Notification dispatcher error: %s", exc)
        await asyncio.sleep(settings.notification_dispatcher_interval_seconds)


def get_metrics() -> dict[str, Any]:
    if _worker_run_started_at is None:
        last_error = None
    else:
        last_error = next(
            iter(
                log_buffer.list_events(
                    limit=1,
                    min_level="ERROR",
                    logger_names={__name__},
                    since_epoch_seconds=_worker_run_started_at,
                )
            ),
            None,
        )
    return {
        "worker_running": _worker_task is not None and not _worker_task.done(),
        "poll_interval_seconds": settings.notification_dispatcher_interval_seconds,
        "last_error": last_error,
        "verification_mode": _verification_mode,
        "write_suppressed": _verification_mode,
    }


async def _run_worker_forever() -> None:
    from ..db import pool

    await pool.open(wait=True)
    try:
        await start_worker()
        while True:
            await asyncio.sleep(3600)
    finally:
        await stop_worker()
        await pool.close()


if __name__ == "__main__":
    from ..logging_utils import setup_logging

    setup_logging()
    try:
        asyncio.run(_run_worker_forever())
    except KeyboardInterrupt:
        logger.info("Notification dispatcher stopped")


__all__ = ["get_metrics", "run_once", "start_worker", "stop_worker"]
