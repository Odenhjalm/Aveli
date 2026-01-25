import asyncio

import pytest

from app.services import media_transcode_worker as worker

pytestmark = pytest.mark.anyio("asyncio")


async def test_worker_reschedules_locked_batch_on_cancel(monkeypatch):
    batch = [{"id": "a"}, {"id": "b"}]

    async def fake_fetch_and_lock_pending_media_assets(*, limit, max_attempts):
        return batch

    rescheduled: list[str] = []

    async def fake_defer_media_asset_processing(*, media_id):
        rescheduled.append(str(media_id))

    async def fake_process_asset(asset):
        raise asyncio.CancelledError

    monkeypatch.setattr(
        worker.media_assets_repo,
        "fetch_and_lock_pending_media_assets",
        fake_fetch_and_lock_pending_media_assets,
        raising=True,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "defer_media_asset_processing",
        fake_defer_media_asset_processing,
        raising=True,
    )
    monkeypatch.setattr(worker, "_process_asset", fake_process_asset, raising=True)

    await worker._poll_loop()

    assert set(rescheduled) == {"a", "b"}
