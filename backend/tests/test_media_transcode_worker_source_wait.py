import asyncio
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
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
async def test_download_to_file_wraps_http_errors_and_uses_fail_fast_client(
    monkeypatch,
    tmp_path,
):
    captured: dict[str, object] = {}

    class FailingStream:
        async def __aenter__(self):
            raise httpx.ReadTimeout("read timed out")

        async def __aexit__(self, exc_type, exc, tb):
            return False

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"] = {"args": args, "kwargs": kwargs}

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        def stream(self, method, url):
            captured["request"] = {"method": method, "url": url}
            return FailingStream()

    monkeypatch.setattr(worker.httpx, "AsyncClient", DummyAsyncClient)

    destination = tmp_path / "source.wav"
    with pytest.raises(worker.storage_service.StorageServiceError) as exc_info:
        await worker._download_to_file(
            "https://example.invalid/source.wav?token=secret",
            destination,
        )

    assert isinstance(exc_info.value.__cause__, httpx.ReadTimeout)
    assert not destination.exists()
    assert captured["request"] == {
        "method": "GET",
        "url": "https://example.invalid/source.wav?token=secret",
    }
    timeout = captured["init"]["kwargs"]["timeout"]
    limits = captured["init"]["kwargs"]["limits"]
    assert isinstance(timeout, httpx.Timeout)
    assert timeout.connect == 5.0
    assert timeout.read == 5.0
    assert timeout.write == 5.0
    assert timeout.pool == 5.0
    assert isinstance(limits, httpx.Limits)
    assert limits.max_keepalive_connections == 0


@pytest.mark.anyio("asyncio")
async def test_download_to_file_fails_when_stream_stalls(monkeypatch, tmp_path):
    class HangingResponse:
        status_code = 200

        def raise_for_status(self):
            return None

        async def aiter_bytes(self, *, chunk_size):
            await asyncio.sleep(3600)
            yield b"never"

    class HangingStream:
        async def __aenter__(self):
            return HangingResponse()

        async def __aexit__(self, exc_type, exc, tb):
            return False

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        def stream(self, method, url):
            return HangingStream()

    monkeypatch.setattr(worker.httpx, "AsyncClient", DummyAsyncClient)
    monkeypatch.setattr(worker, "_DOWNLOAD_CHUNK_TIMEOUT_SECONDS", 0.01)

    with pytest.raises(worker.storage_service.StorageServiceError) as exc_info:
        await worker._download_to_file(
            "https://example.invalid/source.wav?token=secret",
            tmp_path / "source.wav",
        )

    assert "Timed out waiting for storage download bytes" in str(exc_info.value)
    assert isinstance(exc_info.value.__cause__, TimeoutError)


@pytest.mark.anyio("asyncio")
async def test_download_to_file_writes_non_empty_payload(monkeypatch, tmp_path):
    captured: dict[str, object] = {}

    class DummyResponse:
        status_code = 200

        def raise_for_status(self):
            return None

        async def aiter_bytes(self, *, chunk_size):
            captured["chunk_size"] = chunk_size
            yield b"abc"
            yield b"def"

    class DummyStream:
        async def __aenter__(self):
            return DummyResponse()

        async def __aexit__(self, exc_type, exc, tb):
            return False

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"] = {"args": args, "kwargs": kwargs}

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        def stream(self, method, url):
            captured["request"] = {"method": method, "url": url}
            return DummyStream()

    monkeypatch.setattr(worker.httpx, "AsyncClient", DummyAsyncClient)

    destination = tmp_path / "source.wav"
    await worker._download_to_file(
        "https://example.invalid/source.wav?token=secret",
        destination,
    )

    assert destination.read_bytes() == b"abcdef"
    assert captured["chunk_size"] == 1024 * 1024


