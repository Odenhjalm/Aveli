import pytest
import httpx
from urllib.parse import quote

from app.services import storage_service as storage_module
from app.services.storage_service import (
    StorageObjectNotFoundError,
    StorageService,
    StorageServiceError,
)
from app.utils.http_headers import build_content_disposition


def _assert_fail_fast_storage_client(init: dict[str, object]) -> None:
    timeout = init["kwargs"]["timeout"]
    limits = init["kwargs"]["limits"]
    assert isinstance(timeout, httpx.Timeout)
    assert timeout.connect == 5.0
    assert timeout.read == 10.0
    assert isinstance(limits, httpx.Limits)
    assert limits.max_keepalive_connections == 0


def _assert_upload_storage_client(init: dict[str, object]) -> None:
    timeout = init["kwargs"]["timeout"]
    limits = init["kwargs"]["limits"]
    assert isinstance(timeout, httpx.Timeout)
    assert timeout.connect == 5.0
    assert timeout.read == 900.0
    assert timeout.write == 900.0
    assert timeout.pool == 5.0
    assert isinstance(limits, httpx.Limits)
    assert limits.max_keepalive_connections == 0


@pytest.mark.anyio("asyncio")
async def test_get_presigned_url_sets_content_disposition(monkeypatch):
    captured: dict[str, dict[str, object]] = {}

    class DummyResponse:
        status_code = 200

        def json(self):
            return {
                "signedURL": "/storage/v1/object/sign/lesson_media/course/foo.mp4?t=token",
            }

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"] = {"args": args, "kwargs": kwargs}

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            captured["request"] = {"url": url, "json": json, "headers": headers}
            return DummyResponse()

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    result = await service.get_presigned_url(
        "course/foo.mp4",
        ttl=120,
        filename="lektion 1.mp4",
    )

    assert "download=lektion%201.mp4" in result.url
    assert result.expires_in == 120
    assert result.headers["Content-Disposition"] == build_content_disposition(
        "lektion 1.mp4"
    )

    request = captured["request"]
    assert request["url"] == (
        "https://example.supabase.co/storage/v1/object/sign/lesson_media/course/foo.mp4"
    )
    assert request["json"] == {"expiresIn": 120}
    assert request["headers"]["apikey"] == "service-role-key"
    assert request["headers"]["Authorization"] == "Bearer service-role-key"
    _assert_fail_fast_storage_client(captured["init"])


@pytest.mark.anyio("asyncio")
async def test_get_presigned_url_object_not_found_raises_typed_error(monkeypatch):
    class DummyResponse:
        status_code = 400

        def json(self):
            return {
                "error": "not_found",
                "message": "Object not found",
                "statusCode": "404",
            }

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            return DummyResponse()

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    with pytest.raises(StorageObjectNotFoundError):
        await service.get_presigned_url(
            "course/missing.wav",
            ttl=120,
            download=False,
        )


@pytest.mark.anyio("asyncio")
async def test_get_presigned_url_wraps_http_errors(monkeypatch):
    captured: dict[str, dict[str, object]] = {}

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"] = {"args": args, "kwargs": kwargs}

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            raise httpx.ConnectTimeout("connect timed out")

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    with pytest.raises(StorageServiceError) as exc_info:
        await service.get_presigned_url(
            "course/foo.mp4",
            ttl=120,
            download=False,
        )

    assert isinstance(exc_info.value.__cause__, httpx.ConnectTimeout)
    _assert_fail_fast_storage_client(captured["init"])


