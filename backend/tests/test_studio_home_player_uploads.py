import uuid

import pytest

from app import db
from app.services import storage_service as storage_module

pytestmark = pytest.mark.anyio("asyncio")


async def register_teacher(async_client):
    email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    password = "Secret123!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Teacher"},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    profile_resp = await async_client.get("/auth/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]
    await promote_to_teacher(user_id)
    return headers, user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def test_home_player_upload_url_allows_video_mp4(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        # Studio route checks `.enabled`, so ensure the cached service looks configured.
        service = storage_module.get_storage_service("course-media")
        service._supabase_url = service._supabase_url or "https://supabase.local"
        service._service_role_key = service._service_role_key or "dev-service-role"

        async def fake_create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            assert self.bucket == "course-media"
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=3600,
            )

        monkeypatch.setattr(
            "app.services.storage_service.StorageService.create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        presign_resp = await async_client.post(
            "/studio/home-player/uploads/upload-url",
            headers=headers,
            json={
                "filename": "demo.mp4",
                "mime_type": "video/mp4",
                "size_bytes": 1024,
            },
        )
        assert presign_resp.status_code == 200, presign_resp.text
        presign_data = presign_resp.json()
        assert presign_data["upload_url"].startswith("https://storage.local/")
        assert presign_data["object_path"].startswith(f"home-player/{user_id}/")
        assert presign_data["object_path"].endswith("_demo.mp4")

        create_resp = await async_client.post(
            "/studio/home-player/uploads",
            headers=headers,
            json={
                "title": "Demo video",
                "active": True,
                "storage_bucket": "course-media",
                "storage_path": presign_data["object_path"],
                "content_type": "video/mp4",
                "byte_size": 1024,
                "original_name": "demo.mp4",
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        created = create_resp.json()
        assert created["kind"] == "video"
        assert created["content_type"] == "video/mp4"
    finally:
        await cleanup_user(user_id)


async def test_home_player_upload_url_allows_audio_mp3(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        service = storage_module.get_storage_service("course-media")
        service._supabase_url = service._supabase_url or "https://supabase.local"
        service._service_role_key = service._service_role_key or "dev-service-role"

        async def fake_create_upload_url(self, path, *, content_type, upsert, cache_seconds):
            assert self.bucket == "course-media"
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=3600,
            )

        monkeypatch.setattr(
            "app.services.storage_service.StorageService.create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        resp = await async_client.post(
            "/studio/home-player/uploads/upload-url",
            headers=headers,
            json={
                "filename": "demo.mp3",
                "mime_type": "audio/mp3",
                "size_bytes": 1024,
            },
        )
        assert resp.status_code == 200, resp.text
        presign = resp.json()
        assert presign["headers"]["content-type"] == "audio/mpeg"

        create_resp = await async_client.post(
            "/studio/home-player/uploads",
            headers=headers,
            json={
                "title": "Demo audio",
                "active": True,
                "storage_bucket": "course-media",
                "storage_path": presign["object_path"],
                "content_type": "audio/mp3",
                "byte_size": 1024,
                "original_name": "demo.mp3",
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        created = create_resp.json()
        assert created["kind"] == "audio"
        assert created["content_type"] == "audio/mpeg"
        assert created.get("media_id")
        assert created.get("media_asset_id") is None
    finally:
        await cleanup_user(user_id)


async def test_home_player_upload_url_rejects_audio_wav(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        resp = await async_client.post(
            "/studio/home-player/uploads/upload-url",
            headers=headers,
            json={
                "filename": "demo.wav",
                "mime_type": "audio/wav",
                "size_bytes": 1024,
            },
        )
        assert resp.status_code == 422, resp.text
        assert "WAV uploads must use the media pipeline" in resp.text
    finally:
        await cleanup_user(user_id)