@pytest.mark.anyio("asyncio")
async def test_worker_records_download_timeout_without_crashing(monkeypatch):
    fixed_now = datetime(2026, 1, 25, tzinfo=timezone.utc)
    monkeypatch.setattr(worker, "_now", lambda: fixed_now)

    calls: dict[str, object] = {}

    class DummySigned:
        url = "https://example.invalid/source.wav?token=secret"

    class DummyStorage:
        bucket = "course-media"

        async def get_presigned_url(self, *args, **kwargs):
            return DummySigned()

    async def fake_download_to_file(url, destination):
        raise worker.storage_service.StorageServiceError(
            "Timed out waiting for storage download bytes"
        )

    async def increment_processing_attempts(*, media_id: str) -> None:
        calls["increment"] = media_id

    async def mark_media_asset_failed(**kwargs) -> None:
        calls["failed"] = kwargs

    async def defer_media_asset_processing(*args, **kwargs) -> None:
        raise AssertionError("download errors must not use source-not-ready deferral")

    monkeypatch.setattr(
        worker.storage_service, "get_storage_service", lambda bucket: DummyStorage()
    )
    monkeypatch.setattr(worker, "_download_to_file", fake_download_to_file)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "increment_processing_attempts",
        increment_processing_attempts,
    )
    monkeypatch.setattr(
        worker.media_assets_repo, "mark_media_asset_failed", mark_media_asset_failed
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "defer_media_asset_processing",
        defer_media_asset_processing,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "compute_backoff",
        lambda attempts, max_seconds: timedelta(seconds=30),
    )

    await worker._process_asset(
        {
            "id": "media-timeout",
            "processing_attempts": 0,
            "media_type": "audio",
            "purpose": "lesson_audio",
            "original_object_path": "media/source/audio/lesson/foo.wav",
            "storage_bucket": "course-media",
        }
    )

    assert calls["increment"] == "media-timeout"
    assert calls["failed"] == {
        "media_id": "media-timeout",
        "error_message": "Timed out waiting for storage download bytes",
        "next_retry_at": fixed_now + timedelta(seconds=30),
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

        async def inspect_object(self, path, *, ttl):
            calls["inspect_path"] = path
            calls["inspect_ttl"] = ttl
            return worker.storage_service.StorageObjectMetadata(
                path=path,
                content_type="audio/mpeg",
                size_bytes=9,
            )

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
        "playback_object_path": "media/derived/audio/courses/course-1/lessons/lesson-1/demo.mp3",
        "playback_format": "mp3",
        "duration_seconds": 42,
        "codec": "mp3",
        "playback_storage_bucket": "course-media",
    }


