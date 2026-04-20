from __future__ import annotations

from uuid import UUID

import pytest
from fastapi import HTTPException

from app.routes import courses as course_routes
from app.services import courses_service


pytestmark = pytest.mark.anyio("asyncio")


USER_ID = "11111111-1111-1111-1111-111111111111"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"
LESSON_MEDIA_ID = "44444444-4444-4444-4444-444444444444"
MEDIA_ASSET_ID = "55555555-5555-5555-5555-555555555555"


async def test_read_protected_lesson_content_surface_uses_surface_rows_and_runtime_media(
    monkeypatch,
) -> None:
    async def _fake_get_surface_rows(*, lesson_id: str, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return [
            {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": "# Surface content",
                "lesson_media_id": LESSON_MEDIA_ID,
                "media_asset_id": MEDIA_ASSET_ID,
                "lesson_media_position": 3,
            }
        ]

    class _Resolution:
        media_type = "audio"
        media_state = "ready"
        media_asset_id = MEDIA_ASSET_ID
        is_playable = True
        playback_mode = courses_service.LessonMediaPlaybackMode.PIPELINE_ASSET

    async def _fake_resolve_lesson_media(lesson_media_id: str, *, emit_logs: bool = False):
        assert lesson_media_id == LESSON_MEDIA_ID
        assert emit_logs is False
        return _Resolution()

    async def _fake_playback(*, lesson_media_id: str, user_id: str):
        assert lesson_media_id == LESSON_MEDIA_ID
        assert user_id == USER_ID
        return {"resolved_url": "https://stream.local/lesson.mp3"}

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_content_surface_rows",
        _fake_get_surface_rows,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.canonical_media_resolver,
        "resolve_lesson_media",
        _fake_resolve_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.lesson_playback_service,
        "resolve_lesson_media_playback",
        _fake_playback,
        raising=True,
    )

    result = await courses_service.read_protected_lesson_content_surface(
        LESSON_ID,
        user_id=USER_ID,
    )

    assert result is not None
    assert result["lesson"]["content_markdown"] == "# Surface content"
    assert result["media"] == [
        {
            "id": LESSON_MEDIA_ID,
            "lesson_id": LESSON_ID,
            "media_asset_id": MEDIA_ASSET_ID,
            "position": 3,
            "media_type": "audio",
            "state": "ready",
            "media": {
                "media_id": MEDIA_ASSET_ID,
                "state": "ready",
                "resolved_url": "https://stream.local/lesson.mp3",
            },
        }
    ]


async def test_read_protected_lesson_content_surface_filters_non_ready_media(
    monkeypatch,
) -> None:
    async def _fake_get_surface_rows(*, lesson_id: str, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return [
            {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": "# Surface content",
                "lesson_media_id": LESSON_MEDIA_ID,
                "media_asset_id": MEDIA_ASSET_ID,
                "lesson_media_position": 3,
            }
        ]

    class _Resolution:
        media_type = "audio"
        media_state = "processing"
        media_asset_id = MEDIA_ASSET_ID
        is_playable = False
        playback_mode = courses_service.LessonMediaPlaybackMode.NONE

    async def _fake_resolve_lesson_media(lesson_media_id: str, *, emit_logs: bool = False):
        assert lesson_media_id == LESSON_MEDIA_ID
        assert emit_logs is False
        return _Resolution()

    async def _fake_playback(*, lesson_media_id: str, user_id: str):
        raise AssertionError("non-ready media must not be signed")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_content_surface_rows",
        _fake_get_surface_rows,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.canonical_media_resolver,
        "resolve_lesson_media",
        _fake_resolve_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.lesson_playback_service,
        "resolve_lesson_media_playback",
        _fake_playback,
        raising=True,
    )

    result = await courses_service.read_protected_lesson_content_surface(
        LESSON_ID,
        user_id=USER_ID,
    )

    assert result is not None
    assert result["lesson"]["content_markdown"] == "# Surface content"
    assert result["media"] == []


async def test_read_protected_lesson_content_surface_allows_missing_lesson_body(
    monkeypatch,
) -> None:
    async def _fake_get_surface_rows(*, lesson_id: str, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return [
            {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": None,
                "lesson_media_id": None,
                "media_asset_id": None,
                "lesson_media_position": None,
            }
        ]

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_content_surface_rows",
        _fake_get_surface_rows,
        raising=True,
    )

    result = await courses_service.read_protected_lesson_content_surface(
        LESSON_ID,
        user_id=USER_ID,
    )

    assert result is not None
    assert result["lesson"]["content_markdown"] is None
    assert result["media"] == []


async def test_read_protected_lesson_content_surface_rejects_malformed_lesson_row(
    monkeypatch,
) -> None:
    async def _fake_get_surface_rows(*, lesson_id: str, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return [
            {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": None,
                "position": 1,
                "content_markdown": "# Surface content",
                "lesson_media_id": None,
                "media_asset_id": None,
                "lesson_media_position": None,
            }
        ]

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_content_surface_rows",
        _fake_get_surface_rows,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await courses_service.read_protected_lesson_content_surface(
            LESSON_ID,
            user_id=USER_ID,
        )

    assert excinfo.value.status_code == 503


async def test_lesson_detail_uses_surface_based_content_and_structure(monkeypatch):
    async def _fake_access(user_id: str, lesson_id: str):
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        return {
            "lesson": {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": "# Legacy should not win",
            },
            "course": {"id": COURSE_ID},
            "enrollment": {"course_id": COURSE_ID, "user_id": USER_ID},
            "required_enrollment_source": "purchase",
            "current_unlock_position": 1,
            "can_access": True,
        }

    async def _fake_protected_content(lesson_id: str, *, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return {
            "lesson": {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": "# Surface content",
            },
            "media": [],
        }

    async def _fake_structure(course_id: str):
        assert course_id == COURSE_ID
        return [
            {
                "id": LESSON_ID,
                "lesson_title": "Lesson",
                "position": 1,
            }
        ]

    async def _fail_raw_lessons(course_id: str):
        raise AssertionError("raw list_course_lessons must not back mounted lesson reads")

    async def _fail_raw_media(
        lesson_id: str,
        *,
        mode: str | None = None,
        user_id: str | None = None,
    ):
        raise AssertionError("raw list_lesson_media must not back mounted lesson reads")

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_canonical_lesson_access",
        _fake_access,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "read_protected_lesson_content_surface",
        _fake_protected_content,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lesson_structure",
        _fake_structure,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lessons",
        _fail_raw_lessons,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_lesson_media",
        _fail_raw_media,
        raising=True,
    )

    response = await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert response.lesson.content_markdown == "# Surface content"
    assert response.course_id == UUID(COURSE_ID)
    assert len(response.lessons) == 1
    assert response.media == []
