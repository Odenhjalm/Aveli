from datetime import datetime, timedelta, timezone

import pytest

from app.services import media_transcode_worker as worker


@pytest.mark.anyio
async def test_worker_defers_without_consuming_attempt_when_presign_object_missing(
    monkeypatch,
):
    fixed_now = datetime(2026, 1, 25, tzinfo=timezone.utc)
    monkeypatch.setattr(worker, "_now", lambda: fixed_now)
    monkeypatch.setattr(worker.settings, "media_transcode_poll_interval_seconds", 10)

    calls: dict[str, object] = {}

    async def defer_media_asset_processing(
        *, media_id: str, next_retry_at=None
    ) -> None:
        calls["defer"] = media_id
        calls["next_retry_at"] = next_retry_at

    async def increment_processing_attempts(*, media_id: str) -> None:
        raise AssertionError(
            "processing_attempts must not be consumed while source is missing"
        )

    async def mark_media_asset_failed(*args, **kwargs) -> None:
        raise AssertionError(
            "media_asset must not be marked failed while source is missing"
        )

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
    monkeypatch.setattr(
        worker.media_assets_repo, "mark_media_asset_failed", mark_media_asset_failed
    )
    monkeypatch.setattr(
        worker.storage_service, "get_storage_service", lambda bucket: DummyStorage()
    )

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

    assert calls == {
        "defer": "media-1",
        "next_retry_at": fixed_now + timedelta(seconds=10),
    }


@pytest.mark.anyio
async def test_worker_defers_without_consuming_attempt_when_download_returns_404(
    monkeypatch,
):
    fixed_now = datetime(2026, 1, 25, tzinfo=timezone.utc)
    monkeypatch.setattr(worker, "_now", lambda: fixed_now)
    monkeypatch.setattr(worker.settings, "media_transcode_poll_interval_seconds", 10)

    calls: dict[str, object] = {}

    async def defer_media_asset_processing(
        *, media_id: str, next_retry_at=None
    ) -> None:
        calls["defer"] = media_id
        calls["next_retry_at"] = next_retry_at

    async def increment_processing_attempts(*, media_id: str) -> None:
        raise AssertionError(
            "processing_attempts must not be consumed while source is missing"
        )

    async def mark_media_asset_failed(*args, **kwargs) -> None:
        raise AssertionError(
            "media_asset must not be marked failed while source is missing"
        )

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
    monkeypatch.setattr(
        worker.media_assets_repo, "mark_media_asset_failed", mark_media_asset_failed
    )
    monkeypatch.setattr(
        worker.storage_service, "get_storage_service", lambda bucket: DummyStorage()
    )
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

    assert calls == {
        "defer": "media-2",
        "next_retry_at": fixed_now + timedelta(seconds=10),
    }


@pytest.mark.anyio
async def test_transcode_audio_asset_handles_m4a_input_and_generates_mp3(monkeypatch):
    calls: dict[str, object] = {}

    class DummySigned:
        url = "https://example.invalid/source"

    class DummyUpload:
        url = "https://example.invalid/upload"
        headers = {"content-type": "audio/mpeg"}

    class DummyStorage:
        bucket = "course-media"

        async def get_presigned_url(self, *args, **kwargs):
            calls["presign_args"] = args
            calls["presign_kwargs"] = kwargs
            return DummySigned()

        async def create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            calls["derived_path"] = path
            calls["derived_content_type"] = content_type
            calls["derived_upsert"] = upsert
            calls["derived_cache_seconds"] = cache_seconds
            return DummyUpload()

    async def fake_download_to_file(url, destination):
        calls["download_url"] = url
        calls["download_destination"] = destination
        destination.write_bytes(b"m4a-bytes")

    async def fake_consume_attempt():
        calls["attempt_consumed"] = True

    async def fake_run_ffmpeg_audio(input_path, output_path):
        calls["ffmpeg_input"] = input_path
        calls["ffmpeg_output"] = output_path
        output_path.write_bytes(b"mp3-bytes")

    async def fake_probe_duration(path):
        calls["probe_path"] = path
        return 42

    async def fake_upload_file(url, source, headers):
        calls["upload_url"] = url
        calls["upload_source"] = source
        calls["upload_headers"] = headers

    async def fake_mark_media_asset_ready_from_worker(**kwargs):
        calls["mark_ready"] = kwargs
        return True

    monkeypatch.setattr(
        worker.storage_service, "get_storage_service", lambda bucket: DummyStorage()
    )
    monkeypatch.setattr(worker, "_download_to_file", fake_download_to_file)
    monkeypatch.setattr(worker, "_run_ffmpeg_audio", fake_run_ffmpeg_audio)
    monkeypatch.setattr(worker, "_probe_duration", fake_probe_duration)
    monkeypatch.setattr(worker, "_upload_file", fake_upload_file)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_media_asset_ready_from_worker",
        fake_mark_media_asset_ready_from_worker,
    )

    asset = {
        "id": "media-m4a",
        "media_type": "audio",
        "purpose": "lesson_audio",
        "ingest_format": "m4a",
        "original_filename": "demo.m4a",
        "original_object_path": "media/source/audio/courses/course-1/lessons/lesson-1/demo.m4a",
        "storage_bucket": "course-media",
    }

    await worker._transcode_audio_asset(asset, fake_consume_attempt)

    assert calls["attempt_consumed"] is True
    assert calls["download_destination"].suffix == ".m4a"
    assert calls["ffmpeg_input"].suffix == ".m4a"
    assert calls["ffmpeg_output"].suffix == ".mp3"
    assert (
        calls["derived_path"]
        == "media/derived/audio/courses/course-1/lessons/lesson-1/demo.mp3"
    )
    assert calls["derived_content_type"] == "audio/mpeg"
    assert calls["upload_source"] == calls["ffmpeg_output"]
    assert calls["probe_path"] == calls["ffmpeg_output"]
    assert calls["mark_ready"] == {
        "media_id": "media-m4a",
        "streaming_object_path": "media/derived/audio/courses/course-1/lessons/lesson-1/demo.mp3",
        "streaming_format": "mp3",
        "duration_seconds": 42,
        "codec": "mp3",
        "streaming_storage_bucket": "course-media",
    }
