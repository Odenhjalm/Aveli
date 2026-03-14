import pytest
from httpx import ASGITransport, AsyncClient

from app import permissions
from app.main import app
from app.routes import upload as upload_routes
from app.services.storage_service import PresignedUpload


pytestmark = pytest.mark.anyio("asyncio")


async def test_lesson_image_upload_creates_media_asset_without_media_object(
    monkeypatch,
):
    recorded: dict[str, dict] = {}
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": "teacher-1"}

    async def fake_lesson_course_ids(lesson_id: str):
        assert lesson_id == "lesson-1"
        return None, "course-1"

    async def fake_is_course_owner(owner_id: str, course_id: str):
        assert owner_id == "teacher-1"
        assert course_id == "course-1"
        return True

    async def fake_create_upload_url(
        path: str,
        *,
        content_type: str | None = None,
        upsert: bool = False,
        cache_seconds: int | None = None,
    ) -> PresignedUpload:
        recorded["upload"] = {
            "path": path,
            "content_type": content_type,
            "upsert": upsert,
            "cache_seconds": cache_seconds,
        }
        return PresignedUpload(
            url="https://storage.test/upload",
            headers={"content-type": content_type or "application/octet-stream"},
            path=path,
            expires_in=7200,
        )

    async def fake_create_ready_lesson_media_asset(**kwargs):
        recorded["asset"] = dict(kwargs)
        return {"id": "asset-1"}

    async def fake_add_lesson_media_entry_with_position_retry(**kwargs):
        recorded["lesson_media"] = dict(kwargs)
        return {
            "id": "lesson-media-1",
            "lesson_id": kwargs["lesson_id"],
            "kind": kwargs["kind"],
            "storage_path": kwargs["storage_path"],
            "storage_bucket": kwargs["storage_bucket"],
            "media_id": kwargs["media_id"],
            "media_asset_id": kwargs["media_asset_id"],
            "position": 1,
            "content_type": "image/png",
            "byte_size": 9,
            "original_name": "diagram.png",
        }

    async def fake_delete_media_asset(_media_id: str) -> None:
        raise AssertionError("media asset cleanup should not run on successful upload")

    class _FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            recorded["httpx_client"] = {"timeout": kwargs.get("timeout")}

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def put(self, url: str, *, headers: dict[str, str], content: bytes):
            recorded["put"] = {"url": url, "headers": dict(headers), "content": content}

            class _Response:
                status_code = 200

            return _Response()

    monkeypatch.setattr(
        upload_routes.courses_service,
        "lesson_course_ids",
        fake_lesson_course_ids,
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes.models,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes.storage_service.public_storage_service,
        "_supabase_url",
        "https://storage.test",
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes.storage_service.public_storage_service,
        "_service_role_key",
        "service-role",
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes.storage_service.public_storage_service,
        "create_upload_url",
        fake_create_upload_url,
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes,
        "_create_ready_lesson_media_asset",
        fake_create_ready_lesson_media_asset,
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes.models,
        "add_lesson_media_entry_with_position_retry",
        fake_add_lesson_media_entry_with_position_retry,
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes.media_assets_repo,
        "delete_media_asset",
        fake_delete_media_asset,
        raising=True,
    )
    monkeypatch.setattr(
        upload_routes.media_signer,
        "attach_media_links",
        lambda row, purpose="editor_preview": row,
        raising=True,
    )
    monkeypatch.setattr(upload_routes.httpx, "AsyncClient", _FakeAsyncClient, raising=True)

    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            response = await client.post(
                "/api/upload/lesson-image",
                data={"lesson_id": "lesson-1", "course_id": "course-1"},
                files={"file": ("diagram.png", b"png-bytes", "image/png")},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200, response.text
    payload = response.json()["media"]
    assert payload["media_asset_id"] == "asset-1"
    assert payload["media_id"] is None
    assert payload["storage_bucket"] == "public-media"
    assert payload["storage_path"].startswith("lessons/lesson-1/images/")
    assert payload["preferredUrl"].startswith(
        "https://storage.test/storage/v1/object/public/public-media/lessons/lesson-1/images/"
    )
    assert payload["url"] == payload["preferredUrl"]

    assert recorded["upload"]["path"].startswith("lessons/lesson-1/images/")
    assert recorded["upload"]["content_type"] == "image/png"
    assert recorded["put"]["url"] == "https://storage.test/upload"
    assert recorded["put"]["headers"]["content-type"] == "image/png"
    assert recorded["put"]["content"] == b"png-bytes"

    assert recorded["asset"]["kind"] == "image"
    assert recorded["asset"]["course_id"] == "course-1"
    assert recorded["asset"]["storage_bucket"] == "public-media"
    assert recorded["asset"]["storage_path"].startswith("lessons/lesson-1/images/")

    assert recorded["lesson_media"]["media_asset_id"] == "asset-1"
    assert recorded["lesson_media"]["media_id"] is None
    assert recorded["lesson_media"]["storage_bucket"] == "public-media"
    assert recorded["lesson_media"]["storage_path"].startswith(
        "lessons/lesson-1/images/"
    )
