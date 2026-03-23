import logging
import uuid
from datetime import datetime, timezone

import pytest

from app import db, models
from app.repositories import media_assets as media_assets_repo
from app.routes import api_media
from app.services import media_cleanup
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


async def create_course(async_client, headers):
    slug = f"course-{uuid.uuid4().hex[:6]}"
    course_resp = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": "Cover Course",
            "slug": slug,
            "description": "Course for cover tests",
            "is_published": False,
        },
    )
    assert course_resp.status_code == 200, course_resp.text
    return str(course_resp.json()["id"])


async def create_lesson(async_client, headers, course_id: str):
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
    return str(lesson_resp.json()["id"])


async def count_course_cover_assets(course_id: str) -> int:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT count(*)
                FROM app.media_assets
                WHERE course_id = %s
                  AND purpose = 'course_cover'
                """,
                (course_id,),
            )
            row = await cur.fetchone()
    return int(row[0] if row else 0)


async def get_course_meta(async_client, headers, course_id: str) -> dict:
    response = await async_client.get(
        f"/studio/courses/{course_id}",
        headers=headers,
    )
    assert response.status_code == 200, response.text
    return response.json()


async def get_course_cover_fields(course_id: str) -> dict[str, str | None]:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT cover_media_id::text, cover_url
                FROM app.courses
                WHERE id = %s
                """,
                (course_id,),
            )
            row = await cur.fetchone()
    assert row is not None
    return {
        "cover_media_id": row[0],
        "cover_url": row[1],
    }


