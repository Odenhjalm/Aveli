import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi import HTTPException

from app import db, models
from app.config import settings
from app.media_control_plane.services.media_resolver_service import (
    LessonMediaPlaybackMode,
    LessonMediaResolution,
    LessonMediaResolutionReason,
)
from app.routes import api_media
from app.repositories import create_home_player_upload
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import lesson_playback_service
from app.services import storage_service as storage_module
from .utils import register_user

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


async def create_lesson(async_client, headers):
    slug = f"course-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Media Course",
            "slug": slug,
            "description": "Course for media tests",
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


async def _publish_course(async_client, headers, course_id: str) -> None:
    resp = await async_client.patch(
        f"/studio/courses/{course_id}",
        headers=headers,
        json={"is_published": True},
    )
    assert resp.status_code == 200, resp.text


async def _runtime_media_id_for_home_upload(upload_id: str) -> str:
    async with db.get_conn() as cur:
        await cur.execute(
            """
            SELECT id
            FROM app.runtime_media
            WHERE home_player_upload_id = %s
            LIMIT 1
            """,
            (upload_id,),
        )
        row = await cur.fetchone()
    assert row
    return str(row["id"])


async def _runtime_media_id_for_lesson_media(lesson_media_id: str) -> str:
    async with db.get_conn() as cur:
        await cur.execute(
            """
            SELECT id
            FROM app.runtime_media
            WHERE lesson_media_id = %s
            LIMIT 1
            """,
            (lesson_media_id,),
        )
        row = await cur.fetchone()
    assert row
    return str(row["id"])


class _FakePlaybackStorageClient:
    def __init__(self, url: str):
        self._url = url

    async def get_presigned_url(
        self,
        path,
        ttl,
        filename=None,
        *,
        download=False,
    ):
        assert path
        assert ttl > 0
        assert filename
        assert download is False
        return storage_module.PresignedUrl(
            url=self._url,
            expires_in=300,
            headers={},
        )


async def _create_media_asset(
    *,
    user_id: str,
    course_id: str,
    lesson_id: str,
    state: str,
    source_path: str,
    streaming_path: str | None = None,
) -> dict:
    initial_state = "uploaded" if state == "ready" else state
    asset = await media_assets_repo.create_media_asset(
        owner_id=user_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="audio",
        purpose="lesson_audio",
        ingest_format="wav",
        original_object_path=source_path,
        original_content_type="audio/wav",
        original_filename="demo.wav",
        original_size_bytes=1024,
        storage_bucket=storage_module.storage_service.bucket,
        state=initial_state,
        allow_uploaded_state=initial_state == "uploaded",
    )
    assert asset
    if state == "ready" and streaming_path:
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=str(asset["id"]),
            streaming_object_path=streaming_path,
            streaming_format="mp3",
            duration_seconds=120,
            codec="mp3",
        )
    return asset


