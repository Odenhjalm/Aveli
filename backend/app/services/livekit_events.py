from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import sentry_sdk

from .. import metrics, repositories
from ..services import livekit as livekit_service

logger = logging.getLogger(__name__)

MAX_RETRIES = 5
BASE_DELAY_SECONDS = 1.0
MAX_DELAY_SECONDS = 30.0
POLL_INTERVAL_SECONDS = 1.0


@dataclass
class LiveKitWebhookEvent:
    job_id: str
    payload: dict[str, Any]
    attempt: int


_queue: Optional[asyncio.Queue[LiveKitWebhookEvent]] = None
_worker_task: Optional[asyncio.Task[None]] = None
_poller_task: Optional[asyncio.Task[None]] = None
_pending_jobs: int = 0
_failed_jobs: int = 0
_last_failure: Optional[dict[str, Any]] = None


def _sentry_enabled() -> bool:
    return sentry_sdk.Hub.current.client is not None


def _capture_failure(event: "LiveKitWebhookEvent", exc: Exception) -> None:
    if not _sentry_enabled():
        return
    payload = event.payload if isinstance(event.payload, dict) else {}
    event_type = payload.get("event")
    event_id = payload.get("id")
    with sentry_sdk.push_scope() as scope:
        scope.set_tag("webhook.provider", "livekit")
        scope.set_tag("webhook.status", "failed")
        scope.set_tag("alert_kind", "webhook_failure")
        if event_type:
            scope.set_tag("webhook.event_type", str(event_type))
        if event_id:
            scope.set_tag("webhook.event_id", str(event_id))
        sentry_sdk.capture_exception(exc)


def get_metrics() -> dict[str, Any]:
    queue_size = _queue.qsize() if _queue is not None else 0
    metrics.livekit_webhook_queue_size.set(queue_size)
    metrics.livekit_webhook_pending_jobs.set(_pending_jobs)
    return {
        "worker_running": _queue is not None,
        "queue_size": queue_size,
        "pending_jobs": _pending_jobs,
        "failed_jobs": _failed_jobs,
        "last_failure": _last_failure,
    }


async def start_worker() -> None:
    global _queue, _worker_task, _poller_task, _pending_jobs, _failed_jobs, _last_failure
    if _queue is not None:
        return

    await repositories.release_processing_webhook_jobs()
    counts = await repositories.get_webhook_job_counts()
    _pending_jobs = counts["pending"]
    _failed_jobs = counts["failed"]
    _last_failure = None
    metrics.livekit_webhook_pending_jobs.set(_pending_jobs)
    metrics.livekit_webhook_queue_size.set(0)

    _queue = asyncio.Queue()
    _worker_task = asyncio.create_task(_worker_loop())

    initial_jobs = await repositories.fetch_and_lock_due_webhook_jobs(limit=50)
    for job in initial_jobs:
        await _queue_job(job)

    _poller_task = asyncio.create_task(_poller_loop())
    logger.info("LiveKit webhook worker started")


async def stop_worker() -> None:
    global _queue, _worker_task, _poller_task
    if _queue is None:
        return

    if _poller_task:
        _poller_task.cancel()
        try:
            await _poller_task
        except asyncio.CancelledError:
            pass
        _poller_task = None

    await _queue.join()

    if _worker_task:
        _worker_task.cancel()
        try:
            await _worker_task
        except asyncio.CancelledError:
            pass
        _worker_task = None

    _queue = None
    logger.info("LiveKit webhook worker stopped")


async def enqueue_webhook(payload: dict[str, Any]) -> None:
    if _queue is None:
        raise RuntimeError("LiveKit webhook worker not initialised")

    job = await repositories.create_webhook_job(payload)
    global _pending_jobs
    _pending_jobs += 1
    metrics.livekit_webhook_pending_jobs.inc()

    locked = await repositories.lock_webhook_job(str(job["id"]))
    if locked:
        await _queue_job(locked)