@pytest.mark.anyio("asyncio")
@pytest.mark.parametrize(
    (
        "media_type",
        "source_path",
        "source_content_type",
        "expected_source_bucket",
        "expected_output_path",
        "expected_format",
        "expected_codec",
        "expected_duration",
    ),
    [
        (
            "image",
            "lessons/lesson-1/images/demo.jpeg",
            "image/jpeg",
            "public-media",
            "media/derived/lesson-media/image/lessons/lesson-1/images/demo.jpg",
            "jpg",
            "jpeg",
            None,
        ),
        (
            "video",
            "courses/course-1/lessons/lesson-1/video/demo.mp4",
            "video/mp4",
            "course-media",
            "media/derived/lesson-media/video/courses/course-1/lessons/lesson-1/video/demo.mp4",
            "mp4",
            "mp4",
            33,
        ),
        (
            "document",
            "courses/course-1/lessons/lesson-1/documents/guide.pdf",
            "application/pdf",
            "course-media",
            "media/derived/lesson-media/document/courses/course-1/lessons/lesson-1/documents/guide.pdf",
            "pdf",
            "pdf",
            None,
        ),
    ],
)
async def test_lesson_media_passthrough_marks_scoped_types_ready(
    monkeypatch,
    media_type,
    source_path,
    source_content_type,
    expected_source_bucket,
    expected_output_path,
    expected_format,
    expected_codec,
    expected_duration,
):
    calls: dict[str, object] = {}

    class DummySigned:
        url = "https://example.invalid/source"

    class DummyUpload:
        url = "https://example.invalid/upload"
        headers = {"content-type": source_content_type}

    class DummyStorage:
        def __init__(self, bucket: str):
            self.bucket = bucket

        async def get_presigned_url(self, path, **kwargs):
            calls.setdefault("presigned", []).append((self.bucket, path, kwargs))
            return DummySigned()

        async def create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            calls["upload_path"] = path
            calls["upload_bucket"] = self.bucket
            calls["upload_content_type"] = content_type
            calls["upload_upsert"] = upsert
            calls["upload_cache_seconds"] = cache_seconds
            return DummyUpload()

        async def inspect_object(self, path, *, ttl):
            calls.setdefault("inspected", []).append((self.bucket, path, ttl))
            if self.bucket == expected_source_bucket and path == source_path:
                return worker.storage_service.StorageObjectMetadata(
                    path=path,
                    content_type=source_content_type,
                    size_bytes=12,
                )
            if self.bucket == "course-media" and path == expected_output_path:
                return worker.storage_service.StorageObjectMetadata(
                    path=path,
                    content_type=source_content_type,
                    size_bytes=12,
                )
            raise worker.storage_service.StorageObjectNotFoundError("missing")

        async def delete_object(self, path):
            calls["deleted_path"] = path

    def fake_get_storage_service(bucket):
        calls.setdefault("storage_buckets", []).append(bucket)
        return DummyStorage(bucket)

    async def fake_download_to_file(url, destination):
        calls["download_url"] = url
        calls["download_destination"] = destination
        destination.write_bytes(b"source-bytes")

    async def fake_upload_file(url, source, headers):
        calls["uploaded_url"] = url
        calls["uploaded_source"] = source
        calls["uploaded_headers"] = headers

    async def fake_probe_duration(path):
        calls["probe_path"] = path
        return expected_duration

    async def fake_mark_media_asset_ready_from_worker(**kwargs):
        calls["mark_ready"] = kwargs
        return {"id": kwargs["media_id"], "state": "ready"}

    async def fake_consume_attempt():
        calls["attempt_consumed"] = True

    monkeypatch.setattr(
        worker.storage_service,
        "get_storage_service",
        fake_get_storage_service,
    )
    monkeypatch.setattr(worker, "_download_to_file", fake_download_to_file)
    monkeypatch.setattr(worker, "_upload_file", fake_upload_file)
    monkeypatch.setattr(worker, "_probe_duration", fake_probe_duration)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_media_asset_ready_from_worker",
        fake_mark_media_asset_ready_from_worker,
    )

    await worker._transcode_lesson_passthrough_asset(
        {
            "id": f"{media_type}-asset-1",
            "media_type": media_type,
            "purpose": "lesson_media",
            "original_object_path": source_path,
        },
        fake_consume_attempt,
    )

    assert calls["storage_buckets"] == [expected_source_bucket, "course-media"]
    assert calls["attempt_consumed"] is True
    assert calls["upload_bucket"] == "course-media"
    assert calls["upload_path"] == expected_output_path
    assert calls["upload_content_type"] == source_content_type
    assert calls["upload_upsert"] is True
    assert calls["uploaded_source"].name == f"output.{expected_format}"
    if media_type == "video":
        assert calls["probe_path"] == calls["uploaded_source"]
    else:
        assert "probe_path" not in calls
    assert calls["mark_ready"] == {
        "media_id": f"{media_type}-asset-1",
        "playback_object_path": expected_output_path,
        "playback_format": expected_format,
        "duration_seconds": expected_duration,
        "codec": expected_codec,
        "playback_storage_bucket": "course-media",
    }