@pytest.mark.anyio("asyncio")
async def test_create_upload_url_returns_put_headers(monkeypatch):
    captured: dict[str, dict[str, object]] = {}

    class DummyResponse:
        status_code = 200

        def json(self):
            return {
                "url": "/storage/v1/object/upload/sign/lesson_media/course/foo.mp4?token=abc"
            }

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"] = {"args": args, "kwargs": kwargs}

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            captured["request"] = {"url": url, "json": json, "headers": headers}
            return DummyResponse()

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    result = await service.create_upload_url(
        "course/foo.mp4",
        content_type="video/mp4",
        upsert=True,
        cache_seconds=300,
    )

    assert result.url == (
        "https://example.supabase.co/storage/v1/object/upload/sign/"
        "lesson_media/course/foo.mp4?token=abc"
    )
    assert result.headers["x-upsert"] == "true"
    assert result.headers["content-type"] == "video/mp4"
    assert result.headers["cache-control"] == "max-age=300"
    assert result.expires_in == 7200
    assert result.path == "course/foo.mp4"

    request = captured["request"]
    assert request["headers"]["x-upsert"] == "true"
    _assert_fail_fast_storage_client(captured["init"])


@pytest.mark.anyio("asyncio")
async def test_upload_object_uses_extended_timeout_and_logs_success(
    monkeypatch, caplog
):
    captured: dict[str, list[dict[str, object]] | dict[str, object]] = {
        "init": []
    }

    class SignResponse:
        status_code = 200

        def json(self):
            return {
                "url": "/storage/v1/object/upload/sign/lesson_media/course/audio.wav?token=abc"
            }

    class UploadResponse:
        status_code = 200

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"].append({"args": args, "kwargs": kwargs})

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            captured["sign"] = {"url": url, "json": json, "headers": headers}
            return SignResponse()

        async def put(self, url, headers, content):
            captured["upload"] = {
                "url": url,
                "headers": headers,
                "content": content,
            }
            return UploadResponse()

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    caplog.set_level("INFO", logger=storage_module.logger.name)
    result = await service.upload_object(
        "course/audio.wav",
        content=b"wav",
        content_type="audio/wav",
        content_length=3,
        media_asset_id="media-1",
    )

    assert result.path == "course/audio.wav"
    init_calls = captured["init"]
    assert len(init_calls) == 2
    _assert_fail_fast_storage_client(init_calls[0])
    _assert_upload_storage_client(init_calls[1])
    assert captured["upload"]["headers"]["content-type"] == "audio/wav"
    assert "token=abc" not in caplog.text

    success_records = [
        record
        for record in caplog.records
        if record.getMessage().startswith("SUPABASE_STORAGE_UPLOAD_RESULT")
    ]
    assert len(success_records) == 1
    record = success_records[0]
    assert record.media_asset_id == "media-1"
    assert record.bucket == "lesson_media"
    assert record.object_path == "course/audio.wav"
    assert record.content_length == 3
    assert record.content_type == "audio/wav"
    assert record.result == "success"
    assert record.error_class is None
    assert isinstance(record.elapsed_ms, int)


@pytest.mark.anyio("asyncio")
async def test_upload_object_timeout_logs_and_wraps(monkeypatch, caplog):
    captured: dict[str, list[dict[str, object]]] = {"init": []}

    class SignResponse:
        status_code = 200

        def json(self):
            return {
                "url": "/storage/v1/object/upload/sign/lesson_media/course/audio.wav?token=abc"
            }

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            captured["init"].append({"args": args, "kwargs": kwargs})

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            return SignResponse()

        async def put(self, url, headers, content):
            raise httpx.WriteTimeout("upload too slow")

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    caplog.set_level("WARNING", logger=storage_module.logger.name)
    with pytest.raises(StorageServiceError) as exc_info:
        await service.upload_object(
            "course/audio.wav",
            content=b"wav",
            content_type="audio/wav",
            content_length=3,
            media_asset_id="media-1",
        )

    assert isinstance(exc_info.value.__cause__, httpx.WriteTimeout)
    init_calls = captured["init"]
    assert len(init_calls) == 2
    _assert_fail_fast_storage_client(init_calls[0])
    _assert_upload_storage_client(init_calls[1])
    assert "token=abc" not in caplog.text

    timeout_records = [
        record
        for record in caplog.records
        if record.getMessage().startswith("SUPABASE_STORAGE_UPLOAD_RESULT")
    ]
    assert len(timeout_records) == 1
    record = timeout_records[0]
    assert record.media_asset_id == "media-1"
    assert record.bucket == "lesson_media"
    assert record.object_path == "course/audio.wav"
    assert record.content_length == 3
    assert record.content_type == "audio/wav"
    assert record.result == "timeout"
    assert record.error_class == "WriteTimeout"
    assert isinstance(record.elapsed_ms, int)


