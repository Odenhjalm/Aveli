from __future__ import annotations

import json
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
EMPTY_DOCUMENT = {"schema_version": "lesson_document_v1", "blocks": []}


def _json_payload(response) -> dict:
    return json.loads(response.body.decode("utf-8"))


def _document_with_text(text: str) -> dict[str, object]:
    return {
        "schema_version": "lesson_document_v1",
        "blocks": [{"type": "paragraph", "children": [{"text": text}]}],
    }


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
                "content_document": _document_with_text("Surface content"),
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
    assert result["lesson"]["content_document"] == _document_with_text(
        "Surface content"
    )
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
                "content_document": _document_with_text("Surface content"),
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
    assert result["lesson"]["content_document"] == _document_with_text(
        "Surface content"
    )
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
                "content_document": EMPTY_DOCUMENT,
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
    assert result["lesson"]["content_document"] == EMPTY_DOCUMENT
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
                "content_document": _document_with_text("Surface content"),
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


async def test_lesson_detail_uses_lesson_view_surface_projection(monkeypatch):
    async def _fake_lesson_view_surface(
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
        return course_routes.schemas.LessonViewResponse(
            lesson=course_routes.schemas.LessonViewLesson(
                id=LESSON_ID,
                course_id=COURSE_ID,
                lesson_title="Lesson",
                position=1,
                content_document=_document_with_text("Surface content"),
            ),
            navigation=course_routes.schemas.LessonViewNavigation(
                previous_lesson_id=None,
                next_lesson_id=None,
            ),
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
                label="lesson.cta.continue",
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
            media=[],
        )

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
        "read_lesson_view_surface",
        _fake_lesson_view_surface,
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

    payload = _json_payload(response)
    assert payload["lesson"]["content_document"] == _document_with_text(
        "Surface content"
    )
    assert payload["lesson"]["course_id"] == COURSE_ID
    assert payload["access"]["has_access"] is True
    assert payload["navigation"]["previous_lesson_id"] is None
    assert payload["navigation"]["next_lesson_id"] is None
    assert payload["media"] == []
    assert payload["cta"]["text_id"] == "lesson.cta.continue"
    assert "label" not in payload["cta"]
    assert "text_bundle" not in payload