async def _attach_media_asset(
    async_client,
    headers: dict[str, str],
    *,
    media_id: str,
    link_scope: str,
    lesson_id: str | None = None,
    lesson_media_id: str | None = None,
) -> dict:
    payload: dict[str, object] = {
        "media_id": media_id,
        "link_scope": link_scope,
    }
    if lesson_id is not None:
        payload["lesson_id"] = lesson_id
    if lesson_media_id is not None:
        payload["lesson_media_id"] = lesson_media_id

    response = await async_client.post(
        "/api/media/attach",
        headers=headers,
        json=payload,
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize(
    ("filename", "mime_type", "ingest_format"),
    [
        ("demo.mp3", "audio/mpeg", "mp3"),
        ("demo.wav", "audio/wav", "wav"),
        ("demo.m4a", "audio/mp4", "m4a"),
    ],
)
async def test_upload_url_allows_lesson_audio_sources(
    async_client,
    monkeypatch,
    filename,
    mime_type,
    ingest_format,
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": filename,
                "mime_type": mime_type,
                "size_bytes": 2048,
                "media_type": "audio",
                "lesson_id": lesson_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["upload_url"].startswith("https://storage.local/")
        assert body["storage_path"] == (
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/{filename}"
        )
        assert body.get("media_asset_id")
        now = datetime.now(timezone.utc)
        expires_at = datetime.fromisoformat(body["expires_at"])
        delta = (expires_at - now).total_seconds()
        assert -5 <= delta <= 130

        asset = await media_assets_repo.get_media_asset(body["media_asset_id"])
        assert asset is not None
        assert asset["media_type"] == "audio"
        assert asset["purpose"] == "lesson_audio"
        assert asset["ingest_format"] == ingest_format
        assert asset["original_content_type"] == mime_type
        assert asset["original_filename"] == filename
        assert asset["state"] == "pending_upload"

        async with db.get_conn() as cur:
            await cur.execute(
                """
                SELECT media_asset_id
                FROM app.lesson_media
                WHERE lesson_id = %s
                ORDER BY position
                """,
                (lesson_id,),
            )
            lesson_media_rows = await cur.fetchall()
        assert lesson_media_rows == []
    finally:
        await cleanup_user(user_id)


async def test_upload_url_allows_home_player_audio_purpose(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "home.wav",
                "mime_type": "audio/wav",
                "size_bytes": 2048,
                "media_type": "audio",
                "purpose": "home_player_audio",
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["upload_url"].startswith("https://storage.local/")
        assert f"home-player/{user_id}" in body["storage_path"]
        assert body["storage_path"].endswith("/home.wav")
        assert body.get("media_asset_id")

        asset = await media_assets_repo.get_media_asset(body["media_asset_id"])
        assert asset is not None
        assert asset["purpose"] == "home_player_audio"
        assert asset["state"] == "pending_upload"
    finally:
        await cleanup_user(user_id)


async def test_create_media_asset_rejects_unverified_uploaded_state(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        with pytest.raises(
            media_assets_repo.MediaAssetUploadedStateRequiresVerificationError
        ):
            await media_assets_repo.create_media_asset(
                owner_id=user_id,
                course_id=course_id,
                lesson_id=lesson_id,
                media_type="audio",
                purpose="lesson_audio",
                ingest_format="wav",
                original_object_path=(
                    f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
                ),
                original_content_type="audio/wav",
                original_filename="demo.wav",
                original_size_bytes=1024,
                storage_bucket=storage_module.storage_service.bucket,
                state="uploaded",
            )
    finally:
        await cleanup_user(user_id)


async def test_upload_url_allows_lesson_image_purpose(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "diagram.png",
                "mime_type": "image/png",
                "size_bytes": 2048,
                "media_type": "image",
                "lesson_id": lesson_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["upload_url"].startswith("https://storage.local/")
        assert body["storage_path"].startswith(f"lessons/{lesson_id}/images/")
        assert body.get("media_asset_id")

        asset = await media_assets_repo.get_media_asset(body["media_asset_id"])
        assert asset is not None
        assert asset["media_type"] == "image"
        assert asset["purpose"] == "lesson_media"
        assert asset["state"] == "pending_upload"
        assert asset["storage_bucket"] == settings.media_public_bucket
        assert asset["original_content_type"] == "image/png"
    finally:
        await cleanup_user(user_id)


async def test_attach_home_upload_is_idempotent(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        async def fake_wait_for_storage_object(**_kwargs):
            return True

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )
        monkeypatch.setattr(
            "app.routes.api_media._wait_for_storage_object",
            fake_wait_for_storage_object,
            raising=True,
        )

        upload_resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "home.wav",
                "mime_type": "audio/wav",
                "size_bytes": 2048,
                "media_type": "audio",
                "purpose": "home_player_audio",
            },
        )
        assert upload_resp.status_code == 200, upload_resp.text
        media_id = upload_resp.json()["media_asset_id"]

        complete_resp = await async_client.post(
            "/api/media/complete",
            headers=headers,
            json={"media_id": media_id},
        )
        assert complete_resp.status_code == 200, complete_resp.text

        first_attach = await _attach_media_asset(
            async_client,
            headers,
            media_id=media_id,
            link_scope="home_upload",
        )
        second_attach = await _attach_media_asset(
            async_client,
            headers,
            media_id=media_id,
            link_scope="home_upload",
        )

        assert first_attach["lesson_media_id"] is None
        assert second_attach["lesson_media_id"] is None
        assert first_attach["runtime_media_id"] == second_attach["runtime_media_id"]

        async with db.get_conn() as cur:
            await cur.execute(
                """
                SELECT count(*) AS upload_count
                FROM app.home_player_uploads
                WHERE teacher_id = %s
                  AND media_asset_id = %s
                """,
                (user_id, media_id),
            )
            upload_count = await cur.fetchone()
            await cur.execute(
                """
                SELECT count(*) AS runtime_count
                FROM app.runtime_media rm
                JOIN app.home_player_uploads hpu ON hpu.id = rm.home_player_upload_id
                WHERE hpu.teacher_id = %s
                  AND hpu.media_asset_id = %s
                """,
                (user_id, media_id),
            )
            runtime_count = await cur.fetchone()

        assert int(upload_count["upload_count"]) == 1
        assert int(runtime_count["runtime_count"]) == 1
    finally:
        await cleanup_user(user_id)


async def test_attach_lesson_rejects_home_player_assets(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        media_asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=None,
            lesson_id=None,
            media_type="audio",
            purpose="home_player_audio",
            ingest_format="wav",
            original_object_path=f"media/source/audio/home-player/{user_id}/demo.wav",
            original_content_type="audio/wav",
            original_filename="demo.wav",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert media_asset is not None

        resp = await async_client.post(
            "/api/media/attach",
            headers=headers,
            json={
                "media_id": str(media_asset["id"]),
                "lesson_id": lesson_id,
                "link_scope": "lesson",
            },
        )
        assert resp.status_code == 422, resp.text
        assert resp.json()["detail"] == "Only lesson uploads can use link_scope=lesson"
    finally:
        await cleanup_user(user_id)


@pytest.mark.parametrize(
    ("filename", "mime_type"),
    [
        ("demo.mp3", "audio/mpeg"),
        ("demo.wav", "audio/wav"),
        ("demo.m4a", "audio/mp4"),
    ],
)
async def test_complete_upload_requires_separate_attach_for_lesson_media(
    async_client,
    monkeypatch,
    filename,
    mime_type,
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        async def fake_wait_for_storage_object(*, storage_bucket: str, storage_path: str):
            assert storage_bucket == storage_module.storage_service.bucket
            assert storage_path == (
                f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/{filename}"
            )
            return True

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )
        monkeypatch.setattr(
            "app.routes.api_media._wait_for_storage_object",
            fake_wait_for_storage_object,
            raising=True,
        )

        upload_resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": filename,
                "mime_type": mime_type,
                "size_bytes": 2048,
                "media_type": "audio",
                "lesson_id": lesson_id,
            },
        )
        assert upload_resp.status_code == 200, upload_resp.text
        media_id = upload_resp.json()["media_asset_id"]

        pending_asset = await media_assets_repo.get_media_asset(media_id)
        assert pending_asset is not None
        assert pending_asset["state"] == "pending_upload"

        complete_resp = await async_client.post(
            "/api/media/complete",
            headers=headers,
            json={"media_id": media_id},
        )
        assert complete_resp.status_code == 200, complete_resp.text
        complete_body = complete_resp.json()
        assert complete_body["state"] == "uploaded"
        assert complete_body.get("lesson_media_id") is None
        assert complete_body.get("lesson_media") is None

        lesson_media_before_attach = await models.get_lesson_media_by_media_asset_id(media_id)
        assert lesson_media_before_attach is None

        attach_body = await _attach_media_asset(
            async_client,
            headers,
            media_id=media_id,
            link_scope="lesson",
            lesson_id=lesson_id,
        )
        assert attach_body["state"] == "uploaded"
        assert attach_body["lesson_media_id"]
        assert attach_body["runtime_media_id"]
        assert attach_body["lesson_media"]["id"] == attach_body["lesson_media_id"]
        assert attach_body["lesson_media"]["kind"] == "audio"
        assert "storage_path" not in attach_body["lesson_media"]
        assert "storage_bucket" not in attach_body["lesson_media"]
        assert "media_id" not in attach_body["lesson_media"]

        list_resp = await async_client.get(
            f"/studio/lessons/{lesson_id}/media",
            headers=headers,
        )
        assert list_resp.status_code == 200, list_resp.text
        listed_ids = {item["id"] for item in list_resp.json()["items"]}
        assert attach_body["lesson_media_id"] in listed_ids

        uploaded_asset = await media_assets_repo.get_media_asset(media_id)
        assert uploaded_asset is not None
        assert uploaded_asset["media_type"] == "audio"
        assert uploaded_asset["purpose"] == "lesson_audio"
        assert uploaded_asset["state"] == "uploaded"

        lesson_media = await models.get_lesson_media_by_media_asset_id(media_id)
        assert lesson_media is not None
        assert str(lesson_media["lesson_id"]) == lesson_id
        assert str(lesson_media["media_asset_id"]) == media_id
        assert lesson_media["storage_path"] is None

        derived_path = Path(
            str(uploaded_asset["original_object_path"]).replace(
                "media/source/audio/",
                "media/derived/audio/",
                1,
            )
        ).with_suffix(".mp3").as_posix()
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=media_id,
            streaming_object_path=derived_path,
            streaming_format="mp3",
            duration_seconds=42,
            codec="mp3",
        )
        ready_asset = await media_assets_repo.get_media_asset(media_id)
        assert ready_asset is not None
        assert ready_asset["state"] == "ready"
        assert ready_asset["streaming_object_path"] == derived_path
        assert ready_asset["streaming_format"] == "mp3"
    finally:
        await cleanup_user(user_id)


async def test_complete_lesson_image_upload_marks_asset_ready(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        async def fake_wait_for_storage_object(*, storage_bucket: str, storage_path: str):
            assert storage_bucket == settings.media_public_bucket
            assert storage_path.startswith(f"lessons/{lesson_id}/images/")
            return True

        async def fake_fetch_storage_object_details(pairs):
            pair_list = list(pairs)
            assert len(pair_list) == 1
            bucket, path = pair_list[0]
            assert bucket == settings.media_public_bucket
            assert path.startswith(f"lessons/{lesson_id}/images/")
            return {
                (bucket, path): {
                    "content_type": "image/png",
                    "size_bytes": 2048,
                }
            }, True

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )
        monkeypatch.setattr(
            "app.routes.api_media._wait_for_storage_object",
            fake_wait_for_storage_object,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.storage_objects,
            "fetch_storage_object_details",
            fake_fetch_storage_object_details,
            raising=True,
        )

        upload_resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "diagram.png",
                "mime_type": "image/png",
                "size_bytes": 2048,
                "media_type": "image",
                "lesson_id": lesson_id,
            },
        )
        assert upload_resp.status_code == 200, upload_resp.text
        media_id = upload_resp.json()["media_asset_id"]

        complete_resp = await async_client.post(
            "/api/media/complete",
            headers=headers,
            json={"media_id": media_id},
        )
        assert complete_resp.status_code == 200, complete_resp.text
        assert complete_resp.json()["state"] == "ready"

        lesson_media_before_attach = await models.get_lesson_media_by_media_asset_id(media_id)
        assert lesson_media_before_attach is None

        asset = await media_assets_repo.get_media_asset(media_id)
        assert asset is not None
        assert asset["state"] == "ready"
        assert asset["streaming_object_path"] == asset["original_object_path"]
        assert asset["streaming_storage_bucket"] == settings.media_public_bucket
        assert asset["storage_bucket"] == settings.media_public_bucket
    finally:
        await cleanup_user(user_id)