def test_canonical_upload_bucket_uses_profile_media_bucket_for_profile_assets():
    assert (
        storage_module.canonical_upload_bucket_for_media_asset(
            {"purpose": "profile_media", "media_type": "image"}
        )
        == storage_module.settings.media_profile_bucket
    )


def test_canonical_upload_bucket_preserves_existing_course_media_fallbacks():
    assert (
        storage_module.canonical_upload_bucket_for_media_asset(
            {"purpose": "course_cover", "media_type": "image"}
        )
        == storage_module.settings.media_source_bucket
    )
    assert (
        storage_module.canonical_upload_bucket_for_media_asset(
            {"purpose": "lesson_media", "media_type": "audio"}
        )
        == storage_module.settings.media_source_bucket
    )


def test_canonical_upload_bucket_preserves_public_lesson_image_mapping():
    assert (
        storage_module.canonical_upload_bucket_for_media_asset(
            {"purpose": "lesson_media", "media_type": "image"}
        )
        == storage_module.settings.media_public_bucket
    )


@pytest.mark.anyio("asyncio")
@pytest.mark.parametrize(
    "path",
    [
        "folder/space name.png",
        "folder/question?.png",
        "folder/hash#.png",
        "folder/unicodé.png",
        "folder/mix # ? /unicodé file.png",
    ],
)
async def test_get_presigned_url_quotes_storage_path_segments(monkeypatch, path):
    captured: dict[str, object] = {}

    class DummyResponse:
        status_code = 200

        def json(self):
            return {"signedURL": "/storage/v1/object/sign/lesson_media/demo?t=token"}

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            captured["url"] = url
            return DummyResponse()

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    await service.get_presigned_url(path, ttl=120, download=False)

    assert captured["url"] == (
        "https://example.supabase.co/storage/v1/object/sign/lesson_media/"
        f"{quote(path, safe='/')}"
    )


@pytest.mark.anyio("asyncio")
@pytest.mark.parametrize(
    "path",
    [
        "folder/space name.png",
        "folder/question?.png",
        "folder/hash#.png",
        "folder/unicodé.png",
        "folder/mix # ? /unicodé file.png",
    ],
)
async def test_create_upload_url_quotes_storage_path_segments(monkeypatch, path):
    captured: dict[str, object] = {}

    class DummyResponse:
        status_code = 200

        def json(self):
            return {"url": "/storage/v1/object/upload/sign/lesson_media/demo?token=abc"}

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, url, json, headers):
            captured["url"] = url
            return DummyResponse()

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    await service.create_upload_url(path, content_type="image/png")

    assert captured["url"] == (
        "https://example.supabase.co/storage/v1/object/upload/sign/lesson_media/"
        f"{quote(path, safe='/')}"
    )


@pytest.mark.anyio("asyncio")
@pytest.mark.parametrize(
    "path",
    [
        "folder/space name.png",
        "folder/question?.png",
        "folder/hash#.png",
        "folder/unicodé.png",
        "folder/mix # ? /unicodé file.png",
    ],
)
async def test_delete_object_quotes_storage_path_segments(monkeypatch, path):
    captured: dict[str, object] = {}

    class DummyResponse:
        status_code = 200

    class DummyAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def delete(self, url, headers):
            captured["url"] = url
            return DummyResponse()

    monkeypatch.setattr(storage_module.httpx, "AsyncClient", DummyAsyncClient)

    service = StorageService(
        bucket="lesson_media",
        supabase_url="https://example.supabase.co",
        service_role_key="service-role-key",
    )

    deleted = await service.delete_object(path)

    assert deleted is True
    assert captured["url"] == (
        "https://example.supabase.co/storage/v1/object/lesson_media/"
        f"{quote(path, safe='/')}"
    )