@pytest.mark.anyio("asyncio")
@pytest.mark.parametrize(
    ("media_type", "source_path", "source_content_type", "expected_error"),
    [
        (
            "image",
            "lessons/lesson-1/images/demo.webp",
            "image/webp",
            "Unsupported lesson image passthrough format",
        ),
        (
            "video",
            "courses/course-1/lessons/lesson-1/video/demo.webm",
            "video/webm",
            "Unsupported lesson video passthrough format",
        ),
        (
            "document",
            "courses/course-1/lessons/lesson-1/documents/guide.txt",
            "text/plain",
            "Unsupported lesson document passthrough format",
        ),
    ],
)
async def test_lesson_media_passthrough_failures_mark_failed_closed(
    monkeypatch,
    media_type,
    source_path,
    source_content_type,
    expected_error,
):
    fixed_now = datetime(2026, 1, 25, tzinfo=timezone.utc)
    calls: dict[str, object] = {}
    source_bucket = "public-media" if media_type == "image" else "course-media"

    class DummyStorage:
        def __init__(self, bucket: str):
            self.bucket = bucket

        async def inspect_object(self, path, *, ttl):
            assert self.bucket == source_bucket
            assert path == source_path
            return worker.storage_service.StorageObjectMetadata(
                path=path,
                content_type=source_content_type,
                size_bytes=12,
            )

    async def fake_increment_processing_attempts(*, media_id: str):
        calls["increment"] = media_id

    async def fake_mark_media_asset_failed(**kwargs):
        calls["failed"] = kwargs

    async def fail_mark_ready(**kwargs):
        raise AssertionError("unsupported passthrough must not mark ready")

    monkeypatch.setattr(worker, "_now", lambda: fixed_now)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "compute_backoff",
        lambda attempts, max_seconds: timedelta(seconds=30),
    )
    monkeypatch.setattr(
        worker.storage_service,
        "get_storage_service",
        lambda bucket: DummyStorage(bucket),
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "increment_processing_attempts",
        fake_increment_processing_attempts,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_media_asset_failed",
        fake_mark_media_asset_failed,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_media_asset_ready_from_worker",
        fail_mark_ready,
    )

    await worker._process_asset(
        {
            "id": f"{media_type}-asset-unsupported",
            "processing_attempts": 0,
            "media_type": media_type,
            "purpose": "lesson_media",
            "original_object_path": source_path,
        }
    )

    assert calls["increment"] == f"{media_type}-asset-unsupported"
    assert calls["failed"] == {
        "media_id": f"{media_type}-asset-unsupported",
        "error_message": expected_error,
        "next_retry_at": fixed_now + timedelta(seconds=30),
    }


def test_worker_queue_claim_includes_lesson_image_video_document() -> None:
    source = (
        Path(__file__).resolve().parents[1] / "app/repositories/media_assets.py"
    ).read_text(encoding="utf-8")

    assert "'lesson_media'::app.media_purpose" in source
    assert "'image'::app.media_type" in source
    assert "'video'::app.media_type" in source
    assert "'document'::app.media_type" in source


@pytest.mark.anyio("asyncio")
async def test_derived_upload_falls_back_to_local_storage_in_local_mode(
    monkeypatch,
    tmp_path,
) -> None:
    monkeypatch.setattr(worker.settings, "mcp_mode", "local")
    monkeypatch.setattr(worker.settings, "media_root", str(tmp_path))
    source = tmp_path / "source.mp3"
    source.write_bytes(b"mp3-bytes")

    class DummyStorage:
        bucket = "course-media"

        async def create_upload_url(self, *args, **kwargs):
            raise worker.storage_service.StorageServiceError("upload signing failed")

    await worker._upload_derived_file(
        storage=DummyStorage(),
        object_path="media/derived/audio/demo.mp3",
        source=source,
        content_type="audio/mpeg",
        upsert=True,
        cache_seconds=3600,
    )

    target = tmp_path / "course-media" / "media" / "derived" / "audio" / "demo.mp3"
    assert target.read_bytes() == b"mp3-bytes"
    assert worker._local_storage_object_exists(
        "course-media", "media/derived/audio/demo.mp3"
    )


def test_worker_never_assigns_course_cover_identity() -> None:
    source = Path(worker.__file__).read_text(encoding="utf-8")

    assert "cover_media_id" not in source
    assert "courses_repo" not in source
    assert "update_course(" not in source
    assert "set_course_cover" not in source


@pytest.mark.anyio("asyncio")
async def test_ready_verification_rejects_missing_storage_proof() -> None:
    class DummyStorage:
        bucket = "public-media"

        async def inspect_object(self, path, *, ttl):
            raise worker.storage_service.StorageObjectNotFoundError("missing")

    with pytest.raises(RuntimeError, match="playback object is missing"):
        await worker._verify_ready_contract(
            asset={"media_type": "image", "purpose": "course_cover"},
            playback_storage=DummyStorage(),
            playback_object_path="media/derived/cover/courses/course-1/source.jpg",
            playback_format="jpg",
            playback_content_type="image/jpeg",
            duration_seconds=None,
        )