async def test_attach_lesson_image_requires_ready_and_returns_canonical_lesson_media(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        async def fake_wait_for_storage_object(**_kwargs):
            return True

        async def fake_fetch_storage_object_details(pairs):
            pair_list = list(pairs)
            bucket, path = pair_list[0]
            return {
                (bucket, path): {
                    "content_type": "image/png",
                    "size_bytes": 2048,
                }
            }, True

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )
        monkeypatch.setattr(
            "app.routes.api_media._wait_for_storage_object",
            fake_wait_for_storage_object,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.storage_objects,
            "fetch_storage_object_details",
            fake_fetch_storage_object_details,
            raising=True,
        )

        upload_resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "diagram.png",
                "mime_type": "image/png",
                "size_bytes": 2048,
                "media_type": "image",
                "lesson_id": lesson_id,
            },
        )
        assert upload_resp.status_code == 200, upload_resp.text
        media_id = upload_resp.json()["media_asset_id"]

        attach_resp = await async_client.post(
            "/api/media/attach",
            headers=headers,
            json={
                "media_id": media_id,
                "link_scope": "lesson",
                "lesson_id": lesson_id,
            },
        )
        assert attach_resp.status_code == 409, attach_resp.text
        assert attach_resp.json()["detail"] == (
            "Media asset must be ready before it can be attached"
        )

        complete_resp = await async_client.post(
            "/api/media/complete",
            headers=headers,
            json={"media_id": media_id},
        )
        assert complete_resp.status_code == 200, complete_resp.text
        assert complete_resp.json()["state"] == "ready"

        attach_body = await _attach_media_asset(
            async_client,
            headers,
            media_id=media_id,
            link_scope="lesson",
            lesson_id=lesson_id,
        )
        assert attach_body["state"] == "ready"
        assert attach_body["lesson_media_id"]
        assert attach_body["runtime_media_id"]
        assert attach_body["lesson_media"]["id"] == attach_body["lesson_media_id"]
        assert attach_body["lesson_media"]["kind"] == "image"
        assert "storage_path" not in attach_body["lesson_media"]
        assert "storage_bucket" not in attach_body["lesson_media"]
        assert "media_id" not in attach_body["lesson_media"]

        lesson_media = await models.get_lesson_media_by_media_asset_id(media_id)
        assert lesson_media is not None
        assert str(lesson_media["lesson_id"]) == lesson_id
        assert str(lesson_media["media_asset_id"]) == media_id

        async with db.get_conn() as cur:
            await cur.execute(
                """
                SELECT media_id, media_asset_id, storage_path
                FROM app.lesson_media
                WHERE id = %s
                """,
                (attach_body["lesson_media_id"],),
            )
            lesson_media_row = await cur.fetchone()

        assert lesson_media_row is not None
        assert lesson_media_row["media_id"] is None
        assert str(lesson_media_row["media_asset_id"]) == media_id
        assert lesson_media_row["storage_path"] is None
    finally:
        await cleanup_user(user_id)


async def test_attach_replacement_keeps_stable_lesson_and_runtime_ids(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        async def fake_wait_for_storage_object(**_kwargs):
            return True

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )
        monkeypatch.setattr(
            "app.routes.api_media._wait_for_storage_object",
            fake_wait_for_storage_object,
            raising=True,
        )

        async def upload_and_complete(filename: str) -> str:
            upload_resp = await async_client.post(
                "/api/media/upload-url",
                headers=headers,
                json={
                    "filename": filename,
                    "mime_type": "audio/wav",
                    "size_bytes": 2048,
                    "media_type": "audio",
                    "lesson_id": lesson_id,
                },
            )
            assert upload_resp.status_code == 200, upload_resp.text
            media_id = upload_resp.json()["media_asset_id"]

            complete_resp = await async_client.post(
                "/api/media/complete",
                headers=headers,
                json={"media_id": media_id},
            )
            assert complete_resp.status_code == 200, complete_resp.text
            return media_id

        first_media_id = await upload_and_complete("first.wav")
        first_attach = await _attach_media_asset(
            async_client,
            headers,
            media_id=first_media_id,
            link_scope="lesson",
            lesson_id=lesson_id,
        )
        original_lesson_media_id = first_attach["lesson_media_id"]
        original_runtime_media_id = first_attach["runtime_media_id"]

        second_media_id = await upload_and_complete("second.wav")
        replacement_attach = await _attach_media_asset(
            async_client,
            headers,
            media_id=second_media_id,
            link_scope="lesson",
            lesson_id=lesson_id,
            lesson_media_id=original_lesson_media_id,
        )
        assert replacement_attach["lesson_media_id"] == original_lesson_media_id
        assert replacement_attach["runtime_media_id"] == original_runtime_media_id

        lesson_media = await models.get_media(original_lesson_media_id)
        assert lesson_media is not None
        assert str(lesson_media["media_asset_id"]) == second_media_id

        async with db.get_conn() as cur:
            await cur.execute(
                """
                SELECT count(*) AS lesson_media_count
                FROM app.lesson_media
                WHERE lesson_id = %s
                """,
                (lesson_id,),
            )
            lesson_media_count = await cur.fetchone()
            await cur.execute(
                """
                SELECT count(*) AS active_runtime_count
                FROM app.runtime_media
                WHERE lesson_media_id = %s
                  AND active = true
                """,
                (original_lesson_media_id,),
            )
            active_runtime_count = await cur.fetchone()

        assert int(lesson_media_count["lesson_media_count"]) == 1
        assert int(active_runtime_count["active_runtime_count"]) == 1
    finally:
        await cleanup_user(user_id)


async def test_upload_url_requires_lesson_id_for_lesson_audio(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, _ = await create_lesson(async_client, headers)
        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "demo.wav",
                "mime_type": "audio/wav",
                "size_bytes": 1024,
                "media_type": "audio",
                "course_id": course_id,
            },
        )
        assert resp.status_code == 422, resp.text
        assert resp.json()["detail"] == "lesson_id is required for lesson audio uploads"
    finally:
        await cleanup_user(user_id)


async def test_upload_url_rejects_oversize(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)
        max_bytes = max(settings.media_upload_max_audio_bytes, 5 * 1024 * 1024 * 1024)
        resp = await async_client.post(
            "/api/media/upload-url",
            headers=headers,
            json={
                "filename": "demo.wav",
                "mime_type": "audio/wav",
                "size_bytes": max_bytes + 1,
                "media_type": "audio",
                "lesson_id": lesson_id,
            },
        )
        assert resp.status_code == 413, resp.text
    finally:
        await cleanup_user(user_id)


