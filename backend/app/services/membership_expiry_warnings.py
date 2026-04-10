from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Any

from ..config import settings
from ..db import get_conn
from ..observability import log_buffer
from ..repositories import membership_support as membership_support_repo
from . import email_service

logger = logging.getLogger(__name__)

_worker_task: asyncio.Task[None] | None = None
_WARNING_STEP = "membership_expiry_warning_sent"
_WARNING_TYPE = "expiry_7_day"
_verification_mode = False
_worker_run_started_at: float | None = None


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
        logger.info("Membership expiry warning worker started in no-write verification mode")
        return
    _worker_task = asyncio.create_task(_poll_loop())
    logger.info("Membership expiry warning worker started")


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
    logger.info("Membership expiry warning worker stopped")


async def run_once(*, now: datetime | None = None) -> int:
    current_time = now or datetime.now(timezone.utc)
    window_start = current_time + timedelta(days=7)
    window_end = current_time + timedelta(days=8)
    candidates = await _list_expiring_memberships(window_start, window_end)
    sent_count = 0

    for membership in candidates:
        expires_at = membership.get("expires_at")
        membership_id = str(membership["membership_id"])
        user_id = str(membership["user_id"])
        if not isinstance(expires_at, datetime):
            continue
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)

        if await _warning_already_sent(
            membership_id=membership_id,
            expires_at=expires_at,
        ):
            continue

        email = str(membership.get("email") or "").strip()
        if not email:
            continue

        try:
            delivery = await email_service.send_email(
                to_email=email,
                subject="Your Aveli membership expires soon",
                text_body=_build_warning_email_text(
                    display_name=membership.get("display_name"),
                    expires_at=expires_at,
                ),
            )
        except email_service.EmailDeliveryError:
            logger.exception(
                "Failed to send membership expiry warning membership_id=%s user_id=%s",
                membership_id,
                user_id,
            )
            continue

        await membership_support_repo.insert_billing_log(
            user_id=user_id,
            step=_WARNING_STEP,
            info={
                "membership_id": membership_id,
                "expires_at": expires_at.isoformat(),
                "warning_type": _WARNING_TYPE,
                "delivery_mode": delivery.mode,
            },
        )
        sent_count += 1

    logger.info(
        "MEMBERSHIP_EXPIRY_WARNING_RUN_SUMMARY",
        extra={
            "candidates": len(candidates),
            "sent": sent_count,
        },
    )
    return sent_count


async def _poll_loop() -> None:
    while True:
        try:
            await run_once()
        except asyncio.CancelledError:
            break
        except Exception as exc:  # pragma: no cover - defensive worker logging
            logger.exception("Membership expiry warning worker error: %s", exc)
        await asyncio.sleep(settings.membership_expiry_warning_interval_seconds)


async def _list_expiring_memberships(
    window_start: datetime,
    window_end: datetime,
) -> list[dict]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT m.membership_id,
                   m.user_id,
                   m.status,
                   m.expires_at AS expires_at,
                   u.email AS email,
                   p.display_name
              FROM app.memberships m
              JOIN auth.users u ON u.id = m.user_id
              JOIN app.profiles p ON p.user_id = m.user_id
             WHERE (
                   m.status = 'active'
                   OR (m.status = 'canceled' AND m.expires_at > now())
               )
               AND m.expires_at >= %s
               AND m.expires_at < %s
             ORDER BY m.expires_at ASC
            """,
            (window_start, window_end),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in (rows or [])]


async def _warning_already_sent(*, membership_id: str, expires_at: datetime) -> bool:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT 1
              FROM app.billing_logs
             WHERE step = %s
               AND info->>'warning_type' = %s
               AND info->>'membership_id' = %s
               AND info->>'expires_at' = %s
             LIMIT 1
            """,
            (
                _WARNING_STEP,
                _WARNING_TYPE,
                membership_id,
                expires_at.isoformat(),
            ),
        )
        return (await cur.fetchone()) is not None


def _build_warning_email_text(
    *,
    display_name: str | None,
    expires_at: datetime,
) -> str:
    greeting = f"Hello {display_name}," if display_name else "Hello,"
    formatted_date = expires_at.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    return (
        f"{greeting}\n\n"
        "Your Aveli membership expires soon.\n"
        f"Current access ends {formatted_date}.\n\n"
        "If you want to continue without interruption, renew before then.\n"
    )


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
        "poll_interval_seconds": settings.membership_expiry_warning_interval_seconds,
        "last_error": last_error,
        "verification_mode": _verification_mode,
        "write_suppressed": _verification_mode,
    }


__all__ = ["get_metrics", "run_once", "start_worker", "stop_worker"]
