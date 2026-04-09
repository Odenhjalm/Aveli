from datetime import datetime, timedelta, timezone
import logging

import pytest

from app.services import media_transcode_worker as worker


@pytest.mark.anyio("asyncio")
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


@pytest.mark.anyio("asyncio")
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


@pytest.mark.anyio("asyncio")
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


@pytest.mark.anyio("asyncio")
async def test_transcode_cover_promotes_without_legacy_public_url(monkeypatch, caplog):
    calls: dict[str, object] = {}

    class DummySigned:
        url = "https://example.invalid/source"

    class DummyUpload:
        url = "https://example.invalid/upload"
        headers = {"content-type": "image/jpeg"}

    class DummyStorage:
        def __init__(self, bucket: str) -> None:
            self.bucket = bucket

        async def get_presigned_url(self, *args, **kwargs):
            return DummySigned()

        async def create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            calls["derived_path"] = path
            calls["derived_content_type"] = content_type
            return DummyUpload()

    async def fake_download_to_file(url, destination):
        calls["download_url"] = url
        destination.write_bytes(b"cover-source")

    async def fake_consume_attempt():
        calls["attempt_consumed"] = True

    async def fake_run_ffmpeg_cover(input_path, output_path):
        calls["ffmpeg_input"] = input_path
        calls["ffmpeg_output"] = output_path
        output_path.write_bytes(b"cover-derived")

    async def fake_upload_file(url, source, headers):
        calls["upload_url"] = url
        calls["upload_source"] = source
        calls["upload_headers"] = headers

    async def fake_verify_ready_contract(**kwargs):
        calls["verify"] = kwargs

    async def fake_mark_course_cover_ready_from_worker(**kwargs):
        calls["mark_ready"] = kwargs
        return {
            "updated": True,
            "cover_applied": True,
            "course_id": "course-1",
            "previous_cover_media_id": "old-media",
            "latest_cover_media_id": "media-cover",
        }

    async def fake_prune_course_cover_assets(*, course_id: str):
        calls["pruned_course_id"] = course_id

    public_storage = DummyStorage("public-media")
    source_storage = DummyStorage("course-media")
    monkeypatch.setattr(
        worker.storage_service,
        "get_storage_service",
        lambda bucket: public_storage if bucket == "public-media" else source_storage,
    )
    monkeypatch.setattr(worker, "_download_to_file", fake_download_to_file)
    monkeypatch.setattr(worker, "_run_ffmpeg_cover", fake_run_ffmpeg_cover)
    monkeypatch.setattr(worker, "_upload_file", fake_upload_file)
    monkeypatch.setattr(worker, "_verify_ready_contract", fake_verify_ready_contract)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_course_cover_ready_from_worker",
        fake_mark_course_cover_ready_from_worker,
    )
    monkeypatch.setattr(
        worker.media_cleanup,
        "prune_course_cover_assets",
        fake_prune_course_cover_assets,
    )

    asset = {
        "id": "media-cover",
        "course_id": "course-1",
        "media_type": "image",
        "purpose": "course_cover",
        "original_object_path": "media/source/cover/courses/course-1/cover.png",
        "storage_bucket": "course-media",
    }

    with caplog.at_level(logging.INFO):
        await worker._transcode_cover_asset(asset, fake_consume_attempt)

    assert calls["mark_ready"]["streaming_object_path"].endswith(".jpg")
    assert calls["mark_ready"]["streaming_format"] == "jpg"
    assert calls["mark_ready"]["codec"] == "jpeg"
    assert "public_url" not in calls["mark_ready"]
    assert calls["pruned_course_id"] == "course-1"
    assert "COURSE_COVER_PROMOTED" in caplog.text


@pytest.mark.anyio("asyncio")
async def test_transcode_cover_logs_when_ready_asset_not_promoted(
    monkeypatch, caplog
):
    class DummySigned:
        url = "https://example.invalid/source"

    class DummyUpload:
        url = "https://example.invalid/upload"
        headers = {"content-type": "image/jpeg"}

    class DummyStorage:
        def __init__(self, bucket: str) -> None:
            self.bucket = bucket

        async def get_presigned_url(self, *args, **kwargs):
            return DummySigned()

        async def create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            return DummyUpload()

    async def fake_download_to_file(url, destination):
        destination.write_bytes(b"cover-source")

    async def fake_consume_attempt():
        return None

    async def fake_run_ffmpeg_cover(input_path, output_path):
        output_path.write_bytes(b"cover-derived")

    async def fake_upload_file(url, source, headers):
        return None

    async def fake_verify_ready_contract(**kwargs):
        return None

    async def fake_mark_course_cover_ready_from_worker(**kwargs):
        return {
            "updated": True,
            "cover_applied": False,
            "course_id": "course-1",
            "previous_cover_media_id": "old-media",
            "latest_cover_media_id": "newer-media",
        }

    public_storage = DummyStorage("public-media")
    source_storage = DummyStorage("course-media")
    monkeypatch.setattr(
        worker.storage_service,
        "get_storage_service",
        lambda bucket: public_storage if bucket == "public-media" else source_storage,
    )
    monkeypatch.setattr(worker, "_download_to_file", fake_download_to_file)
    monkeypatch.setattr(worker, "_run_ffmpeg_cover", fake_run_ffmpeg_cover)
    monkeypatch.setattr(worker, "_upload_file", fake_upload_file)
    monkeypatch.setattr(worker, "_verify_ready_contract", fake_verify_ready_contract)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_course_cover_ready_from_worker",
        fake_mark_course_cover_ready_from_worker,
    )

    asset = {
        "id": "media-cover",
        "course_id": "course-1",
        "media_type": "image",
        "purpose": "course_cover",
        "original_object_path": "media/source/cover/courses/course-1/cover.png",
        "storage_bucket": "course-media",
    }

    with caplog.at_level(logging.WARNING):
        await worker._transcode_cover_asset(asset, fake_consume_attempt)

    assert "COURSE_COVER_READY_NOT_PROMOTED" in caplog.text
