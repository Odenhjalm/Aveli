from datetime import datetime, timedelta, timezone
import uuid

import pytest
from fastapi import HTTPException

from app.services import courses_service

pytestmark = pytest.mark.anyio("asyncio")


def _source_timestamp(*, minutes_ago: int = 0) -> datetime:
    return datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)


async def test_courses_service_home_audio_returns_backend_authored_media(
    monkeypatch,
):
    teacher_id = str(uuid.uuid4())
    direct_media_asset_id = str(uuid.uuid4())
    course_link_media_asset_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    course_id = str(uuid.uuid4())

    async def fake_list_direct_uploads(*, limit: int = 100):
        assert limit >= 100
        return [
            {
                "teacher_id": teacher_id,
                "title": "Direct track",
                "created_at": _source_timestamp(minutes_ago=2),
                "teacher_name": "Teacher",
                "media_asset_id": direct_media_asset_id,
                "media_state": "ready",
            }
        ]

    async def fake_list_course_links(*, limit: int = 100):
        assert limit >= 100
        return [
            {
                "teacher_id": teacher_id,
                "title": "Course track",
                "created_at": _source_timestamp(minutes_ago=1),
                "teacher_name": "Teacher",
                "lesson_id": lesson_id,
                "course_id": course_id,
                "lesson_title": "Lesson",
                "course_title": "Course",
                "course_slug": "course",
                "media_asset_id": course_link_media_asset_id,
                "media_state": "uploaded",
            }
        ]

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert user_id == teacher_id
        assert candidate_lesson_id == lesson_id
        return {"lesson": {"id": lesson_id}, "can_access": True}

    async def fake_resolve_media_asset_playback(*, media_asset_id: str):
        assert media_asset_id == direct_media_asset_id
        return {"resolved_url": "https://stream.local/direct-track.mp3"}

    monkeypatch.setattr(
        courses_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_lesson_access",
        fake_read_access,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.lesson_playback_service,
        "resolve_media_asset_playback",
        fake_resolve_media_asset_playback,
        raising=True,
    )

    items = list(await courses_service.list_home_audio_media(teacher_id, limit=10))

    assert [item["source_type"] for item in items] == ["course_link", "direct_upload"]

    course_link_item = items[0]
    assert course_link_item["media"] == {
        "media_id": course_link_media_asset_id,
        "state": "uploaded",
        "resolved_url": None,
    }
    assert course_link_item["lesson_title"] == "Lesson"
    assert course_link_item["course_id"] == course_id
    assert course_link_item["course_title"] == "Course"
    assert course_link_item["course_slug"] == "course"

    direct_upload_item = items[1]
    assert direct_upload_item["media"] == {
        "media_id": direct_media_asset_id,
        "state": "ready",
        "resolved_url": "https://stream.local/direct-track.mp3",
    }
    assert direct_upload_item["lesson_title"] is None
    assert direct_upload_item["course_id"] is None
    assert direct_upload_item["course_title"] is None
    assert direct_upload_item["course_slug"] is None


async def test_courses_service_home_audio_filters_invalid_ready_items(monkeypatch):
    teacher_id = str(uuid.uuid4())
    good_media_asset_id = str(uuid.uuid4())
    bad_media_asset_id = str(uuid.uuid4())

    async def fake_list_direct_uploads(*, limit: int = 100):
        return [
            {
                "teacher_id": teacher_id,
                "title": "Good ready",
                "created_at": _source_timestamp(minutes_ago=2),
                "teacher_name": "Teacher",
                "media_asset_id": good_media_asset_id,
                "media_state": "ready",
            },
            {
                "teacher_id": teacher_id,
                "title": "Bad ready",
                "created_at": _source_timestamp(minutes_ago=1),
                "teacher_name": "Teacher",
                "media_asset_id": bad_media_asset_id,
                "media_state": "ready",
            },
        ]

    async def fake_list_course_links(*, limit: int = 100):
        return []

    async def fake_resolve_media_asset_playback(*, media_asset_id: str):
        if media_asset_id == good_media_asset_id:
            return {"resolved_url": "https://stream.local/good.mp3"}
        raise HTTPException(status_code=503, detail="Streaming asset unavailable")

    monkeypatch.setattr(
        courses_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.lesson_playback_service,
        "resolve_media_asset_playback",
        fake_resolve_media_asset_playback,
        raising=True,
    )

    items = list(await courses_service.list_home_audio_media(teacher_id, limit=10))

    assert len(items) == 1
    assert items[0]["media"] == {
        "media_id": good_media_asset_id,
        "state": "ready",
        "resolved_url": "https://stream.local/good.mp3",
    }


async def test_courses_service_home_audio_requires_canonical_lesson_access(monkeypatch):
    teacher_id = str(uuid.uuid4())
    other_user_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    media_asset_id = str(uuid.uuid4())

    async def fake_list_direct_uploads(*, limit: int = 100):
        return []

    async def fake_list_course_links(*, limit: int = 100):
        return [
            {
                "teacher_id": teacher_id,
                "title": "Course track",
                "created_at": _source_timestamp(minutes_ago=1),
                "teacher_name": "Teacher",
                "lesson_id": lesson_id,
                "course_id": str(uuid.uuid4()),
                "lesson_title": "Lesson",
                "course_title": "Course",
                "course_slug": "course",
                "media_asset_id": media_asset_id,
                "media_state": "processing",
            }
        ]

    async def fake_read_access(user_id: str, candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return {"lesson": {"id": lesson_id}, "can_access": user_id == teacher_id}

    monkeypatch.setattr(
        courses_service.home_audio_runtime_repo,
        "list_home_audio_direct_upload_sources",
        fake_list_direct_uploads,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.home_audio_runtime_repo,
        "list_home_audio_course_link_sources",
        fake_list_course_links,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_lesson_access",
        fake_read_access,
        raising=True,
    )

    teacher_items = list(await courses_service.list_home_audio_media(teacher_id, limit=10))
    other_items = list(await courses_service.list_home_audio_media(other_user_id, limit=10))

    assert len(teacher_items) == 1
    assert teacher_items[0]["media"] == {
        "media_id": media_asset_id,
        "state": "processing",
        "resolved_url": None,
    }
    assert other_items == []
