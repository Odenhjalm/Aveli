from __future__ import annotations

from uuid import UUID

import pytest
from fastapi import HTTPException

from app.routes import courses as course_routes


pytestmark = pytest.mark.anyio("asyncio")


USER_ID = "11111111-1111-1111-1111-111111111111"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"
LESSON_MEDIA_ID = "44444444-4444-4444-4444-444444444444"
MEDIA_ASSET_ID = "55555555-5555-5555-5555-555555555555"


async def _allow_lesson_access(user_id: str, lesson_id: str):
    assert user_id == USER_ID
    assert lesson_id == LESSON_ID
    return {
        "lesson": {
            "id": LESSON_ID,
            "course_id": COURSE_ID,
            "lesson_title": "Lesson",
            "position": 1,
        },
        "course": {"id": COURSE_ID},
        "enrollment": {
            "id": "66666666-6666-6666-6666-666666666666",
            "course_id": COURSE_ID,
            "user_id": USER_ID,
            "source": "purchase",
            "current_unlock_position": 1,
        },
        "required_enrollment_source": "purchase",
        "current_unlock_position": 1,
        "can_access": True,
    }


async def _lesson_structure(course_id: str):
    assert course_id == COURSE_ID
    return [
        {
            "id": LESSON_ID,
            "lesson_title": "Lesson",
            "position": 1,
        }
    ]


async def test_lesson_detail_excludes_non_ready_media(monkeypatch):
    async def _protected_content(lesson_id: str, *, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return {
            "lesson": {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": "# Lesson",
            },
            "media": [],
        }

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_canonical_lesson_access",
        _allow_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "read_protected_lesson_content_surface",
        _protected_content,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lesson_structure",
        _lesson_structure,
        raising=True,
    )

    response = await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert response.media == []


async def test_lesson_detail_returns_ready_resolved_media(monkeypatch):
    async def _protected_content(lesson_id: str, *, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return {
            "lesson": {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": "# Lesson",
            },
            "media": [
                {
                    "id": LESSON_MEDIA_ID,
                    "lesson_id": LESSON_ID,
                    "media_asset_id": MEDIA_ASSET_ID,
                    "position": 1,
                    "media_type": "audio",
                    "state": "ready",
                    "media": {
                        "media_id": MEDIA_ASSET_ID,
                        "state": "ready",
                        "resolved_url": "https://stream.local/lesson.mp3",
                    },
                }
            ],
        }

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_canonical_lesson_access",
        _allow_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "read_protected_lesson_content_surface",
        _protected_content,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lesson_structure",
        _lesson_structure,
        raising=True,
    )

    response = await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert len(response.media) == 1
    item = response.media[0]
    assert item.state == "ready"
    assert item.media is not None
    assert item.media.media_id == UUID(MEDIA_ASSET_ID)
    assert item.media.state == "ready"
    assert item.media.resolved_url == "https://stream.local/lesson.mp3"


async def test_lesson_detail_rejects_malformed_protected_lesson(monkeypatch):
    async def _protected_content(lesson_id: str, *, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return {
            "lesson": {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": None,
                "position": 1,
                "content_markdown": "# Lesson",
            },
            "media": [],
        }

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_canonical_lesson_access",
        _allow_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "read_protected_lesson_content_surface",
        _protected_content,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lesson_structure",
        _lesson_structure,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert excinfo.value.status_code == 503
    assert excinfo.value.detail == "Lektionen kunde inte laddas just nu."
    assert "canonical" not in str(excinfo.value.detail).lower()


async def test_lesson_detail_rejects_malformed_structure_row(monkeypatch):
    async def _protected_content(lesson_id: str, *, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return {
            "lesson": {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Lesson",
                "position": 1,
                "content_markdown": "# Lesson",
            },
            "media": [],
        }

    async def _malformed_lesson_structure(course_id: str):
        assert course_id == COURSE_ID
        return [
            {
                "id": LESSON_ID,
                "lesson_title": "",
                "position": 1,
            }
        ]

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_canonical_lesson_access",
        _allow_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "read_protected_lesson_content_surface",
        _protected_content,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lesson_structure",
        _malformed_lesson_structure,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert excinfo.value.status_code == 503
    assert excinfo.value.detail == "Lektionen kunde inte laddas just nu."
    assert "canonical" not in str(excinfo.value.detail).lower()
