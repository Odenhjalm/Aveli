import asyncio
import json
from datetime import datetime, timezone
from typing import Any

import pytest

from app.services import livekit_events

pytestmark = pytest.mark.anyio("asyncio")


async def test_process_room_started_logs_activity(monkeypatch):
    recorded = []

    async def fake_get_seminar_session(session_id: str):
        return {"id": session_id, "seminar_id": "33333333-3333-4333-8333-333333333333"}

    async def fake_get_session_by_room(room_name: str):
        return None

    async def fake_update_seminar_session(session_id: str, fields: dict):
        assert fields["status"] == "live"

    async def fake_insert_activity(**kwargs):
        recorded.append(kwargs)

    monkeypatch.setattr(
        livekit_events.repositories, "get_seminar_session", fake_get_seminar_session
    )
    monkeypatch.setattr(
        livekit_events.repositories, "get_session_by_room", fake_get_session_by_room
    )
    monkeypatch.setattr(
        livekit_events.repositories, "update_seminar_session", fake_update_seminar_session
    )
    monkeypatch.setattr(
        livekit_events.repositories, "insert_activity", fake_insert_activity
    )

    payload = {
        "event": "room_started",
        "room": {
            "name": "seminar-room",
            "metadata": json.dumps({"session_id": "22222222-2222-4222-8222-222222222222"}),
        },
    }

    await livekit_events.process_livekit_event(payload)

    assert recorded
    assert recorded[0]["activity_type"] == "room_created"
    assert recorded[0]["subject_table"] == "seminars"
    assert recorded[0]["subject_id"] == "33333333-3333-4333-8333-333333333333"


async def test_process_participant_joined_logs_activity(monkeypatch):
    touch_calls = []
    activity_calls = []

    async def fake_touch_attendee_presence(**kwargs):
        touch_calls.append(kwargs)

    async def fake_insert_activity(**kwargs):
        activity_calls.append(kwargs)

    monkeypatch.setattr(
        livekit_events.repositories, "touch_attendee_presence", fake_touch_attendee_presence
    )
    monkeypatch.setattr(
        livekit_events.repositories, "insert_activity", fake_insert_activity
    )

    payload = {
        "event": "participant_joined",
        "room": {"name": "seminar-room"},
        "participant": {
            "identity": "user-identity",
            "sid": "PA_sid",
            "metadata": json.dumps(
                {
                    "seminar_id": "44444444-4444-4444-8444-444444444444",
                    "user_id": "55555555-5555-4555-8555-555555555555",
                }
            ),
        },
    }

    await livekit_events.process_livekit_event(payload)

    assert touch_calls
    assert activity_calls
    assert activity_calls[0]["activity_type"] == "participant_joined"
    assert activity_calls[0]["actor_id"] == "55555555-5555-4555-8555-555555555555"


async def test_webhook_queue_retries(monkeypatch, anyio_backend):
    if anyio_backend != "asyncio":
        pytest.skip("LiveKit queue worker requires asyncio backend")
    calls = []
    jobs: dict[str, dict[str, Any]] = {}

    async def fake_release():
        for job in jobs.values():
            if job["status"] == "processing":
                job["status"] = "pending"
                job["locked"] = False

    async def fake_counts():
        pending = sum(
            1 for job in jobs.values() if job["status"] in {"pending", "processing"}
        )
        failed = sum(1 for job in jobs.values() if job["status"] == "failed")
        return {"pending": pending, "failed": failed}

    async def fake_create(payload):
        job_id = f"job-{len(jobs) + 1}"
        now = datetime.now(timezone.utc)
        jobs[job_id] = {
            "id": job_id,
            "payload": payload,
            "attempt": 0,
            "next_run": now,
            "status": "pending",
            "locked": False,
            "last_error": None,
        }
        return {"id": job_id, "payload": payload, "attempt": 0, "next_run_at": now}

    async def fake_lock(job_id: str):
        job = jobs.get(job_id)
        if job and not job["locked"] and job["status"] == "pending":
            job["locked"] = True
            job["status"] = "processing"
            return {"id": job_id, "payload": job["payload"], "attempt": job["attempt"]}
        return None

    async def fake_fetch(limit: int = 20):
        now = datetime.now(timezone.utc)
        items = []
        for job_id, job in list(jobs.items()):
            if len(items) >= limit:
                break
            if job["status"] == "pending" and not job["locked"] and job["next_run"] <= now:
                job["locked"] = True
                job["status"] = "processing"
                job["attempt"] = job["attempt"]
                items.append(
                    {"id": job_id, "payload": job["payload"], "attempt": job["attempt"]}
                )
        return items

    async def fake_delete(job_id: str):
        jobs.pop(job_id, None)

    async def fake_schedule(job_id: str, *, attempt: int, next_run_at, last_error: str):
        job = jobs[job_id]
        job["attempt"] = attempt
        job["next_run"] = next_run_at
        job["last_error"] = last_error
        job["status"] = "pending"
        job["locked"] = False

    async def fake_fail(job_id: str, *, attempt: int, last_error: str):
        job = jobs[job_id]
        job["attempt"] = attempt
        job["last_error"] = last_error
        job["status"] = "failed"
        job["locked"] = False

    async def fake_process(payload):
        calls.append(payload)
        if len(calls) == 1:
            raise RuntimeError("boom")

    monkeypatch.setattr(livekit_events, "process_livekit_event", fake_process)
    monkeypatch.setattr(livekit_events, "BASE_DELAY_SECONDS", 0.01, raising=False)
    monkeypatch.setattr(livekit_events, "MAX_DELAY_SECONDS", 0.05, raising=False)
    monkeypatch.setattr(
        livekit_events.repositories, "release_processing_webhook_jobs", fake_release
    )
    monkeypatch.setattr(
        livekit_events.repositories, "get_webhook_job_counts", fake_counts
    )
    monkeypatch.setattr(
        livekit_events.repositories, "create_webhook_job", fake_create
    )
    monkeypatch.setattr(
        livekit_events.repositories, "lock_webhook_job", fake_lock
    )
    monkeypatch.setattr(
        livekit_events.repositories,
        "fetch_and_lock_due_webhook_jobs",
        fake_fetch,
    )
    monkeypatch.setattr(
        livekit_events.repositories, "delete_webhook_job", fake_delete
    )
    monkeypatch.setattr(
        livekit_events.repositories,
        "schedule_webhook_retry",
        fake_schedule,
    )
    monkeypatch.setattr(
        livekit_events.repositories,
        "mark_webhook_job_failed",
        fake_fail,
    )

    await livekit_events.start_worker()
    try:
        await livekit_events.enqueue_webhook({"event": "room_started", "room": {}})
        await asyncio.sleep(0.15)
    finally:
        await livekit_events.stop_worker()

    assert len(calls) >= 2
