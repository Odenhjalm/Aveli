from __future__ import annotations

from fastapi.routing import APIRoute
import pytest

from app.main import app
from app.routes import courses as course_routes


pytestmark = pytest.mark.anyio("asyncio")


COURSES_PREFIX = "/courses"
ENTRY_SUFFIX = "/entry-view"
COURSE_SLUG = "course-entry"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"


def _entry_route_path() -> str:
    return f"{COURSES_PREFIX}/{{course_id_or_slug}}{ENTRY_SUFFIX}"


def _entry_url() -> str:
    return f"{COURSES_PREFIX}/{COURSE_SLUG}{ENTRY_SUFFIX}"


def _entry_response() -> course_routes.schemas.CourseEntryViewResponse:
    return course_routes.schemas.CourseEntryViewResponse(
        course=course_routes.schemas.CourseEntryCourse(
            id=COURSE_ID,
            slug=COURSE_SLUG,
            title="Course Entry",
            description="Backend-authored course description.",
            cover=None,
            required_enrollment_source="intro",
            is_premium=False,
            price_amount_cents=None,
            price_currency=None,
            formatted_price=None,
            sellable=False,
        ),
        lessons=[
            course_routes.schemas.CourseEntryLessonShell(
                id=LESSON_ID,
                lesson_title="Lesson 1",
                position=1,
                availability=course_routes.schemas.CourseEntryLessonAvailability(
                    state="locked",
                    can_open=False,
                    reason_code="not_enrolled",
                    reason_text="Enrollment is required.",
                    next_unlock_at=None,
                ),
                progression=course_routes.schemas.CourseEntryLessonProgression(
                    state="upcoming",
                    completed_at=None,
                    is_next_recommended=False,
                ),
            )
        ],
        access=course_routes.schemas.CourseEntryAccess(
            is_enrolled=False,
            is_in_drip=False,
            is_in_any_intro_drip=False,
            can_enroll=True,
            can_purchase=False,
        ),
        cta=course_routes.schemas.CourseEntryCTA(
            type="enroll",
            label="Enroll",
            enabled=True,
            action={"type": "enroll"},
        ),
        pricing=None,
        next_recommended_lesson=None,
    )


async def test_course_entry_view_route_returns_projection(
    async_client,
    monkeypatch,
) -> None:
    calls: list[tuple[str, object | None]] = []

    async def fake_read_course_entry_view_surface(
        course_id_or_slug: str,
        user_id_or_subject: object | None = None,
    ):
        calls.append((course_id_or_slug, user_id_or_subject))
        return _entry_response()

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_course_entry_view_surface",
        fake_read_course_entry_view_surface,
        raising=True,
    )

    response = await async_client.get(_entry_url())

    assert response.status_code == 200
    assert calls == [(COURSE_SLUG, None)]
    payload = response.json()
    assert payload["course"]["slug"] == COURSE_SLUG
    assert payload["cta"]["type"] == "enroll"
    assert payload["lessons"][0]["availability"]["state"] == "locked"


async def test_course_entry_view_route_returns_404_when_projection_missing(
    async_client,
    monkeypatch,
) -> None:
    async def fake_read_course_entry_view_surface(
        course_id_or_slug: str,
        user_id_or_subject: object | None = None,
    ):
        return None

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_course_entry_view_surface",
        fake_read_course_entry_view_surface,
        raising=True,
    )

    response = await async_client.get(_entry_url())

    assert response.status_code == 404


async def test_course_entry_view_route_response_excludes_runtime_content_and_media(
    async_client,
    monkeypatch,
) -> None:
    async def fake_read_course_entry_view_surface(
        course_id_or_slug: str,
        user_id_or_subject: object | None = None,
    ):
        return _entry_response()

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_course_entry_view_surface",
        fake_read_course_entry_view_surface,
        raising=True,
    )

    response = await async_client.get(_entry_url())

    assert response.status_code == 200
    payload_text = str(response.json())
    assert "content_document" not in payload_text
    assert "content_markdown" not in payload_text
    assert "lesson_media_id" not in payload_text
    assert "media_id" not in payload_text
    assert "resolved_url" not in payload_text


def test_course_entry_view_route_is_registered_before_generic_course_detail() -> None:
    route_paths = [
        route.path
        for route in app.routes
        if isinstance(route, APIRoute) and "GET" in route.methods
    ]

    assert route_paths.index(_entry_route_path()) < route_paths.index(
        f"{COURSES_PREFIX}/{{course_id}}"
    )
