import pytest

from app.repositories import livekit_jobs as livekit_jobs_repo
from app.services import livekit as livekit_service
from app.services import livekit_events
from app.services.livekit_webhook_handler import handle_livekit_webhook

pytestmark = pytest.mark.anyio("asyncio")


async def test_livekit_worker_start_is_inert():
    await livekit_events.start_worker()
    await livekit_events.start_worker(verification_mode=True)

    metrics = livekit_events.get_metrics()
    assert metrics["worker_running"] is False
    assert metrics["queue_size"] == 0
    assert metrics["pending_jobs"] == 0
    assert metrics["failed_jobs"] == 0
    assert metrics["verification_mode"] is False
    assert metrics["write_suppressed"] is True


async def test_livekit_enqueue_is_forbidden():
    with pytest.raises(livekit_events.LiveKitPausedError, match="paused"):
        await livekit_events.enqueue_webhook({"event": "room_started"})


async def test_livekit_event_processing_is_forbidden():
    with pytest.raises(livekit_events.LiveKitPausedError, match="paused"):
        await livekit_events.process_livekit_event({"event": "participant_joined"})


async def test_livekit_room_create_is_forbidden():
    with pytest.raises(livekit_service.LiveKitRESTError, match="pausat"):
        await livekit_service.create_room("room")


async def test_livekit_room_end_is_forbidden():
    with pytest.raises(livekit_service.LiveKitRESTError, match="pausat"):
        await livekit_service.end_room("room")


async def test_livekit_webhook_handler_returns_inert_response():
    response = await handle_livekit_webhook(
        {"event": "room_started"},
        signature="anything",
    )

    assert response == {
        "queued": False,
        "status": "paused",
        "reason": "livekit_runtime_paused",
    }


@pytest.mark.parametrize(
    ("function_name", "args", "kwargs"),
    [
        ("release_processing_webhook_jobs", (), {}),
        ("create_webhook_job", ({"event": "room_started"},), {}),
        ("lock_webhook_job", ("job-1",), {}),
        ("fetch_and_lock_due_webhook_jobs", (), {}),
        ("delete_webhook_job", ("job-1",), {}),
        (
            "schedule_webhook_retry",
            ("job-1",),
            {"attempt": 1, "next_run_at": object(), "last_error": "boom"},
        ),
        ("mark_webhook_job_failed", ("job-1",), {"attempt": 1, "last_error": "boom"}),
    ],
)
async def test_livekit_queue_mutators_are_forbidden(function_name, args, kwargs):
    function = getattr(livekit_jobs_repo, function_name)

    with pytest.raises(RuntimeError, match="queue mutation is forbidden"):
        await function(*args, **kwargs)