async def test_playback_url_blocks_until_ready(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        source_path = (
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
        )
        asset = await _create_media_asset(
            user_id=user_id,
            course_id=course_id,
            lesson_id=lesson_id,
            state="uploaded",
            source_path=source_path,
        )

        resp = await async_client.post(
            "/api/media/playback-url",
            headers=headers,
            json={"media_id": str(asset["id"])},
        )
        assert resp.status_code == 409, resp.text
    finally:
        await cleanup_user(user_id)


async def test_playback_url_authorized(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        source_path = (
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
        )
        derived_path = (
            f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )
        asset = await _create_media_asset(
            user_id=user_id,
            course_id=course_id,
            lesson_id=lesson_id,
            state="ready",
            source_path=source_path,
            streaming_path=derived_path,
        )

        async def fake_get_presigned_url(
            self,
            path,
            ttl,
            filename=None,
            *,
            download=True,
        ):
            assert download is False
            assert path.endswith(".mp3")
            assert "source" not in path
            return storage_module.PresignedUrl(
                url=f"https://stream.local/{path}",
                expires_in=300,
                headers={},
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "get_presigned_url",
            fake_get_presigned_url,
            raising=True,
        )

        now = datetime.now(timezone.utc)
        resp = await async_client.post(
            "/api/media/playback-url",
            headers=headers,
            json={"media_id": str(asset["id"])},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["playback_url"].startswith("https://stream.local/")
        assert body["format"] == "mp3"
        expires_at = datetime.fromisoformat(body["expires_at"])
        delta = (expires_at - now).total_seconds()
        assert 290 <= delta <= 310
    finally:
        await cleanup_user(user_id)


async def test_runtime_playback_success(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        runtime_media_id = str(uuid.uuid4())

        async def fake_resolve_runtime_media_playback(*, runtime_media_id: str, user_id: str):
            assert runtime_media_id
            assert user_id
            return {
                "runtime_media_id": runtime_media_id,
                "playback_url": "https://stream.local/media/derived/audio/demo.mp3",
                "kind": "audio",
                "content_type": "audio/mpeg",
                "duration_seconds": 123,
            }

        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_runtime_media_playback",
            fake_resolve_runtime_media_playback,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/playback",
            headers=headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["runtime_media_id"] == runtime_media_id
        assert body["playback_url"].startswith("https://stream.local/")
        assert body["kind"] == "audio"
        assert body["content_type"] == "audio/mpeg"
        assert body["duration_seconds"] == 123
    finally:
        await cleanup_user(user_id)


async def test_runtime_playback_returns_not_ready(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        runtime_media_id = str(uuid.uuid4())

        async def fake_resolve_runtime_media_playback(*, runtime_media_id: str, user_id: str):
            raise HTTPException(
                status_code=409,
                detail="Media is not ready",
            )

        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_runtime_media_playback",
            fake_resolve_runtime_media_playback,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/playback",
            headers=headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert resp.status_code == 409, resp.text
        assert resp.json()["detail"] == "Media is not ready"
    finally:
        await cleanup_user(user_id)


async def test_runtime_playback_denies_access(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        runtime_media_id = str(uuid.uuid4())

        async def fake_resolve_runtime_media_playback(*, runtime_media_id: str, user_id: str):
            raise HTTPException(
                status_code=403,
                detail="Access denied",
            )

        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_runtime_media_playback",
            fake_resolve_runtime_media_playback,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/playback",
            headers=headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert resp.status_code == 403, resp.text
        assert resp.json()["detail"] == "Access denied"
    finally:
        await cleanup_user(user_id)


async def test_runtime_playback_returns_not_found(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        runtime_media_id = str(uuid.uuid4())

        async def fake_resolve_runtime_media_playback(*, runtime_media_id: str, user_id: str):
            raise HTTPException(
                status_code=404,
                detail="Media not found",
            )

        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_runtime_media_playback",
            fake_resolve_runtime_media_playback,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/playback",
            headers=headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert resp.status_code == 404, resp.text
        assert resp.json()["detail"] == "Media not found"
    finally:
        await cleanup_user(user_id)


async def test_runtime_playback_home_direct_upload_legacy_object_access_control(
    async_client,
    monkeypatch,
):
    headers, user_id = await register_teacher(async_client)
    other_headers = None
    other_user_id = None
    try:
        media_object = await models.create_media_object(
            owner_id=user_id,
            storage_path=f"home-player/{user_id}/{uuid.uuid4().hex}.mp3",
            storage_bucket="course-media",
            content_type="audio/mpeg",
            byte_size=1024,
            checksum=None,
            original_name="home-object.mp3",
        )
        assert media_object
        upload = await create_home_player_upload(
            teacher_id=user_id,
            media_id=str(media_object["id"]),
            media_asset_id=None,
            title="Legacy Home Upload",
            kind="audio",
            active=True,
        )
        assert upload
        runtime_media_id = await _runtime_media_id_for_home_upload(str(upload["id"]))

        async def fake_storage_exists(*, storage_bucket: str, storage_path: str) -> bool:
            assert storage_bucket == "course-media"
            assert storage_path.endswith(".mp3")
            return True

        async def fake_resolve_storage_playback_url(**_kwargs):
            return "https://stream.local/home-object.mp3"

        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "_storage_object_exists",
            fake_storage_exists,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.media_resolver,
            "resolve_storage_playback_url",
            fake_resolve_storage_playback_url,
            raising=True,
        )

        teacher_resp = await async_client.post(
            "/api/media/playback",
            headers=headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert teacher_resp.status_code == 200, teacher_resp.text
        assert teacher_resp.json()["runtime_media_id"] == runtime_media_id
        assert teacher_resp.json()["playback_url"] == "https://stream.local/home-object.mp3"

        other_headers, other_user_id, _ = await register_user(async_client)
        denied_resp = await async_client.post(
            "/api/media/playback",
            headers=other_headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert denied_resp.status_code == 403, denied_resp.text
        assert denied_resp.json()["detail"] == "Access denied"

        course_id, _ = await create_lesson(async_client, headers)
        await _publish_course(async_client, headers, course_id)
        await courses_repo.ensure_course_enrollment(other_user_id, course_id)

        allowed_resp = await async_client.post(
            "/api/media/playback",
            headers=other_headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert allowed_resp.status_code == 200, allowed_resp.text
        assert allowed_resp.json()["runtime_media_id"] == runtime_media_id
        assert allowed_resp.json()["playback_url"] == "https://stream.local/home-object.mp3"
    finally:
        if other_user_id is not None:
            await cleanup_user(other_user_id)
        await cleanup_user(user_id)


async def test_runtime_playback_home_direct_upload_asset_backed(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=None,
            lesson_id=None,
            media_type="audio",
            purpose="home_player_audio",
            ingest_format="wav",
            original_object_path=f"media/source/audio/home/{uuid.uuid4().hex}.wav",
            original_content_type="audio/wav",
            original_filename="home.wav",
            original_size_bytes=2048,
            storage_bucket="course-media",
            state="processing",
        )
        assert asset
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=str(asset["id"]),
            streaming_object_path=f"media/derived/audio/home/{uuid.uuid4().hex}.mp3",
            streaming_format="mp3",
            duration_seconds=91,
            codec="mp3",
            streaming_storage_bucket="course-media",
        )
        upload = await create_home_player_upload(
            teacher_id=user_id,
            media_id=None,
            media_asset_id=str(asset["id"]),
            title="Asset Home Upload",
            kind="audio",
            active=True,
        )
        assert upload
        runtime_media_id = await _runtime_media_id_for_home_upload(str(upload["id"]))

        async def fake_storage_exists(*, storage_bucket: str, storage_path: str) -> bool:
            assert storage_bucket == "course-media"
            assert storage_path.endswith(".mp3")
            return True

        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "_storage_object_exists",
            fake_storage_exists,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.storage_service,
            "get_storage_service",
            lambda _bucket: _FakePlaybackStorageClient(
                "https://stream.local/home-asset.mp3"
            ),
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/playback",
            headers=headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["runtime_media_id"] == runtime_media_id
        assert body["playback_url"] == "https://stream.local/home-asset.mp3"
        assert body["kind"] == "audio"
        assert body["content_type"] == "audio/mpeg"
        assert body["duration_seconds"] == 91
    finally:
        await cleanup_user(user_id)


async def test_runtime_playback_home_course_linked_lesson_media(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    student_headers = None
    student_user_id = None
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        await _publish_course(async_client, headers, course_id)
        asset = await _create_media_asset(
            user_id=user_id,
            course_id=course_id,
            lesson_id=lesson_id,
            state="ready",
            source_path=f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/home.wav",
            streaming_path=f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/home.mp3",
        )
        lesson_media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=None,
            storage_bucket="course-media",
            media_id=None,
            media_asset_id=str(asset["id"]),
            position=1,
            duration_seconds=None,
        )
        assert lesson_media
        lesson_media_id = str(lesson_media["id"])
        runtime_media_id = await _runtime_media_id_for_lesson_media(lesson_media_id)

        create_link_resp = await async_client.post(
            "/studio/home-player/course-links",
            headers=headers,
            json={
                "lesson_media_id": lesson_media_id,
                "title": "Course-linked track",
                "enabled": True,
            },
        )
        assert create_link_resp.status_code == 201, create_link_resp.text

        async def fake_storage_exists(*, storage_bucket: str, storage_path: str) -> bool:
            assert storage_bucket == "course-media"
            assert storage_path.endswith(".mp3")
            return True

        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "_storage_object_exists",
            fake_storage_exists,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.storage_service,
            "get_storage_service",
            lambda _bucket: _FakePlaybackStorageClient(
                "https://stream.local/course-link.mp3"
            ),
            raising=True,
        )

        student_headers, student_user_id, _ = await register_user(async_client)
        denied_resp = await async_client.post(
            "/api/media/playback",
            headers=student_headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert denied_resp.status_code == 403, denied_resp.text

        await courses_repo.ensure_course_enrollment(student_user_id, course_id)
        allowed_resp = await async_client.post(
            "/api/media/playback",
            headers=student_headers,
            json={"runtime_media_id": runtime_media_id},
        )
        assert allowed_resp.status_code == 200, allowed_resp.text
        assert allowed_resp.json()["runtime_media_id"] == runtime_media_id
        assert allowed_resp.json()["playback_url"] == "https://stream.local/course-link.mp3"
    finally:
        if student_user_id is not None:
            await cleanup_user(student_user_id)
        await cleanup_user(user_id)


async def test_lesson_playback_pipeline_row(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_media_id = str(uuid.uuid4())
        async def fake_resolve_lesson_media_playback(
            *, lesson_media_id: str, user_id: str
        ):
            assert lesson_media_id
            assert user_id
            return {
                "url": "https://stream.local/media/derived/audio/demo.mp3",
                "expires_at": datetime.now(timezone.utc),
                "format": "mp3",
            }

        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_lesson_media_playback",
            fake_resolve_lesson_media_playback,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": lesson_media_id},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["url"].startswith("https://stream.local/")
    finally:
        await cleanup_user(user_id)


async def test_previews_and_lesson_playback_share_backend_resolution(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_id = str(uuid.uuid4())
        course_id = str(uuid.uuid4())
        image_id = str(uuid.uuid4())
        video_id = str(uuid.uuid4())
        audio_id = str(uuid.uuid4())

        async def fake_list_lesson_media_by_ids(candidate_ids: list[str]):
            return [
                {"id": image_id, "lesson_id": lesson_id},
                {"id": video_id, "lesson_id": lesson_id},
                {"id": audio_id, "lesson_id": lesson_id},
            ]

        async def fake_lesson_course_ids(candidate_lesson_id: str):
            assert candidate_lesson_id == lesson_id
            return None, course_id

        async def fake_is_course_owner(candidate_user_id: str, candidate_course_id: str):
            assert str(candidate_user_id) == user_id
            assert candidate_course_id == course_id
            return True

        async def fake_list_lesson_media(candidate_lesson_id: str, mode: str = "editor_preview"):
            assert candidate_lesson_id == lesson_id
            assert mode == "editor_preview"
            return [
                {
                    "id": image_id,
                    "lesson_id": lesson_id,
                    "kind": "image",
                    "original_name": "image.png",
                },
                {
                    "id": video_id,
                    "lesson_id": lesson_id,
                    "kind": "video",
                    "original_name": "video.mp4",
                },
                {
                    "id": audio_id,
                    "lesson_id": lesson_id,
                    "kind": "audio",
                    "original_name": "audio.mp3",
                },
            ]

        async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
            assert user_id
            return {
                "url": f"https://stream.local/{lesson_media_id}.bin",
                "playback_url": f"https://stream.local/{lesson_media_id}.bin",
            }

        monkeypatch.setattr(
            api_media.courses_repo,
            "list_lesson_media_by_ids",
            fake_list_lesson_media_by_ids,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.courses_service,
            "lesson_course_ids",
            fake_lesson_course_ids,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.models,
            "is_course_owner",
            fake_is_course_owner,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.courses_service,
            "list_lesson_media",
            fake_list_lesson_media,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.lesson_playback_service,
            "resolve_lesson_media_playback",
            fake_resolve_lesson_media_playback,
            raising=True,
        )

        preview_resp = await async_client.post(
            "/api/media/previews",
            headers=headers,
            json={"ids": [image_id, video_id, audio_id]},
        )
        assert preview_resp.status_code == 200, preview_resp.text
        preview_items = preview_resp.json()["items"]
        assert preview_items[image_id]["authoritative_editor_ready"] is True
        assert preview_items[image_id]["resolved_preview_url"] == (
            f"https://stream.local/{image_id}.bin"
        )
        assert preview_items[video_id]["authoritative_editor_ready"] is True
        assert preview_items[video_id]["resolved_preview_url"] == (
            f"https://stream.local/{video_id}.bin"
        )
        assert preview_items[audio_id]["authoritative_editor_ready"] is True
        assert preview_items[audio_id]["resolved_preview_url"] is None
        assert "thumbnail_url" not in preview_items[image_id]
        assert "poster_frame" not in preview_items[image_id]

        playback_resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": image_id},
        )
        assert playback_resp.status_code == 200, playback_resp.text
        assert (
            preview_items[image_id]["resolved_preview_url"]
            == playback_resp.json()["playback_url"]
        )
    finally:
        await cleanup_user(user_id)


async def test_media_previews_isolate_malformed_and_missing_ids(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_id = str(uuid.uuid4())
        course_id = str(uuid.uuid4())
        valid_id = str(uuid.uuid4())
        missing_id = str(uuid.uuid4())
        malformed_id = "not-a-uuid"

        async def fake_list_lesson_media_by_ids(candidate_ids: list[str]):
            assert valid_id in candidate_ids
            assert missing_id in candidate_ids
            return [{"id": valid_id, "lesson_id": lesson_id}]

        async def fake_lesson_course_ids(candidate_lesson_id: str):
            assert candidate_lesson_id == lesson_id
            return None, course_id

        async def fake_is_course_owner(candidate_user_id: str, candidate_course_id: str):
            assert str(candidate_user_id) == user_id
            assert candidate_course_id == course_id
            return True

        async def fake_list_lesson_media(candidate_lesson_id: str, mode: str = "editor_preview"):
            assert candidate_lesson_id == lesson_id
            assert mode == "editor_preview"
            return [
                {
                    "id": valid_id,
                    "lesson_id": lesson_id,
                    "kind": "image",
                    "original_name": "valid.png",
                }
            ]

        async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
            assert lesson_media_id == valid_id
            assert user_id
            return {
                "url": f"https://stream.local/{lesson_media_id}.bin",
                "playback_url": f"https://stream.local/{lesson_media_id}.bin",
            }

        monkeypatch.setattr(
            api_media.courses_repo,
            "list_lesson_media_by_ids",
            fake_list_lesson_media_by_ids,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.courses_service,
            "lesson_course_ids",
            fake_lesson_course_ids,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.models,
            "is_course_owner",
            fake_is_course_owner,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.courses_service,
            "list_lesson_media",
            fake_list_lesson_media,
            raising=True,
        )
        monkeypatch.setattr(
            api_media.lesson_playback_service,
            "resolve_lesson_media_playback",
            fake_resolve_lesson_media_playback,
            raising=True,
        )

        preview_resp = await async_client.post(
            "/api/media/previews",
            headers=headers,
            json={"ids": [valid_id, malformed_id, missing_id]},
        )
        assert preview_resp.status_code == 200, preview_resp.text
        preview_items = preview_resp.json()["items"]
        assert preview_items[valid_id]["authoritative_editor_ready"] is True
        assert preview_items[valid_id]["resolved_preview_url"] == (
            f"https://stream.local/{valid_id}.bin"
        )
        assert preview_items[malformed_id]["authoritative_editor_ready"] is False
        assert preview_items[malformed_id]["failure_reason"] == "invalid_id"
        assert preview_items[missing_id]["authoritative_editor_ready"] is False
        assert preview_items[missing_id]["failure_reason"] == "not_found"
    finally:
        await cleanup_user(user_id)


async def test_lesson_playback_legacy_row_is_blocked(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_media_id = str(uuid.uuid4())
        async def fake_resolve_lesson_media_playback(
            *, lesson_media_id: str, user_id: str
        ):
            raise HTTPException(
                status_code=404,
                detail="Lesson media has no playable source",
            )

        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_lesson_media_playback",
            fake_resolve_lesson_media_playback,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": lesson_media_id},
        )
        assert resp.status_code == 404, resp.text
        assert resp.json()["detail"] == "Lesson media has no playable source"
    finally:
        await cleanup_user(user_id)


async def test_lesson_playback_legacy_audio_passthrough_is_rejected(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)
        derived_path = (
            f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )
        media_object = await models.create_media_object(
            owner_id=user_id,
            storage_path=derived_path,
            storage_bucket="course-media",
            content_type="audio/mpeg",
            byte_size=321,
            checksum=None,
            original_name="demo.mp3",
        )
        assert media_object

        lesson_media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="audio",
            storage_path=derived_path,
            storage_bucket="course-media",
            media_id=str(media_object["id"]),
            position=1,
            duration_seconds=None,
        )
        assert lesson_media

        async def fake_get_presigned_url(
            self,
            path,
            ttl,
            filename=None,
            *,
            download=True,
        ):
            assert download is False
            assert path == derived_path
            assert ttl == 3600
            assert filename == "demo.mp3"
            return storage_module.PresignedUrl(
                url=f"https://stream.local/course-media/{path}",
                expires_in=3600,
                headers={},
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "get_presigned_url",
            fake_get_presigned_url,
            raising=True,
        )
        async def fake_storage_exists(*, storage_bucket: str, storage_path: str):
            assert storage_bucket == "course-media"
            assert storage_path == derived_path
            return True

        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "_storage_object_exists",
            fake_storage_exists,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": str(lesson_media["id"])},
        )
        assert resp.status_code == 404, resp.text
        assert resp.json()["detail"] == "Lesson media has no playable source"
    finally:
        await cleanup_user(user_id)


async def test_lesson_playback_invalid_row_returns_404(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        media_id = str(uuid.uuid4())

        async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
            raise HTTPException(
                status_code=404,
                detail="Lesson media has no playable source",
            )

        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_lesson_media_playback",
            fake_resolve_lesson_media_playback,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": media_id},
        )
        assert resp.status_code == 404, resp.text
        assert resp.json()["detail"] == "Lesson media has no playable source"
    finally:
        await cleanup_user(user_id)


async def test_lesson_playback_pipeline_preserves_teacher_bypass(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_media_id = str(uuid.uuid4())
        runtime_media_id = str(uuid.uuid4())
        media_asset_id = str(uuid.uuid4())
        resolution = LessonMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=str(uuid.uuid4()),
            media_asset_id=media_asset_id,
            legacy_media_object_id=None,
            kind="audio",
            content_type="audio/mpeg",
            media_state="ready",
            duration_seconds=120,
            storage_bucket="course-media",
            storage_path="media/derived/audio/demo.mp3",
            is_playable=True,
            playback_mode=LessonMediaPlaybackMode.PIPELINE_ASSET,
            failure_reason=LessonMediaResolutionReason.OK_READY_ASSET,
            asset_purpose="lesson_audio",
            runtime_media_id=runtime_media_id,
            reference_type="lesson_media",
            auth_scope="lesson_course",
            teacher_id=user_id,
            course_id=str(uuid.uuid4()),
            active=True,
            fallback_policy="never",
        )

        async def fake_lookup_runtime_media_id_for_lesson_media(candidate_lesson_media_id: str):
            assert candidate_lesson_media_id == lesson_media_id
            return runtime_media_id

        async def fake_resolve_runtime_media(candidate_runtime_media_id: str):
            assert candidate_runtime_media_id == runtime_media_id
            return resolution

        async def fake_get_media_asset_access(media_id: str):
            assert media_id == media_asset_id
            return {
                "id": media_asset_id,
                "lesson_id": resolution.lesson_id,
                "media_type": "audio",
                "state": "ready",
                "purpose": "lesson_audio",
                "course_id": resolution.course_id,
                "is_published": False,
                "is_intro": False,
                "is_free_intro": False,
                "streaming_object_path": "media/derived/audio/demo.mp3",
                "streaming_storage_bucket": "course-media",
                "storage_bucket": "course-media",
            }

        async def fake_is_course_teacher_or_instructor(user_id_value: str, _: str):
            assert user_id_value == user_id
            return True

        async def fail_if_snapshot_called(*args, **kwargs):
            raise AssertionError(
                "course_access_snapshot must not be called for teacher bypass"
            )

        class _FakeStorageClient:
            async def get_presigned_url(
                self,
                path,
                ttl,
                filename=None,
                *,
                download=True,
            ):
                assert ttl > 0
                assert filename == "demo.mp3"
                assert download is False
                return storage_module.PresignedUrl(
                    url=f"https://stream.local/{path}",
                    expires_in=300,
                    headers={},
                )

        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "lookup_runtime_media_id_for_lesson_media",
            fake_lookup_runtime_media_id_for_lesson_media,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "resolve_runtime_media",
            fake_resolve_runtime_media,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.media_assets_repo,
            "get_media_asset_access",
            fake_get_media_asset_access,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.courses_service,
            "is_course_teacher_or_instructor",
            fake_is_course_teacher_or_instructor,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.models,
            "course_access_snapshot",
            fail_if_snapshot_called,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.storage_service,
            "get_storage_service",
            lambda _bucket: _FakeStorageClient(),
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": lesson_media_id},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["url"].startswith("https://stream.local/")
    finally:
        await cleanup_user(user_id)


async def test_lesson_playback_legacy_intro_audio_is_rejected(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_media_id = str(uuid.uuid4())
        runtime_media_id = str(uuid.uuid4())
        resolution = LessonMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=str(uuid.uuid4()),
            media_asset_id=None,
            legacy_media_object_id="legacy-object-1",
            kind="audio",
            content_type="audio/mpeg",
            media_state="ready",
            duration_seconds=None,
            storage_bucket="course-media",
            storage_path="courses/demo/lessons/demo/legacy.mp3",
            is_playable=True,
            playback_mode=LessonMediaPlaybackMode.LEGACY_STORAGE,
            failure_reason=LessonMediaResolutionReason.OK_LEGACY_OBJECT,
            runtime_media_id=runtime_media_id,
            reference_type="lesson_media",
            auth_scope="lesson_course",
            teacher_id=user_id,
            course_id=str(uuid.uuid4()),
            active=True,
            fallback_policy="legacy_only",
        )

        async def fake_lookup_runtime_media_id_for_lesson_media(candidate_lesson_media_id: str):
            assert candidate_lesson_media_id == lesson_media_id
            return runtime_media_id

        async def fake_resolve_runtime_media(candidate_runtime_media_id: str):
            assert candidate_runtime_media_id == runtime_media_id
            return resolution

        async def fake_get_lesson_media_access_by_path(
            *, storage_path: str, storage_bucket: str
        ):
            assert storage_path
            assert storage_bucket
            return {
                "course_id": str(uuid.uuid4()),
                "is_published": True,
                "is_intro": True,
                "is_free_intro": False,
            }

        async def fake_is_course_teacher_or_instructor(*_args, **_kwargs):
            return False

        async def fail_if_snapshot_called(*args, **kwargs):
            raise AssertionError(
                "course_access_snapshot must not be called for intro media"
            )

        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "lookup_runtime_media_id_for_lesson_media",
            fake_lookup_runtime_media_id_for_lesson_media,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "resolve_runtime_media",
            fake_resolve_runtime_media,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.courses_repo,
            "get_lesson_media_access_by_path",
            fake_get_lesson_media_access_by_path,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.courses_service,
            "is_course_teacher_or_instructor",
            fake_is_course_teacher_or_instructor,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.models,
            "course_access_snapshot",
            fail_if_snapshot_called,
            raising=True,
        )

        async def fake_resolve_storage_playback_url(**_kwargs):
            return (
                "https://stream.local/course-media/courses/demo/lessons/demo/legacy.mp3"
            )

        monkeypatch.setattr(
            lesson_playback_service.media_resolver,
            "resolve_storage_playback_url",
            fake_resolve_storage_playback_url,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": lesson_media_id},
        )
        assert resp.status_code == 404, resp.text
        assert resp.json()["detail"] == "Lesson media has no playable source"
    finally:
        await cleanup_user(user_id)


async def test_lesson_playback_legacy_non_intro_audio_is_rejected(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_media_id = str(uuid.uuid4())
        runtime_media_id = str(uuid.uuid4())
        resolution = LessonMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=str(uuid.uuid4()),
            media_asset_id=None,
            legacy_media_object_id="legacy-object-1",
            kind="audio",
            content_type="audio/mpeg",
            media_state="ready",
            duration_seconds=None,
            storage_bucket="course-media",
            storage_path="courses/demo/lessons/demo/legacy.mp3",
            is_playable=True,
            playback_mode=LessonMediaPlaybackMode.LEGACY_STORAGE,
            failure_reason=LessonMediaResolutionReason.OK_LEGACY_OBJECT,
            runtime_media_id=runtime_media_id,
            reference_type="lesson_media",
            auth_scope="lesson_course",
            teacher_id=user_id,
            course_id=str(uuid.uuid4()),
            active=True,
            fallback_policy="legacy_only",
        )

        async def fake_lookup_runtime_media_id_for_lesson_media(candidate_lesson_media_id: str):
            assert candidate_lesson_media_id == lesson_media_id
            return runtime_media_id

        async def fake_resolve_runtime_media(candidate_runtime_media_id: str):
            assert candidate_runtime_media_id == runtime_media_id
            return resolution

        async def fake_get_lesson_media_access_by_path(
            *, storage_path: str, storage_bucket: str
        ):
            assert storage_path
            assert storage_bucket
            return {
                "course_id": str(uuid.uuid4()),
                "is_published": True,
                "is_intro": False,
                "is_free_intro": False,
            }

        async def fake_is_course_teacher_or_instructor(*_args, **_kwargs):
            return False

        async def fail_if_snapshot_called(*args, **kwargs):
            raise AssertionError(
                "course_access_snapshot must not be called for legacy lesson audio"
            )

        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "lookup_runtime_media_id_for_lesson_media",
            fake_lookup_runtime_media_id_for_lesson_media,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.canonical_media_resolver,
            "resolve_runtime_media",
            fake_resolve_runtime_media,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.courses_repo,
            "get_lesson_media_access_by_path",
            fake_get_lesson_media_access_by_path,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.courses_service,
            "is_course_teacher_or_instructor",
            fake_is_course_teacher_or_instructor,
            raising=True,
        )
        monkeypatch.setattr(
            lesson_playback_service.models,
            "course_access_snapshot",
            fail_if_snapshot_called,
            raising=True,
        )
        resp = await async_client.post(
            "/api/media/lesson-playback",
            headers=headers,
            json={"lesson_media_id": lesson_media_id},
        )
        assert resp.status_code == 404, resp.text
        assert resp.json()["detail"] == "Lesson media has no playable source"
    finally:
        await cleanup_user(user_id)


async def test_debug_media_returns_storage_path_and_signed_url(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        lesson_media_id = str(uuid.uuid4())
        storage_path = "media/derived/audio/courses/demo/lessons/demo/legacy.mp3"

        async def fake_get_media(media_id: str):
            assert media_id == lesson_media_id
            return {
                "id": lesson_media_id,
                "media_asset_id": None,
                "storage_path": storage_path,
                "storage_bucket": "course-media",
            }

        async def fake_resolve_object_media_playback(
            *, lesson_media_id: str, user_id: str
        ):
            assert lesson_media_id
            assert user_id
            return {
                "media_id": lesson_media_id,
                "url": f"https://stream.local/course-media/{storage_path}",
                "playback_url": f"https://stream.local/course-media/{storage_path}",
                "storage_path": storage_path,
            }

        monkeypatch.setattr(models, "get_media", fake_get_media, raising=True)
        monkeypatch.setattr(
            lesson_playback_service,
            "resolve_object_media_playback",
            fake_resolve_object_media_playback,
            raising=True,
        )

        resp = await async_client.get(
            f"/debug/media/{lesson_media_id}",
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["lesson_media_id"] == lesson_media_id
        assert body["storage_path"] == storage_path
        assert body["signed_url"] == f"https://stream.local/course-media/{storage_path}"
    finally:
        await cleanup_user(user_id)


async def test_upload_url_requires_auth(async_client):
    lesson_id = str(uuid.uuid4())
    resp = await async_client.post(
        "/api/media/upload-url",
        json={
            "filename": "demo.wav",
            "mime_type": "audio/wav",
            "size_bytes": 1024,
            "media_type": "audio",
            "lesson_id": lesson_id,
        },
    )
    assert resp.status_code == 401


async def test_playback_url_requires_auth(async_client):
    resp = await async_client.post(
        "/api/media/playback-url",
        json={"media_id": str(uuid.uuid4())},
    )
    assert resp.status_code == 401


async def test_playback_url_rejects_non_owner(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    other_headers = None
    other_user_id = None
    try:
        other_headers, other_user_id, _ = await register_user(async_client)
        course_id, lesson_id = await create_lesson(async_client, headers)
        source_path = (
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
        )
        derived_path = (
            f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )
        asset = await _create_media_asset(
            user_id=user_id,
            course_id=course_id,
            lesson_id=lesson_id,
            state="ready",
            source_path=source_path,
            streaming_path=derived_path,
        )

        async def fake_get_presigned_url(
            self,
            path,
            ttl,
            filename=None,
            *,
            download=True,
        ):
            return storage_module.PresignedUrl(
                url=f"https://stream.local/{path}",
                expires_in=300,
                headers={},
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "get_presigned_url",
            fake_get_presigned_url,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/playback-url",
            headers=other_headers,
            json={"media_id": str(asset["id"])},
        )
        assert resp.status_code == 403, resp.text
    finally:
        if other_user_id:
            await cleanup_user(other_user_id)
        await cleanup_user(user_id)


async def test_wav_upload_position_allows_upload_after_deletion(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        _, lesson_id = await create_lesson(async_client, headers)

        async def fake_create_upload_url(
            self,
            path,
            *,
            content_type,
            upsert,
            cache_seconds,
        ):
            return storage_module.PresignedUpload(
                url=f"https://storage.local/{path}",
                headers={"content-type": content_type},
                path=path,
                expires_in=120,
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "create_upload_url",
            fake_create_upload_url,
            raising=True,
        )
        async def fake_wait_for_storage_object(**_kwargs):
            return True

        monkeypatch.setattr(
            "app.routes.api_media._wait_for_storage_object",
            fake_wait_for_storage_object,
            raising=True,
        )

        async def issue_upload(filename: str) -> dict:
            resp = await async_client.post(
                "/api/media/upload-url",
                headers=headers,
                json={
                    "filename": filename,
                    "mime_type": "audio/wav",
                    "size_bytes": 2048,
                    "media_type": "audio",
                    "lesson_id": lesson_id,
                },
            )
            assert resp.status_code == 200, resp.text
            complete_resp = await async_client.post(
                "/api/media/complete",
                headers=headers,
                json={"media_id": resp.json()["media_asset_id"]},
            )
            assert complete_resp.status_code == 200, complete_resp.text
            await _attach_media_asset(
                async_client,
                headers,
                media_id=resp.json()["media_asset_id"],
                link_scope="lesson",
                lesson_id=lesson_id,
            )
            return resp.json()

        await issue_upload("a.wav")
        await issue_upload("b.wav")

        async with db.get_conn() as cur:
            await cur.execute(
                "SELECT id, position, media_asset_id FROM app.lesson_media WHERE lesson_id = %s ORDER BY position",
                (lesson_id,),
            )
            before_delete = await cur.fetchall()
        assert len(before_delete) == 2
        first_id = str(before_delete[0]["id"])
        second_position = int(before_delete[1].get("position") or 0)
        assert second_position == 2, before_delete[1]

        delete_resp = await async_client.delete(
            f"/studio/media/{first_id}",
            headers=headers,
        )
        assert delete_resp.status_code == 200, delete_resp.text

        async with db.get_conn() as cur:
            await cur.execute(
                "SELECT id, position, media_asset_id FROM app.lesson_media WHERE lesson_id = %s ORDER BY position",
                (lesson_id,),
            )
            after_delete = await cur.fetchall()
        assert len(after_delete) == 1
        assert (
            int(after_delete[0].get("position") or 0) == second_position
        ), after_delete[0]

        await issue_upload("c.wav")

        async with db.get_conn() as cur:
            await cur.execute(
                "SELECT position FROM app.lesson_media WHERE lesson_id = %s ORDER BY position",
                (lesson_id,),
            )
            positions = [int(row.get("position") or 0) for row in await cur.fetchall()]
        assert positions == [2, 3]
    finally:
        await cleanup_user(user_id)


async def test_playback_url_allows_subscription_only_access(async_client, monkeypatch):
    headers, owner_id = await register_teacher(async_client)
    student_headers, student_id, _ = await register_user(async_client)
    try:
        course_id, lesson_id = await create_lesson(async_client, headers)

        async def fake_get_presigned_url(
            self,
            path,
            ttl,
            filename=None,
            *,
            download=True,
        ):
            return storage_module.PresignedUrl(
                url=f"https://stream.local/{path}",
                expires_in=300,
                headers={},
            )

        monkeypatch.setattr(
            storage_module.StorageService,
            "get_presigned_url",
            fake_get_presigned_url,
            raising=True,
        )

        # Create and mark a pipeline audio asset ready.
        source_path = (
            f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav"
        )
        derived_path = (
            f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/demo.mp3"
        )
        asset = await media_assets_repo.create_media_asset(
            owner_id=owner_id,
            course_id=course_id,
            lesson_id=lesson_id,
            media_type="audio",
            purpose="lesson_audio",
            ingest_format="wav",
            original_object_path=source_path,
            original_content_type="audio/wav",
            original_filename="demo.wav",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert asset
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=str(asset["id"]),
            streaming_object_path=derived_path,
            streaming_format="mp3",
            duration_seconds=120,
            codec="mp3",
            streaming_storage_bucket=storage_module.storage_service.bucket,
        )

        # Grant the student an active subscription (but do not enroll them).
        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    INSERT INTO app.subscriptions (user_id, subscription_id, status)
                    VALUES (%s, %s, %s)
                    """,
                    (student_id, f"sub_{uuid.uuid4().hex[:10]}", "active"),
                )
                await conn.commit()

        # Unpublished courses must remain inaccessible even for subscription users.
        playback_unpublished = await async_client.post(
            "/api/media/playback-url",
            headers=student_headers,
            json={"media_id": str(asset["id"])},
        )
        assert playback_unpublished.status_code == 403, playback_unpublished.text

        # Publish the course so non-owners can attempt playback access.
        publish_resp = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=headers,
            json={"is_published": True},
        )
        assert publish_resp.status_code == 200, publish_resp.text

        access_resp = await async_client.get(
            f"/courses/{course_id}/access",
            headers=student_headers,
        )
        assert access_resp.status_code == 200, access_resp.text
        access_payload = access_resp.json()
        print("course_access_snapshot", access_payload)
        assert access_payload["has_active_subscription"] is True
        assert access_payload["has_access"] is True
        assert access_payload["enrolled"] is False

        playback_resp = await async_client.post(
            "/api/media/playback-url",
            headers=student_headers,
            json={"media_id": str(asset["id"])},
        )
        assert playback_resp.status_code == 200, playback_resp.text
        playback_payload = playback_resp.json()
        assert playback_payload.get("playback_url", "").startswith(
            "https://stream.local/"
        )
    finally:
        await cleanup_user(student_id)
        await cleanup_user(owner_id)
