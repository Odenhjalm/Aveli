import uuid

import pytest

from app import db
from app.services import storage_service as storage_module


pytestmark = pytest.mark.anyio("asyncio")


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _register_teacher(async_client):
    email = f"public_media_{uuid.uuid4().hex[:8]}@example.com"
    password = "Secret123!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Teacher"},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = _auth_header(tokens["access_token"])
    profile_resp = await async_client.get("/auth/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]
    await _promote_to_teacher(user_id)
    return headers, user_id


async def _promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def _cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _create_lesson(async_client, headers):
    slug = f"public-media-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Public Media Course",
            "slug": slug,
            "description": "Course for public-media tests",
            "is_published": False,
        },
    )
    assert course_resp.status_code == 200, course_resp.text
    course_id = str(course_resp.json()["id"])

    lesson_resp = await async_client.post(
        "/studio/lessons",
        headers=headers,
        json={
            "course_id": course_id,
            "title": "Lesson",
            "content_markdown": "# Lesson",
            "position": 1,
            "is_intro": False,
        },
    )
    assert lesson_resp.status_code == 200, lesson_resp.text
    lesson_id = str(lesson_resp.json()["id"])
    return course_id, lesson_id


async def test_public_media_lesson_image_roundtrip_uses_supabase(async_client, tmp_path, monkeypatch):
    """
    Regression test: public-media lesson images must not rely on local disk.

    When Supabase Storage is enabled, uploads should go to the public bucket and
    /api/files/public-media/... should proxy bytes from Supabase.
    """

    from app.routes import upload as upload_routes

    upload_root = tmp_path / "uploads"
    upload_root.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(upload_routes, "UPLOADS_ROOT", upload_root, raising=True)

    # Enable Supabase for the public bucket within this test.
    monkeypatch.setattr(storage_module.public_storage_service, "_supabase_url", "https://supabase.local", raising=True)
    monkeypatch.setattr(storage_module.public_storage_service, "_service_role_key", "test", raising=True)

    last_signed_path: dict[str, str] = {}

    async def fake_create_upload_url(self, path, *, content_type=None, upsert=False, cache_seconds=None):
        last_signed_path["path"] = path
        return storage_module.PresignedUpload(
            url=f"https://storage.local/upload/{path}",
            headers={
                "x-upsert": "true" if upsert else "false",
                "content-type": content_type or "application/octet-stream",
                "cache-control": f"max-age={cache_seconds or 60}",
            },
            path=path,
            expires_in=3600,
        )

    monkeypatch.setattr(
        "app.services.storage_service.StorageService.create_upload_url",
        fake_create_upload_url,
        raising=True,
    )

    class FakeResponse:
        def __init__(self, status_code: int, content: bytes = b"", headers: dict[str, str] | None = None):
            self.status_code = status_code
            self.content = content
            self.headers = headers or {}

    class FakeAsyncClient:
        stored: dict[str, bytes] = {}

        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def put(self, url, *, headers=None, content=None):
            marker = "/upload/"
            path = str(url).split(marker, 1)[-1]
            payload = content if isinstance(content, (bytes, bytearray)) else b""
            self.stored[path] = bytes(payload)
            return FakeResponse(200)

        async def get(self, url, *, headers=None):
            marker = "/storage/v1/object/public/public-media/"
            path = str(url).split(marker, 1)[-1]
            if path not in self.stored:
                return FakeResponse(404)
            return FakeResponse(200, content=self.stored[path], headers={"content-type": "image/png"})

    monkeypatch.setattr(upload_routes.httpx, "AsyncClient", FakeAsyncClient, raising=True)

    headers, user_id = await _register_teacher(async_client)
    try:
        course_id, lesson_id = await _create_lesson(async_client, headers)

        upload_resp = await async_client.post(
            "/api/upload/course-media",
            headers=headers,
            data={"course_id": course_id, "lesson_id": lesson_id, "type": "image"},
            files={"file": ("demo.png", b"png-bytes", "image/png")},
        )
        assert upload_resp.status_code == 200, upload_resp.text
        payload = upload_resp.json()
        assert payload["storage_bucket"] == "public-media"
        assert payload["path"].startswith(f"public-media/{course_id}/{lesson_id}/image/")
        assert "/api/files/public-media/" in (payload.get("url") or "")

        assert last_signed_path.get("path") == payload["path"]
        # Supabase mode should not write to local disk at all.
        assert list(upload_root.rglob("*")) == []

        fetch_resp = await async_client.get(f"/api/files/{payload['path']}")
        assert fetch_resp.status_code == 200, fetch_resp.text
        assert fetch_resp.content == b"png-bytes"
    finally:
        await _cleanup_user(user_id)