@pytest.mark.anyio("asyncio")
async def test_course_cover_image_transcode_marks_ready_with_jpg_format(
    monkeypatch,
) -> None:
    calls: dict[str, object] = {}

    class DummySigned:
        url = "https://example.invalid/source"

    class DummyUpload:
        url = "https://example.invalid/upload"
        headers = {"content-type": "image/jpeg"}

    class DummyStorage:
        def __init__(self, bucket: str):
            self.bucket = bucket

        async def get_presigned_url(self, path, **kwargs):
            calls.setdefault("presigned_paths", []).append(path)
            calls.setdefault("presigned_kwargs", []).append(kwargs)
            return DummySigned()

        async def create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            calls["upload_path"] = path
            calls["upload_content_type"] = content_type
            calls["upload_upsert"] = upsert
            calls["upload_cache_seconds"] = cache_seconds
            return DummyUpload()

        async def inspect_object(self, path, *, ttl):
            calls.setdefault("inspect_paths", []).append(path)
            calls.setdefault("inspect_ttls", []).append(ttl)
            return worker.storage_service.StorageObjectMetadata(
                path=path,
                content_type="image/jpeg",
                size_bytes=8,
            )

        async def delete_object(self, path):
            calls["deleted_path"] = path

    def fake_get_storage_service(bucket):
        calls.setdefault("storage_buckets", []).append(bucket)
        return DummyStorage(bucket)

    async def fake_download_to_file(url, destination):
        calls["download_url"] = url
        calls["download_destination"] = destination
        destination.write_bytes(b"png-bytes")

    async def fake_consume_attempt():
        calls["attempt_consumed"] = True

    async def fake_run_ffmpeg_cover(input_path, output_path):
        calls["ffmpeg_input"] = input_path
        calls["ffmpeg_output"] = output_path
        output_path.write_bytes(b"\xff\xd8jpeg\xff\xd9")

    async def fake_upload_file(url, source, headers):
        calls["uploaded_url"] = url
        calls["uploaded_source"] = source
        calls["uploaded_headers"] = headers

    async def fake_mark_course_cover_ready_from_worker(**kwargs):
        calls["mark_ready"] = kwargs
        return {"updated": True}

    monkeypatch.setattr(
        worker.storage_service,
        "get_storage_service",
        fake_get_storage_service,
    )
    monkeypatch.setattr(worker, "_download_to_file", fake_download_to_file)
    monkeypatch.setattr(worker, "_run_ffmpeg_cover", fake_run_ffmpeg_cover)
    monkeypatch.setattr(worker, "_upload_file", fake_upload_file)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_course_cover_ready_from_worker",
        fake_mark_course_cover_ready_from_worker,
    )

    await worker._transcode_cover_asset(
        {
            "id": "course-cover-1",
            "media_type": "image",
            "purpose": "course_cover",
            "original_object_path": "media/source/cover/courses/course-1/source.png",
        },
        fake_consume_attempt,
    )

    assert calls["storage_buckets"] == [
        worker.settings.media_source_bucket,
        worker.settings.media_public_bucket,
    ]
    assert calls["attempt_consumed"] is True
    assert calls["upload_path"] == "media/derived/cover/courses/course-1/source.jpg"
    assert calls["upload_content_type"] == "image/jpeg"
    assert calls["uploaded_source"] == calls["ffmpeg_output"]
    assert calls["inspect_paths"] == [
        "media/derived/cover/courses/course-1/source.jpg",
        "media/derived/cover/courses/course-1/source.jpg",
    ]
    assert calls["mark_ready"] == {
        "media_id": "course-cover-1",
        "playback_object_path": "media/derived/cover/courses/course-1/source.jpg",
        "playback_storage_bucket": worker.settings.media_public_bucket,
        "playback_format": "jpg",
        "codec": "jpeg",
    }


def test_profile_media_output_path_preserves_subject_scope() -> None:
    assert (
        worker._derive_profile_media_output_path(
            "media/source/profile-avatar/user-1/avatar.png",
            "jpg",
        )
        == "media/derived/profile-avatar/user-1/avatar.jpg"
    )


