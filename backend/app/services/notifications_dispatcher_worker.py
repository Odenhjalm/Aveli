from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

from psycopg.rows import dict_row

from ..config import settings
from ..db import pool
from ..observability import log_buffer
from . import push_provider

logger = logging.getLogger(__name__)

_worker_task: asyncio.Task[None] | None = None
_verification_mode = False
_worker_run_started_at: float | None = None
_DEFAULT_BATCH_SIZE = 50
_MAX_ATTEMPTS = 5


async def _deliver_stub(delivery: dict[str, Any]) -> tuple[str, str | None]:
    del delivery
    return "sent", None


def _push_message_for_delivery(delivery: dict[str, Any]) -> push_provider.PushMessage:
    payload = delivery.get("payload_json")
    payload_dict = payload if isinstance(payload, dict) else {}
    title = "New lesson unlocked"
    body = str(payload_dict.get("title") or "").strip() or title
    data = {
        "notification_id": str(delivery["notification_id"]),
        "type": str(delivery["notification_type"]),
    }
    for key in ("course_id", "lesson_id"):
        value = payload_dict.get(key)
        if value is not None:
            data[key] = str(value)
    return push_provider.PushMessage(title=title, body=body, data=data)


async def _ensure_push_device_deliveries(
    cur: Any,
    delivery: dict[str, Any],
) -> None:
    await cur.execute(
        """
        insert into app.notification_push_device_deliveries (
            delivery_id,
            notification_id,
            device_id
        )
        select %s::uuid,
               %s::uuid,
               ud.id
          from app.user_devices as ud
         where ud.user_id = %s::uuid
           and ud.active = true
        on conflict (delivery_id, device_id) do nothing
        """,
        (
            delivery["delivery_id"],
            delivery["notification_id"],
            delivery["user_id"],
        ),
    )


async def _push_delivery_summary(cur: Any, delivery_id: str) -> tuple[int, int, int]:
    await cur.execute(
        """
        select count(*)::int as total,
               count(*) filter (where status = 'sent')::int as sent,
               count(*) filter (where status = 'failed')::int as failed
          from app.notification_push_device_deliveries
         where delivery_id = %s::uuid
        """,
        (delivery_id,),
    )
    row = await cur.fetchone()
    if row is None:
        return 0, 0, 0
    return int(row["total"] or 0), int(row["sent"] or 0), int(row["failed"] or 0)


async def _deliver_push(cur: Any, delivery: dict[str, Any]) -> tuple[str, str | None]:
    await _ensure_push_device_deliveries(cur, delivery)
    await cur.execute(
        """
        select pdd.id::text as push_delivery_id,
               ud.id::text as device_id,
               ud.push_token,
               ud.platform
          from app.notification_push_device_deliveries as pdd
          join app.user_devices as ud
            on ud.id = pdd.device_id
         where pdd.delivery_id = %s::uuid
           and pdd.status <> 'sent'
           and pdd.attempts < %s
         order by ud.created_at asc, ud.id asc
         for update of pdd
        """,
        (delivery["delivery_id"], _MAX_ATTEMPTS),
    )
    device_deliveries = [dict(row) for row in await cur.fetchall()]
    if not device_deliveries:
        total, sent, failed = await _push_delivery_summary(cur, delivery["delivery_id"])
        if total == 0 or total == sent:
            return "sent", None
        return "failed", "push delivery has no remaining deliverable devices"

    message = _push_message_for_delivery(delivery)
    try:
        provider = push_provider.get_push_provider()
        provider_error: Exception | None = None
    except Exception as exc:  # configuration errors are recorded per device
        provider = None
        provider_error = exc

    failed_errors: list[str] = []
    for device_delivery in device_deliveries:
        status = "sent"
        error_text = None
        provider_message_id = None
        try:
            if provider_error is not None:
                raise provider_error
            if provider is None:
                raise push_provider.PushProviderConfigurationError(
                    "push provider is not configured"
                )
            provider_message_id = await provider.send(
                token=str(device_delivery["push_token"]),
                message=message,
            )
        except Exception as exc:
            status = "failed"
            error_text = str(exc)[:1000]
            failed_errors.append(error_text)
            logger.exception(
                "Push delivery failed delivery_id=%s device_id=%s",
                delivery["delivery_id"],
                device_delivery["device_id"],
            )

        await cur.execute(
            """
            update app.notification_push_device_deliveries
               set status = %s,
                   attempts = attempts + 1,
                   provider_message_id = %s,
                   last_attempt_at = clock_timestamp(),
                   error_text = %s
             where id = %s::uuid
            """,
            (
                status,
                provider_message_id,
                error_text,
                device_delivery["push_delivery_id"],
            ),
        )

    total, sent, failed = await _push_delivery_summary(cur, delivery["delivery_id"])
    if total == 0 or total == sent:
        return "sent", None
    if failed > 0:
        return "failed", (failed_errors[0] if failed_errors else "push delivery failed")
    return "failed", "push delivery did not reach all devices"


async def _deliver(cur: Any, delivery: dict[str, Any]) -> tuple[str, str | None]:
    channel = str(delivery.get("channel") or "").strip()
    if channel == "push":
        return await _deliver_push(cur, delivery)
    return await _deliver_stub(delivery)


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
                try:
                    status, error_text = await _deliver(cur, delivery)
                except Exception as exc:  # pragma: no cover - defensive batch boundary
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