async def _worker_loop() -> None:
    assert _queue is not None
    while True:
        try:
            event = await _queue.get()
        except asyncio.CancelledError:
            break

        try:
            await process_livekit_event(event.payload)
            await repositories.delete_webhook_job(event.job_id)
            global _pending_jobs
            _pending_jobs = max(0, _pending_jobs - 1)
            metrics.livekit_webhook_pending_jobs.set(_pending_jobs)
            metrics.livekit_webhook_processed_total.inc()
        except Exception as exc:  # pragma: no cover - logged and retried
            logger.exception("LiveKit webhook processing failed: %s", exc)
            await _handle_retry(event, exc)
        finally:
            _queue.task_done()
            metrics.livekit_webhook_queue_size.set(_queue.qsize())


async def _poller_loop() -> None:
    assert _queue is not None
    while True:
        try:
            jobs = await repositories.fetch_and_lock_due_webhook_jobs()
            if jobs:
                for job in jobs:
                    await _queue_job(job)
                continue
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
        except asyncio.CancelledError:
            break
        except Exception as exc:  # pragma: no cover
            logger.exception("LiveKit webhook poller error: %s", exc)
            await asyncio.sleep(POLL_INTERVAL_SECONDS)


async def _queue_job(job: dict[str, Any]) -> None:
    if _queue is None:
        raise RuntimeError("LiveKit webhook worker not initialised")
    await _queue.put(
        LiveKitWebhookEvent(
            job_id=str(job["id"]),
            payload=job["payload"],
            attempt=int(job["attempt"]),
        )
    )
    metrics.livekit_webhook_queue_size.set(_queue.qsize())


async def _handle_retry(event: LiveKitWebhookEvent, exc: Exception) -> None:
    now = datetime.now(timezone.utc)
    next_attempt = event.attempt + 1
    error_message = str(exc)
    global _last_failure, _pending_jobs, _failed_jobs

    if next_attempt >= MAX_RETRIES:
        await repositories.mark_webhook_job_failed(
            event.job_id,
            attempt=next_attempt,
            last_error=error_message,
        )
        _capture_failure(event, exc)
        _pending_jobs = max(0, _pending_jobs - 1)
        metrics.livekit_webhook_pending_jobs.set(_pending_jobs)
        _failed_jobs += 1
        _last_failure = {
            "job_id": event.job_id,
            "error": error_message,
            "attempt": next_attempt,
            "time": now.isoformat(),
            "status": "failed",
        }
        metrics.livekit_webhook_failed_total.inc()
        logger.error(
            "LiveKit webhook reached max retries; marked job %s as failed",
            event.job_id,
        )
        return

    delay = min(BASE_DELAY_SECONDS * (2 ** event.attempt), MAX_DELAY_SECONDS)
    next_run = now + timedelta(seconds=delay)
    await repositories.schedule_webhook_retry(
        event.job_id,
        attempt=next_attempt,
        next_run_at=next_run,
        last_error=error_message,
    )
    _last_failure = {
        "job_id": event.job_id,
        "error": error_message,
        "attempt": next_attempt,
        "time": now.isoformat(),
        "next_run_at": next_run.isoformat(),
        "status": "scheduled_retry",
    }
    metrics.livekit_webhook_retries_total.inc()
    asyncio.create_task(_delayed_requeue(event.job_id, delay))


async def _delayed_requeue(job_id: str, delay: float) -> None:
    try:
        await asyncio.sleep(delay)
        job = await repositories.lock_webhook_job(job_id)
        if job:
            await _queue_job(job)
    except asyncio.CancelledError:
        raise
    except Exception as exc:  # pragma: no cover
        logger.exception("Failed to requeue LiveKit webhook job %s: %s", job_id, exc)


async def process_livekit_event(payload: dict[str, Any]) -> None:
    event = payload.get("event")
    if not event:
        logger.warning("LiveKit webhook missing event key: %s", payload)
        return

    now = datetime.now(timezone.utc)

    if event in {"room_started", "room_created"}:
        await _handle_room_started(payload, now)
    elif event == "room_finished":
        await _handle_room_finished(payload, now)
    elif event in {"participant_joined", "participant_left"}:
        await _handle_participant_event(payload, now, event)
    elif event == "recording_finished":
        await _handle_recording_finished(payload, now)
    else:
        logger.info("Unhandled LiveKit event '%s'", event)


