from __future__ import annotations

import asyncio
import logging
import os
import time
from datetime import datetime, timedelta, timezone
from typing import Any

from ..config import settings
from ..db import pool
from ..observability import log_buffer
from ..repositories import lesson_completions
from ..repositories.lesson_completions import LessonCompletionAlreadyExistsError
from . import notification_service

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
                select ce.id,
                       ce.user_id,
                       ce.course_id,
                       ce.current_unlock_position
                from app.course_enrollments as ce
                where app.resolve_course_drip_mode(ce.course_id) in (
                    'legacy_uniform_drip',
                    'custom_lesson_offsets'
                )
                order by ce.granted_at asc, ce.id asc
                limit 100
                """
            )
            candidates = await cur.fetchall()
            advanced_enrollments = 0
            for (
                enrollment_id,
                user_id,
                course_id,
                current_unlock_position,
            ) in candidates:
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
                    await notification_service.create_notification(
                        str(user_id),
                        "course_drip_lesson_unlocked",
                        {
                            "course_id": str(course_id),
                            "enrollment_id": str(enrollment_id),
                            "previous_unlock_position": int(
                                current_unlock_position or 0
                            ),
                            "current_unlock_position": next_unlock_position,
                            "evaluated_at": current_time.isoformat(),
                        },
                        (
                            "course_drip_lesson_unlocked:"
                            f"{enrollment_id}:{next_unlock_position}"
                        ),
                        conn=conn,
                    )

            await cur.execute(
                """
                select ce.id
                from app.course_enrollments as ce
                join app.courses as c
                  on c.id = ce.course_id
                where c.required_enrollment_source = 'intro_enrollment'::app.course_enrollment_source
                  and app.resolve_course_drip_mode(ce.course_id) in (
                    'legacy_uniform_drip',
                    'custom_lesson_offsets',
                    'no_drip_immediate_access'
                  )
                order by ce.granted_at asc, ce.id asc
                limit 100
                """
            )
            auto_completion_candidates = await cur.fetchall()

        for (enrollment_id,) in auto_completion_candidates:
            candidate = await lesson_completions.get_intro_final_lesson_auto_completion_candidate(
                enrollment_id=str(enrollment_id),
                conn=conn,
            )
            if candidate is None:
                continue

            final_unlock_at = candidate["final_unlock_at"]
            if final_unlock_at is None:
                continue

            if current_time < final_unlock_at + timedelta(days=7):
                continue

            existing_completion = await lesson_completions.get_lesson_completion(
                user_id=str(candidate["user_id"]),
                lesson_id=str(candidate["final_lesson_id"]),
                conn=conn,
            )
            if existing_completion is not None:
                continue

            try:
                await lesson_completions.create_lesson_completion(
                    user_id=str(candidate["user_id"]),
                    course_id=str(candidate["course_id"]),
                    lesson_id=str(candidate["final_lesson_id"]),
                    completion_source="auto_final_lesson",
                    conn=conn,
                )
            except LessonCompletionAlreadyExistsError:
                continue

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
