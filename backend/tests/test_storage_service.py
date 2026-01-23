import pytest

from app.services import storage_service as storage_module
from app.services.storage_service import StorageObjectNotFoundError, StorageService
from app.utils.http_headers import build_content_disposition


@pytest.mark.anyio
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


@pytest.mark.anyio
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


@pytest.mark.anyio
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