@pytest.mark.anyio("asyncio")
async def test_transcode_asset_dispatches_profile_media_image(monkeypatch) -> None:
    calls: dict[str, object] = {}

    async def fake_transcode_profile_media_image_asset(asset, consume_attempt):
        calls["asset"] = asset
        calls["consume_attempt"] = consume_attempt

    async def fake_consume_attempt():
        calls["attempt_consumed"] = True

    monkeypatch.setattr(
        worker,
        "_transcode_profile_media_image_asset",
        fake_transcode_profile_media_image_asset,
    )

    asset = {
        "id": "profile-media-1",
        "media_type": "image",
        "purpose": "profile_media",
    }

    await worker._transcode_asset(asset, fake_consume_attempt)

    assert calls["asset"] == asset
    assert calls["consume_attempt"] == fake_consume_attempt


@pytest.mark.anyio("asyncio")
async def test_profile_media_image_transcode_marks_ready_through_worker(
    monkeypatch,
) -> None:
    calls: dict[str, object] = {}

    class DummySigned:
        url = "https://example.invalid/source"

    class DummyUpload:
        url = "https://example.invalid/upload"
        headers = {"content-type": "image/jpeg"}

    class DummyStorage:
        def __init__(self, bucket: str):
            self.bucket = bucket

        async def get_presigned_url(self, path, **kwargs):
            calls.setdefault("presigned_paths", []).append(path)
            calls.setdefault("presigned_kwargs", []).append(kwargs)
            return DummySigned()

        async def create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            calls["upload_path"] = path
            calls["upload_content_type"] = content_type
            calls["upload_upsert"] = upsert
            calls["upload_cache_seconds"] = cache_seconds
            return DummyUpload()

        async def inspect_object(self, path, *, ttl):
            calls.setdefault("inspect_paths", []).append(path)
            calls.setdefault("inspect_ttls", []).append(ttl)
            return worker.storage_service.StorageObjectMetadata(
                path=path,
                content_type="image/jpeg",
                size_bytes=8,
            )

        async def delete_object(self, path):
            calls["deleted_path"] = path

    def fake_get_storage_service(bucket):
        calls.setdefault("storage_buckets", []).append(bucket)
        return DummyStorage(bucket)

    async def fake_download_to_file(url, destination):
        calls["download_url"] = url
        calls["download_destination"] = destination
        destination.write_bytes(b"profile-image-bytes")

    async def fake_consume_attempt():
        calls["attempt_consumed"] = True

    async def fake_run_ffmpeg_cover(input_path, output_path):
        calls["ffmpeg_input"] = input_path
        calls["ffmpeg_output"] = output_path
        output_path.write_bytes(b"jpeg-bytes")

    async def fake_upload_file(url, source, headers):
        calls["uploaded_url"] = url
        calls["uploaded_source"] = source
        calls["uploaded_headers"] = headers

    async def fake_mark_media_asset_ready_from_worker(**kwargs):
        calls["mark_ready"] = kwargs
        return {"id": kwargs["media_id"], "state": "ready"}

    monkeypatch.setattr(
        worker.storage_service,
        "get_storage_service",
        fake_get_storage_service,
    )
    monkeypatch.setattr(worker, "_download_to_file", fake_download_to_file)
    monkeypatch.setattr(worker, "_run_ffmpeg_cover", fake_run_ffmpeg_cover)
    monkeypatch.setattr(worker, "_upload_file", fake_upload_file)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "mark_media_asset_ready_from_worker",
        fake_mark_media_asset_ready_from_worker,
    )

    await worker._transcode_profile_media_image_asset(
        {
            "id": "profile-media-1",
            "media_type": "image",
            "purpose": "profile_media",
            "original_object_path": "media/source/profile-avatar/user-1/avatar.png",
        },
        fake_consume_attempt,
    )

    assert calls["storage_buckets"] == [
        worker.settings.media_profile_bucket,
        worker.settings.media_public_bucket,
    ]
    assert calls["attempt_consumed"] is True
    assert calls["upload_path"] == "media/derived/profile-avatar/user-1/avatar.jpg"
    assert calls["upload_content_type"] == "image/jpeg"
    assert calls["uploaded_source"] == calls["ffmpeg_output"]
    assert calls["mark_ready"] == {
        "media_id": "profile-media-1",
        "playback_object_path": "media/derived/profile-avatar/user-1/avatar.jpg",
        "playback_storage_bucket": worker.settings.media_public_bucket,
        "playback_format": "jpg",
        "codec": "jpeg",
    }
