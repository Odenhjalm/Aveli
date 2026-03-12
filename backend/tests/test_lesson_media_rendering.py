import uuid

import pytest

from app import models
from app.repositories import courses as courses_repo
from app.repositories import media_assets as media_assets_repo
from app.services import courses_service
from app.services import storage_service as storage_module


pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(async_client) -> tuple[str, str]:
    password = "Passw0rd!"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": f"lesson_media_{uuid.uuid4().hex[:8]}@example.com",
            "password": password,
            "display_name": "Owner",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    me_resp = await async_client.get("/auth/me", headers=auth_header(tokens["access_token"]))
    assert me_resp.status_code == 200, me_resp.text
    return tokens["access_token"], me_resp.json()["user_id"]


async def test_lesson_detail_includes_processing_pipeline_media(async_client):
    token, owner_id = await register_user(async_client)

    course = await courses_repo.create_course(
        {
            "title": "Published Course",
            "slug": f"published-{uuid.uuid4().hex[:8]}",
            "description": "Course for lesson media rendering tests",
            "created_by": owner_id,
            "is_published": True,
            "price_amount_cents": 1000,
            "currency": "sek",
        }
    )
    course_id = str(course["id"])
    lesson = await courses_repo.create_lesson(
        course_id,
        title="Lesson",
        content_markdown="# Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson
    lesson_id = str(lesson["id"])

    media_asset = await media_assets_repo.create_media_asset(
        owner_id=owner_id,
        course_id=course_id,
        lesson_id=lesson_id,
        media_type="audio",
        purpose="lesson_audio",
        ingest_format="wav",
        original_object_path=f"media/source/audio/courses/{course_id}/lessons/{lesson_id}/demo.wav",
        original_content_type="audio/wav",
        original_filename="demo.wav",
        original_size_bytes=123,
        storage_bucket="course-media",
        state="processing",
    )
    assert media_asset

    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=None,
        storage_bucket="course-media",
        media_id=None,
        media_asset_id=str(media_asset["id"]),
        position=1,
        duration_seconds=None,
    )
    assert lesson_media
    lesson_media_id = str(lesson_media["id"])

    resp = await async_client.get(
        f"/courses/lessons/{lesson_id}",
        headers=auth_header(token),
    )
    assert resp.status_code == 200, resp.text

    media_items = resp.json().get("media") or []
    assert lesson_media_id in {item.get("id") for item in media_items}
    item = next(it for it in media_items if it.get("id") == lesson_media_id)
    assert item.get("media_asset_id") == str(media_asset["id"])
    assert item.get("media_state") == "processing"


async def test_lesson_detail_resolves_audio_playback_url(async_client, monkeypatch):
    token, owner_id = await register_user(async_client)

    course = await courses_repo.create_course(
        {
            "title": "Resolved Audio Course",
            "slug": f"resolved-audio-{uuid.uuid4().hex[:8]}",
            "description": "Course for resolved audio tests",
            "created_by": owner_id,
            "is_published": True,
            "price_amount_cents": 1000,
            "currency": "sek",
        }
    )
    course_id = str(course["id"])
    lesson = await courses_repo.create_lesson(
        course_id,
        title="Resolved Audio Lesson",
        content_markdown="# Lesson",
        position=0,
        is_intro=False,
    )
    assert lesson
    lesson_id = str(lesson["id"])

    derived_path = (
        f"media/derived/audio/courses/{course_id}/lessons/{lesson_id}/resolved.mp3"
    )
    media_object = await models.create_media_object(
        owner_id=owner_id,
        storage_path=derived_path,
        storage_bucket="course-media",
        content_type="audio/mpeg",
        byte_size=321,
        checksum=None,
        original_name="resolved.mp3",
    )
    assert media_object

    lesson_media = await models.add_lesson_media_entry(
        lesson_id=lesson_id,
        kind="audio",
        storage_path=derived_path,
        storage_bucket="course-media",
        media_id=str(media_object["id"]),
        media_asset_id=None,
        position=1,
        duration_seconds=None,
    )
    assert lesson_media

    async def fake_fetch_storage_object_existence(_candidate_pairs):
        return {("course-media", derived_path): True}, True

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
        assert filename == "resolved.mp3"
        return storage_module.PresignedUrl(
            url=f"https://stream.local/course-media/{path}",
            expires_in=3600,
            headers={},
        )

    monkeypatch.setattr(
        courses_service.storage_objects,
        "fetch_storage_object_existence",
        fake_fetch_storage_object_existence,
        raising=True,
    )
    monkeypatch.setattr(
        storage_module.StorageService,
        "get_presigned_url",
        fake_get_presigned_url,
        raising=True,
    )

    resp = await async_client.get(
        f"/courses/lessons/{lesson_id}",
        headers=auth_header(token),
    )
    assert resp.status_code == 200, resp.text

    media_items = resp.json().get("media") or []
    item = next(it for it in media_items if it.get("id") == str(lesson_media["id"]))
    assert item.get("kind") == "audio"
    assert item.get("playback_url") == f"https://stream.local/course-media/{derived_path}"
    assert "storage_path" not in item
    assert "storage_bucket" not in item
