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
LESSON_DOCUMENT = {
    "schema_version": "lesson_document_v1",
    "blocks": [{"type": "paragraph", "children": [{"text": "Lesson"}]}],
}


def _lesson_view_response(
    *,
    media: list[course_routes.schemas.LessonViewMediaItem] | None = None,
) -> course_routes.schemas.LessonViewResponse:
    return course_routes.schemas.LessonViewResponse(
        lesson=course_routes.schemas.LessonViewLesson(
            id=LESSON_ID,
            course_id=COURSE_ID,
            lesson_title="Lesson",
            position=1,
            content_document=LESSON_DOCUMENT,
        ),
        navigation=course_routes.schemas.LessonViewNavigation(),
        access=course_routes.schemas.LessonViewAccess(
            has_access=True,
            is_enrolled=True,
            is_in_drip=False,
            is_premium=True,
            can_enroll=False,
            can_purchase=False,
        ),
        cta=course_routes.schemas.LessonViewCTA(
            type="continue",
            label="Continue",
            enabled=True,
            action={"type": "continue"},
        ),
        pricing=course_routes.schemas.LessonViewPricing(
            price_amount_cents=12000,
            price_currency="sek",
            formatted="120 SEK",
        ),
        progression=course_routes.schemas.LessonViewProgression(
            unlocked=True,
            reason="available",
        ),
        media=media or [],
    )


async def test_lesson_detail_excludes_non_ready_media(monkeypatch):
    async def _lesson_view_surface(
        lesson_id: str,
        *,
        user_id: str | None = None,
        preview: bool = False,
        teacher_id: str | None = None,
    ):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        assert preview is False
        assert teacher_id is None
        return _lesson_view_response()

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_lesson_view_surface",
        _lesson_view_surface,
        raising=True,
    )

    response = await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert response.media == []


async def test_lesson_detail_returns_ready_resolved_media(monkeypatch):
    async def _lesson_view_surface(
        lesson_id: str,
        *,
        user_id: str | None = None,
        preview: bool = False,
        teacher_id: str | None = None,
    ):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        assert preview is False
        assert teacher_id is None
        return _lesson_view_response(
            media=[
                course_routes.schemas.LessonViewMediaItem(
                    lesson_media_id=LESSON_MEDIA_ID,
                    position=1,
                    media_type="audio",
                    media=course_routes.schemas.LessonViewMedia(
                        media_id=MEDIA_ASSET_ID,
                        state="ready",
                        resolved_url="https://stream.local/lesson.mp3",
                    ),
                )
            ]
        )

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_lesson_view_surface",
        _lesson_view_surface,
        raising=True,
    )

    response = await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert len(response.media) == 1
    item = response.media[0]
    assert item.lesson_media_id == UUID(LESSON_MEDIA_ID)
    assert item.media_type == "audio"
    assert item.media.media_id == MEDIA_ASSET_ID
    assert item.media.state == "ready"
    assert item.media.resolved_url == "https://stream.local/lesson.mp3"


async def test_lesson_detail_maps_service_unavailable_to_safe_error(monkeypatch):
    async def _lesson_view_surface(
        lesson_id: str,
        *,
        user_id: str | None = None,
        preview: bool = False,
        teacher_id: str | None = None,
    ):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        assert preview is False
        assert teacher_id is None
        raise HTTPException(status_code=503, detail="canonical surface unavailable")

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_lesson_view_surface",
        _lesson_view_surface,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert excinfo.value.status_code == 503
    assert excinfo.value.detail == course_routes._LESSON_CONTENT_UNAVAILABLE_DETAIL
    assert "canonical" not in str(excinfo.value.detail).lower()


async def test_lesson_detail_passes_preview_flag_to_service(monkeypatch):
    async def _lesson_view_surface(
        lesson_id: str,
        *,
        user_id: str | None = None,
        preview: bool = False,
        teacher_id: str | None = None,
    ):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        assert preview is True
        assert teacher_id == USER_ID
        return _lesson_view_response()

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_lesson_view_surface",
        _lesson_view_surface,
        raising=True,
    )

    response = await course_routes.lesson_detail(
        LESSON_ID,
        {"id": UUID(USER_ID)},
        preview=True,
    )

    assert response.lesson.id == UUID(LESSON_ID)