async def set_course_cover_url(course_id: str, cover_url: str | None) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.courses
                SET cover_url = %s,
                    updated_at = now()
                WHERE id = %s
                """,
                (cover_url, course_id),
            )
            await conn.commit()


async def test_cover_upload_url_allows_image(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)

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

        now = datetime.now(timezone.utc)
        resp = await async_client.post(
            "/api/media/cover-upload-url",
            headers=headers,
            json={
                "filename": "cover.jpg",
                "mime_type": "image/jpeg",
                "size_bytes": 2048,
                "course_id": course_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["upload_url"].startswith("https://storage.local/")
        assert "media/source/cover/courses" in body["object_path"]
        assert body["object_path"].endswith("_cover.jpg")
        expires_at = datetime.fromisoformat(body["expires_at"])
        delta = (expires_at - now).total_seconds()
        assert 110 <= delta <= 130

        asset = await media_assets_repo.get_media_asset(body["media_id"])
        assert asset is not None
        assert asset["media_type"] == "image"
        assert asset["purpose"] == "course_cover"
        assert asset["state"] == "pending_upload"
        meta = await get_course_cover_fields(course_id)
        assert meta.get("cover_media_id") is None
        assert meta.get("cover_url") is None
    finally:
        await cleanup_user(user_id)


async def test_complete_cover_upload_promotes_verified_asset(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)

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
            assert storage_path.startswith(f"media/source/cover/courses/{course_id}/")
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
            "/api/media/cover-upload-url",
            headers=headers,
            json={
                "filename": "cover.jpg",
                "mime_type": "image/jpeg",
                "size_bytes": 2048,
                "course_id": course_id,
            },
        )
        assert upload_resp.status_code == 200, upload_resp.text
        media_id = upload_resp.json()["media_id"]

        pending_asset = await media_assets_repo.get_media_asset(media_id)
        assert pending_asset is not None
        assert pending_asset["state"] == "pending_upload"

        complete_resp = await async_client.post(
            "/api/media/complete",
            headers=headers,
            json={"media_id": media_id},
        )
        assert complete_resp.status_code == 200, complete_resp.text
        assert complete_resp.json()["state"] == "uploaded"

        uploaded_asset = await media_assets_repo.get_media_asset(media_id)
        assert uploaded_asset is not None
        assert uploaded_asset["state"] == "uploaded"
        meta = await get_course_cover_fields(course_id)
        assert meta.get("cover_media_id") is None
        assert meta.get("cover_url") is None
    finally:
        await cleanup_user(user_id)


async def test_cover_upload_url_rejects_non_image(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        resp = await async_client.post(
            "/api/media/cover-upload-url",
            headers=headers,
            json={
                "filename": "cover.wav",
                "mime_type": "audio/wav",
                "size_bytes": 1024,
                "course_id": course_id,
            },
        )
        assert resp.status_code == 415, resp.text
    finally:
        await cleanup_user(user_id)


async def test_cover_from_lesson_media_creates_asset(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        lesson_id = await create_lesson(async_client, headers, course_id)
        lesson_storage_path = f"lessons/{lesson_id}/images/demo.png"
        copy_calls: list[dict[str, str | None]] = []

        async def fake_fetch_storage_object_existence(pairs):
            return {tuple(pair): True for pair in pairs}, True

        async def fake_copy_object(
            *,
            source_bucket,
            source_path,
            destination_bucket,
            destination_path,
            content_type=None,
            cache_seconds=None,
        ):
            copy_calls.append(
                {
                    "source_bucket": source_bucket,
                    "source_path": source_path,
                    "destination_bucket": destination_bucket,
                    "destination_path": destination_path,
                    "content_type": content_type,
                }
            )

        monkeypatch.setattr(
            api_media.storage_objects,
            "fetch_storage_object_existence",
            fake_fetch_storage_object_existence,
            raising=True,
        )
        monkeypatch.setattr(
            storage_module,
            "copy_object",
            fake_copy_object,
            raising=True,
        )

        media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="image",
            storage_path=lesson_storage_path,
            storage_bucket=storage_module.public_storage_service.bucket,
            media_id=None,
            media_asset_id=None,
            position=1,
            duration_seconds=None,
        )
        assert media

        resp = await async_client.post(
            "/api/media/cover-from-media",
            headers=headers,
            json={
                "course_id": course_id,
                "lesson_media_id": str(media["id"]),
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        asset = await media_assets_repo.get_media_asset(body["media_id"])
        assert asset is not None
        assert len(copy_calls) == 1
        copied = copy_calls[0]
        assert copied["source_bucket"] == storage_module.public_storage_service.bucket
        assert copied["source_path"] == lesson_storage_path
        assert copied["destination_bucket"] == storage_module.storage_service.bucket
        assert copied["destination_path"] is not None
        assert str(copied["destination_path"]).startswith(
            f"media/source/cover/courses/{course_id}/"
        )
        assert asset["original_object_path"] == copied["destination_path"]
        assert asset["original_object_path"] != lesson_storage_path
        assert not str(asset["original_object_path"]).startswith("lessons/")
        assert asset["purpose"] == "course_cover"
        assert asset["storage_bucket"] == storage_module.storage_service.bucket
        meta = await get_course_cover_fields(course_id)
        assert meta.get("cover_media_id") is None
        assert meta.get("cover_url") is None
    finally:
        await cleanup_user(user_id)


async def test_cover_from_lesson_media_rejects_bucket_prefixed_path(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        lesson_id = await create_lesson(async_client, headers, course_id)

        media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="image",
            storage_path=f"{storage_module.storage_service.bucket}/demo/cover.png",
            storage_bucket=storage_module.storage_service.bucket,
            media_id=None,
            media_asset_id=None,
            position=1,
            duration_seconds=None,
        )
        assert media

        before_count = await count_course_cover_assets(course_id)
        resp = await async_client.post(
            "/api/media/cover-from-media",
            headers=headers,
            json={
                "course_id": course_id,
                "lesson_media_id": str(media["id"]),
            },
        )
        assert resp.status_code == 400, resp.text
        assert resp.json()["detail"] == "Cover source storage_path must not include bucket prefix"
        assert await count_course_cover_assets(course_id) == before_count
    finally:
        await cleanup_user(user_id)


async def test_cover_from_lesson_media_rejects_missing_storage_object(
    async_client, monkeypatch
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        lesson_id = await create_lesson(async_client, headers, course_id)

        async def fake_fetch_storage_object_existence(pairs):
            return {tuple(pair): False for pair in pairs}, True

        monkeypatch.setattr(
            api_media.storage_objects,
            "fetch_storage_object_existence",
            fake_fetch_storage_object_existence,
            raising=True,
        )

        media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="image",
            storage_path="demo/missing-cover.png",
            storage_bucket=storage_module.storage_service.bucket,
            media_id=None,
            media_asset_id=None,
            position=1,
            duration_seconds=None,
        )
        assert media

        before_count = await count_course_cover_assets(course_id)
        resp = await async_client.post(
            "/api/media/cover-from-media",
            headers=headers,
            json={
                "course_id": course_id,
                "lesson_media_id": str(media["id"]),
            },
        )
        assert resp.status_code == 400, resp.text
        assert resp.json()["detail"] == "Cover source object is missing from storage"
        assert await count_course_cover_assets(course_id) == before_count
    finally:
        await cleanup_user(user_id)


async def test_cover_clear_deletes_assets(async_client, monkeypatch):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)

        source_path = f"media/source/cover/courses/{course_id}/demo.jpg"
        derived_path = f"media/derived/cover/courses/{course_id}/demo.jpg"

        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="jpeg",
            original_object_path=source_path,
            original_content_type="image/jpeg",
            original_filename="demo.jpg",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert asset

        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(asset["id"]),
            streaming_object_path=derived_path,
            streaming_format="jpg",
            streaming_storage_bucket=storage_module.public_storage_service.bucket,
            public_url=f"https://public.local/{derived_path}",
            codec="jpeg",
        )

        calls: list[tuple[str, str]] = []

        async def fake_delete_object(self, path):
            calls.append((self.bucket, path))
            return True

        monkeypatch.setattr(
            storage_module.StorageService,
            "delete_object",
            fake_delete_object,
            raising=True,
        )

        resp = await async_client.post(
            "/api/media/cover-clear",
            headers=headers,
            json={"course_id": course_id},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json() == {"ok": True}

        meta = await async_client.get(
            f"/studio/courses/{course_id}",
            headers=headers,
        )
        assert meta.status_code == 200, meta.text
        meta_json = meta.json()
        assert meta_json.get("cover_media_id") is None
        assert meta_json.get("cover_url") is None

        assert await media_assets_repo.get_media_asset(str(asset["id"])) is None

        assert (storage_module.storage_service.bucket, source_path) in calls
        assert (storage_module.public_storage_service.bucket, derived_path) in calls
    finally:
        await cleanup_user(user_id)


async def test_prune_course_cover_assets_skips_shared_lesson_storage(
    async_client, monkeypatch, caplog
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        lesson_id = await create_lesson(async_client, headers, course_id)
        lesson_storage_path = f"lessons/{lesson_id}/images/shared-cover.png"
        old_derived_path = f"media/derived/cover/courses/{course_id}/old.jpg"
        new_source_path = f"media/source/cover/courses/{course_id}/fresh.png"
        new_derived_path = f"media/derived/cover/courses/{course_id}/fresh.jpg"

        lesson_media = await models.add_lesson_media_entry(
            lesson_id=lesson_id,
            kind="image",
            storage_path=lesson_storage_path,
            storage_bucket=storage_module.public_storage_service.bucket,
            media_id=None,
            media_asset_id=None,
            position=1,
            duration_seconds=None,
        )
        assert lesson_media

        old_asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="png",
            original_object_path=lesson_storage_path,
            original_content_type="image/png",
            original_filename="shared-cover.png",
            original_size_bytes=1024,
            storage_bucket=storage_module.public_storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert old_asset
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(old_asset["id"]),
            streaming_object_path=old_derived_path,
            streaming_format="jpg",
            streaming_storage_bucket=storage_module.public_storage_service.bucket,
            codec="jpeg",
        )

        new_asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="png",
            original_object_path=new_source_path,
            original_content_type="image/png",
            original_filename="fresh.png",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert new_asset
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(new_asset["id"]),
            streaming_object_path=new_derived_path,
            streaming_format="jpg",
            streaming_storage_bucket=storage_module.public_storage_service.bucket,
            codec="jpeg",
        )

        calls: list[tuple[str, str]] = []

        async def fake_delete_object(self, path):
            calls.append((self.bucket, path))
            return True

        monkeypatch.setattr(
            storage_module.StorageService,
            "delete_object",
            fake_delete_object,
            raising=True,
        )

        with caplog.at_level(logging.INFO):
            deleted_count = await media_cleanup.prune_course_cover_assets(
                course_id=course_id
            )

        assert deleted_count == 1
        assert await media_assets_repo.get_media_asset(str(old_asset["id"])) is None
        assert await media_assets_repo.get_media_asset(str(new_asset["id"])) is not None
        assert await models.get_media(str(lesson_media["id"])) is not None
        assert (
            storage_module.public_storage_service.bucket,
            lesson_storage_path,
        ) not in calls
        assert (
            storage_module.public_storage_service.bucket,
            old_derived_path,
        ) in calls
        assert "MEDIA_CLEANUP_SHARED_STORAGE_DETECTED" in caplog.text
        assert "MEDIA_CLEANUP_DELETE_SKIPPED_SHARED_REFERENCE" in caplog.text
        assert "lesson_storage_prefix" in caplog.text
        assert "lesson_media=1" in caplog.text
    finally:
        await cleanup_user(user_id)


async def test_delete_media_asset_and_objects_skips_shared_media_object_storage(
    async_client, monkeypatch, caplog
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        shared_storage_path = f"media/source/cover/courses/{course_id}/shared-object.png"
        media_object = await models.create_media_object(
            owner_id=user_id,
            storage_path=shared_storage_path,
            storage_bucket=storage_module.storage_service.bucket,
            content_type="image/png",
            byte_size=128,
            checksum=None,
            original_name="shared-object.png",
        )
        assert media_object

        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="png",
            original_object_path=shared_storage_path,
            original_content_type="image/png",
            original_filename="shared-object.png",
            original_size_bytes=128,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert asset

        calls: list[tuple[str, str]] = []

        async def fake_delete_object(self, path):
            calls.append((self.bucket, path))
            return True

        monkeypatch.setattr(
            storage_module.StorageService,
            "delete_object",
            fake_delete_object,
            raising=True,
        )

        with caplog.at_level(logging.INFO):
            deleted = await media_cleanup.delete_media_asset_and_objects(
                media_id=str(asset["id"])
            )

        assert deleted is True
        assert await media_assets_repo.get_media_asset(str(asset["id"])) is None
        assert await models.get_media_object(str(media_object["id"])) is not None
        assert (
            storage_module.storage_service.bucket,
            shared_storage_path,
        ) not in calls
        assert "MEDIA_CLEANUP_SHARED_STORAGE_DETECTED" in caplog.text
        assert "MEDIA_CLEANUP_DELETE_SKIPPED_SHARED_REFERENCE" in caplog.text
        assert "media_objects=1" in caplog.text
    finally:
        await cleanup_user(user_id)


async def test_studio_course_update_persists_cover_media_id(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)

        source_path = f"media/source/cover/courses/{course_id}/persisted.jpg"
        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="jpeg",
            original_object_path=source_path,
            original_content_type="image/jpeg",
            original_filename="persisted.jpg",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert asset

        resp = await async_client.patch(
            f"/studio/courses/{course_id}",
            headers=headers,
            json={"cover_media_id": str(asset["id"])},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["cover_media_id"] == str(asset["id"])

        meta = await get_course_cover_fields(course_id)
        assert meta.get("cover_media_id") == str(asset["id"])
        assert meta.get("cover_url") is None
    finally:
        await cleanup_user(user_id)


async def test_worker_promotion_updates_cover_media_id_without_touching_cover_url(
    async_client, caplog
):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        legacy_cover_url = "/api/files/public-media/courses/legacy-cover.jpg"
        await set_course_cover_url(course_id, legacy_cover_url)

        source_path = f"media/source/cover/courses/{course_id}/demo.jpg"
        derived_path = f"media/derived/cover/courses/{course_id}/demo.jpg"
        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="jpeg",
            original_object_path=source_path,
            original_content_type="image/jpeg",
            original_filename="demo.jpg",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert asset

        with caplog.at_level(logging.WARNING):
            result = await media_assets_repo.mark_course_cover_ready_from_worker(
                media_id=str(asset["id"]),
                streaming_object_path=derived_path,
                streaming_format="jpg",
                streaming_storage_bucket=storage_module.public_storage_service.bucket,
                public_url=f"https://public.local/{derived_path}",
                codec="jpeg",
            )

        assert result["updated"] is True
        assert result["cover_applied"] is True
        meta = await get_course_cover_fields(course_id)
        assert meta.get("cover_media_id") == str(asset["id"])
        assert meta.get("cover_url") == legacy_cover_url
        assert "COURSE_COVER_LEGACY_URL_WRITE_IGNORED" in caplog.text
    finally:
        await cleanup_user(user_id)


async def test_worker_promotion_is_idempotent_for_cover_media_id(async_client):
    headers, user_id = await register_teacher(async_client)
    try:
        course_id = await create_course(async_client, headers)
        legacy_cover_url = "/api/files/public-media/courses/legacy-cover.jpg"
        await set_course_cover_url(course_id, legacy_cover_url)

        source_path = f"media/source/cover/courses/{course_id}/demo.jpg"
        derived_path = f"media/derived/cover/courses/{course_id}/demo.jpg"
        asset = await media_assets_repo.create_media_asset(
            owner_id=user_id,
            course_id=course_id,
            lesson_id=None,
            media_type="image",
            purpose="course_cover",
            ingest_format="jpeg",
            original_object_path=source_path,
            original_content_type="image/jpeg",
            original_filename="demo.jpg",
            original_size_bytes=1024,
            storage_bucket=storage_module.storage_service.bucket,
            state="uploaded",
            allow_uploaded_state=True,
        )
        assert asset

        first = await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(asset["id"]),
            streaming_object_path=derived_path,
            streaming_format="jpg",
            streaming_storage_bucket=storage_module.public_storage_service.bucket,
            codec="jpeg",
        )
        second = await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(asset["id"]),
            streaming_object_path=derived_path,
            streaming_format="jpg",
            streaming_storage_bucket=storage_module.public_storage_service.bucket,
            codec="jpeg",
        )

        assert first["cover_applied"] is True
        assert second["cover_applied"] is True
        meta = await get_course_cover_fields(course_id)
        assert meta.get("cover_media_id") == str(asset["id"])
        assert meta.get("cover_url") == legacy_cover_url
    finally:
        await cleanup_user(user_id)
