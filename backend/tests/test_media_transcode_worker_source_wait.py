import pytest

from app.services import media_transcode_worker as worker


@pytest.mark.anyio
async def test_worker_defers_without_consuming_attempt_when_presign_object_missing(
    monkeypatch,
):
    calls: dict[str, str] = {}

    async def defer_media_asset_processing(*, media_id: str) -> None:
        calls["defer"] = media_id

    async def increment_processing_attempts(*, media_id: str) -> None:
        raise AssertionError("processing_attempts must not be consumed while source is missing")

    async def mark_media_asset_failed(*args, **kwargs) -> None:
        raise AssertionError("media_asset must not be marked failed while source is missing")

    class DummyStorage:
        bucket = "course-media"

        async def get_presigned_url(self, *args, **kwargs):
            raise worker.storage_service.StorageObjectNotFoundError(
                "Supabase Storage object not found",
                status_code=400,
                error="not_found",
            )

    monkeypatch.setattr(
        worker.media_assets_repo,
        "defer_media_asset_processing",
        defer_media_asset_processing,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "increment_processing_attempts",
        increment_processing_attempts,
    )
    monkeypatch.setattr(worker.media_assets_repo, "mark_media_asset_failed", mark_media_asset_failed)
    monkeypatch.setattr(worker.storage_service, "get_storage_service", lambda bucket: DummyStorage())

    await worker._process_asset(
        {
            "id": "media-1",
            "processing_attempts": 0,
            "media_type": "audio",
            "purpose": "lesson_audio",
            "original_object_path": "media/source/audio/lesson/foo.wav",
            "storage_bucket": "course-media",
        }
    )

    assert calls == {"defer": "media-1"}


@pytest.mark.anyio
async def test_worker_defers_without_consuming_attempt_when_download_returns_404(monkeypatch):
    calls: dict[str, str] = {}

    async def defer_media_asset_processing(*, media_id: str) -> None:
        calls["defer"] = media_id

    async def increment_processing_attempts(*, media_id: str) -> None:
        raise AssertionError("processing_attempts must not be consumed while source is missing")

    async def mark_media_asset_failed(*args, **kwargs) -> None:
        raise AssertionError("media_asset must not be marked failed while source is missing")

    class DummySigned:
        url = "https://example.invalid/signed"

    class DummyStorage:
        bucket = "course-media"

        async def get_presigned_url(self, *args, **kwargs):
            return DummySigned()

    async def download_to_file(url, destination):
        raise worker.SourceNotReadyError("Source object not yet available")

    monkeypatch.setattr(
        worker.media_assets_repo,
        "defer_media_asset_processing",
        defer_media_asset_processing,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "increment_processing_attempts",
        increment_processing_attempts,
    )
    monkeypatch.setattr(worker.media_assets_repo, "mark_media_asset_failed", mark_media_asset_failed)
    monkeypatch.setattr(worker.storage_service, "get_storage_service", lambda bucket: DummyStorage())
    monkeypatch.setattr(worker, "_download_to_file", download_to_file)

    await worker._process_asset(
        {
            "id": "media-2",
            "processing_attempts": 0,
            "media_type": "audio",
            "purpose": "lesson_audio",
            "original_object_path": "media/source/audio/lesson/foo.wav",
            "storage_bucket": "course-media",
        }
    )

    assert calls == {"defer": "media-2"}