async def _handle_room_started(payload: dict[str, Any], now: datetime) -> None:
    room = payload.get("room") or {}
    room_name = room.get("name")
    metadata_str = room.get("metadata")
    metadata: dict[str, Any] = {}
    session_id = None
    if metadata_str:
        try:
            metadata = json.loads(metadata_str)
            session_id = metadata.get("session_id")
        except json.JSONDecodeError:
            logger.warning("Invalid metadata JSON in room_started: %s", metadata_str)
    session = None
    if session_id:
        session = await repositories.get_seminar_session(str(session_id))
    elif room_name:
        session = await repositories.get_session_by_room(room_name)
    if not session:
        logger.warning("Room started without session context: %s", room_name)
        return

    await repositories.update_seminar_session(
        session_id=str(session["id"]),
        fields={"status": "live", "started_at": now},
    )
    seminar_id = str(session["seminar_id"])
    await repositories.insert_activity(
        activity_type="room_created",
        actor_id=None,
        subject_table="seminars",
        subject_id=seminar_id,
        summary=f"LiveKit room started ({room_name or 'unknown'})",
        metadata={
            "event": "room_started",
            "room_name": room_name,
            "session_id": str(session["id"]),
            "livekit_metadata": metadata,
        },
        occurred_at=now,
    )


async def _handle_room_finished(payload: dict[str, Any], now: datetime) -> None:
    room = payload.get("room") or {}
    room_name = room.get("name")
    session = None
    if room_name:
        session = await repositories.get_session_by_room(room_name)
    if session:
        await repositories.update_seminar_session(
            session_id=str(session["id"]),
            fields={"status": "ended", "ended_at": now},
        )
        try:
            await livekit_service.end_room(room_name, reason="webhook")
        except livekit_service.LiveKitRESTError:
            logger.warning("LiveKit end_room failed for %s", room_name)


async def _handle_participant_event(
    payload: dict[str, Any],
    now: datetime,
    event: str,
) -> None:
    participant = payload.get("participant") or {}
    metadata_raw = participant.get("metadata")
    metadata: dict[str, Any] = {}
    if metadata_raw:
        try:
            metadata = json.loads(metadata_raw)
        except (TypeError, json.JSONDecodeError):
            logger.warning("Invalid participant metadata: %s", metadata_raw)
            metadata = {}

    seminar_id = metadata.get("seminar_id")
    user_id = metadata.get("user_id")
    if seminar_id and user_id:
        await repositories.touch_attendee_presence(
            seminar_id=str(seminar_id),
            user_id=str(user_id),
            joined_at=now if event == "participant_joined" else None,
            left_at=now if event == "participant_left" else None,
            livekit_identity=participant.get("identity"),
            participant_sid=participant.get("sid"),
        )
        activity_type = (
            "participant_joined" if event == "participant_joined" else "participant_left"
        )
        summary = (
            "Participant joined LiveKit room"
            if event == "participant_joined"
            else "Participant left LiveKit room"
        )
        await repositories.insert_activity(
            activity_type=activity_type,
            actor_id=str(user_id),
            subject_table="seminars",
            subject_id=str(seminar_id),
            summary=summary,
            metadata={
                "event": event,
                "room_name": payload.get("room", {}).get("name"),
                "participant": {
                    "identity": participant.get("identity"),
                    "sid": participant.get("sid"),
                },
            },
            occurred_at=now,
        )
    else:
        logger.info("Participant event missing seminar/user context: %s", metadata)


async def _handle_recording_finished(payload: dict[str, Any], now: datetime) -> None:
    recording = payload.get("recording", {})
    metadata_raw = recording.get("metadata")
    metadata: dict[str, Any] = {}
    if metadata_raw:
        try:
            metadata = json.loads(metadata_raw)
        except (TypeError, json.JSONDecodeError):
            logger.warning("Invalid recording metadata: %s", metadata_raw)
            metadata = {}
    seminar_id = metadata.get("seminar_id")
    session_id = metadata.get("session_id")
    asset_url = recording.get("location") or recording.get("file")
    if seminar_id and asset_url:
        await repositories.upsert_recording(
            seminar_id=str(seminar_id),
            session_id=str(session_id) if session_id else None,
            asset_url=asset_url,
            status="available",
            duration_seconds=recording.get("duration"),
            byte_size=recording.get("size"),
            metadata=metadata,
        )
