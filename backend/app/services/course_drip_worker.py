from __future__ import annotations

import asyncio
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any

from ..config import settings
from ..db import pool
from ..observability import log_buffer

logger = logging.getLogger(__name__)

_worker_task: asyncio.Task[None] | None = None
_verification_mode = False
_worker_run_started_at: float | None = None


def _env_worker_enabled() -> bool:
    return os.environ.get("RUN_COURSE_DRIP_WORKER", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "y",
        "on",
    }


def _enablement_state() -> dict[str, bool]:
    enabled_by_mcp_mode = settings.mcp_workers_enabled
    enabled_by_env = _env_worker_enabled()
    return {
        "enabled_by_mcp_mode": enabled_by_mcp_mode,
        "enabled_by_env": enabled_by_env,
        "enabled_by_config": enabled_by_mcp_mode,
        "final_state": enabled_by_mcp_mode or enabled_by_env,
    }


async def _verification_idle_loop() -> None:
    while True:
        try:
            await asyncio.sleep(3600)
        except asyncio.CancelledError:
            break


async def start_worker(*, verification_mode: bool = False) -> None:
    global _worker_task, _verification_mode, _worker_run_started_at
    enablement = _enablement_state()
    if not enablement["final_state"]:
        logger.info("Course drip worker disabled", extra=enablement)
        return
    if _worker_task is not None:
        return
    _verification_mode = verification_mode
    _worker_run_started_at = time.time()
    if verification_mode:
        _worker_task = asyncio.create_task(_verification_idle_loop())
        logger.info(
            "Course drip worker started in no-write verification mode",
            extra={**enablement, "verification_mode": True, "write_suppressed": True},
        )
        return
    _worker_task = asyncio.create_task(_poll_loop())
    logger.info("Course drip worker started", extra=enablement)


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
    logger.info("Course drip worker stopped")


async def run_once(*, now: datetime | None = None) -> int:
    current_time = now or datetime.now(timezone.utc)
    async with pool.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                select ce.id, ce.current_unlock_position
                from app.course_enrollments as ce
                join app.courses as c on c.id = ce.course_id
                where c.drip_enabled = true
                order by ce.updated_at asc, ce.id asc
                limit 100
                """
            )
            candidates = await cur.fetchall()
            advanced_enrollments = 0
            for enrollment_id, current_unlock_position in candidates:
                await cur.execute(
                    """
                    select current_unlock_position
                    from app.canonical_worker_advance_course_enrollment_drip(%s, %s)
                    """,
                    (enrollment_id, current_time),
                )
                row = await cur.fetchone()
                next_unlock_position = int(row[0] if row else 0)
                if next_unlock_position > int(current_unlock_position or 0):
                    advanced_enrollments += 1
            await conn.commit()
    logger.info(
        "COURSE_DRIP_WORKER_RUN_SUMMARY",
        extra={"advanced_enrollments": advanced_enrollments},
    )
    return advanced_enrollments


async def _poll_loop() -> None:
    while True:
        try:
            await run_once()
        except asyncio.CancelledError:
            break
        except Exception as exc:  # pragma: no cover - defensive worker logging
            logger.exception("Course drip worker error: %s", exc)
        await asyncio.sleep(settings.course_drip_worker_interval_seconds)


def get_metrics() -> dict[str, Any]:
    enablement = _enablement_state()
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
        **enablement,
        "poll_interval_seconds": settings.course_drip_worker_interval_seconds,
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
    enablement = _enablement_state()
    if not enablement["final_state"]:
        logger.info("Course drip worker disabled", extra=enablement)
        raise SystemExit(0)
    try:
        asyncio.run(_run_worker_forever())
    except KeyboardInterrupt:
        logger.info("Course drip worker stopped")


__all__ = ["get_metrics", "run_once", "start_worker", "stop_worker"]
