from __future__ import annotations

import json
from uuid import UUID

import pytest
from fastapi import HTTPException

from backend.bootstrap import baseline_v2
from app.routes import courses as course_routes
from app.services import courses_service

pytestmark = pytest.mark.anyio("asyncio")


USER_ID = "11111111-1111-1111-1111-111111111111"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"


def _json_payload(response) -> dict:
    return json.loads(response.body.decode("utf-8"))


def test_lesson_content_surface_sql_is_projection_not_access_authority():
    slots: dict[str, str] = {}
    for path in baseline_v2._slot_paths():
        if path.name in {
            "V2_0010_read_projections.sql",
            "V2_0029_lesson_document_content.sql",
        }:
            slots[path.name] = path.read_text(encoding="utf-8")
    sql = slots.get("V2_0010_read_projections.sql", "")
    document_sql = slots.get("V2_0029_lesson_document_content.sql", "")
    assert sql, "Baseline V2 lock does not contain V2_0010_read_projections.sql"
    assert document_sql, "Baseline V2 lock does not contain document content slot"

    assert "create view app.lesson_content_surface" in sql
    assert "content_document" in document_sql
    assert "create view app.lesson_content_surface" in document_sql
    for projection_sql in (sql, document_sql):
        assert "course_enrollments" not in projection_sql
        assert "request.jwt.claim.sub" not in projection_sql
        assert "memberships" not in projection_sql.lower()


async def test_read_canonical_lesson_access_does_not_allow_membership_to_substitute(
    monkeypatch,
):
    async def fake_fetch_lesson(lesson_id: str):
        assert lesson_id == LESSON_ID
        return {
            "id": LESSON_ID,
            "course_id": COURSE_ID,
            "lesson_title": "Locked lesson",
            "position": 2,
            "content_markdown": "# Locked",
        }

    async def fake_read_canonical_course_access(user_id: str, course_id: str):
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        return {
            "course": {"id": COURSE_ID},
            "enrollment": None,
            "required_enrollment_source": "purchase",
            "can_access": False,
        }

    monkeypatch.setattr(
        courses_service,
        "fetch_lesson",
        fake_fetch_lesson,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_course_access",
        fake_read_canonical_course_access,
        raising=True,
    )

    access = await courses_service.read_canonical_lesson_access(USER_ID, LESSON_ID)

    assert access["lesson"]["id"] == LESSON_ID
    assert access["enrollment"] is None
    assert access["current_unlock_position"] == 0
    assert access["can_access"] is False


async def test_read_canonical_lesson_access_respects_current_unlock_position(
    monkeypatch,
):
    async def fake_fetch_lesson(lesson_id: str):
        assert lesson_id == LESSON_ID
        return {
            "id": LESSON_ID,
            "course_id": COURSE_ID,
            "lesson_title": "Lesson 3",
            "position": 3,
            "content_markdown": "# Locked",
        }

    async def fake_read_canonical_course_access(user_id: str, course_id: str):
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        return {
            "course": {"id": COURSE_ID},
            "enrollment": {
                "id": "enrollment-1",
                "course_id": COURSE_ID,
                "user_id": USER_ID,
                "source": "purchase",
                "current_unlock_position": 2,
            },
            "required_enrollment_source": "purchase",
            "can_access": True,
        }

    monkeypatch.setattr(
        courses_service,
        "fetch_lesson",
        fake_fetch_lesson,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_course_access",
        fake_read_canonical_course_access,
        raising=True,
    )

    access = await courses_service.read_canonical_lesson_access(USER_ID, LESSON_ID)

    assert access["enrollment"]["current_unlock_position"] == 2
    assert access["current_unlock_position"] == 2
    assert access["can_access"] is False


async def test_lesson_detail_serializes_locked_view_before_protected_reads(monkeypatch):
    async def fake_read_lesson_view_surface(
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
                lesson_title="Locked lesson",
                position=2,
            ),
            navigation=course_routes.schemas.LessonViewNavigation(),
            access=course_routes.schemas.LessonViewAccess(
                has_access=False,
                is_enrolled=True,
                is_in_drip=True,
                is_premium=True,
                can_enroll=False,
                can_purchase=False,
            ),
            cta=course_routes.schemas.LessonViewCTA(
                type="blocked",
                label="lesson.cta.unavailable",
                enabled=False,
                reason_code="drip",
                reason_text="Lektionen är inte upplåst ännu.",
            ),
            progression=course_routes.schemas.LessonViewProgression(
                unlocked=False,
                reason="drip",
            ),
            media=[],
        )

    async def fail_list_course_lessons(course_id: str):
        raise AssertionError("protected lesson structure must not load before access passes")

    async def fail_list_lesson_media(
        lesson_id: str,
        *,
        mode: str | None = None,
        user_id: str | None = None,
    ):
        raise AssertionError("protected lesson media must not load before access passes")

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_lesson_view_surface",
        fake_read_lesson_view_surface,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lessons",
        fail_list_course_lessons,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_lesson_media",
        fail_list_lesson_media,
        raising=True,
    )

    response = await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    payload = _json_payload(response)
    assert payload["lesson"]["content_document"] is None
    assert payload["media"] == []
    assert payload["progression"] == {"unlocked": False, "reason": "drip"}
    assert payload["cta"]["text_id"] == "lesson.cta.unavailable"
    assert "label" not in payload["cta"]
    assert "text_bundle" not in payload
    assert "lesson_media_id" not in str(payload)
    assert "resolved_url" not in str(payload)


async def test_lesson_detail_missing_lesson_uses_swedish_safe_error(
    monkeypatch,
):
    async def fake_read_lesson_view_surface(
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
        return None

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_lesson_view_surface",
        fake_read_lesson_view_surface,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert excinfo.value.status_code == 404
    assert excinfo.value.detail == course_routes._LESSON_NOT_FOUND_DETAIL
    assert "lesson not found" not in str(excinfo.value.detail).lower()


async def test_lesson_detail_serializes_locked_admin_without_course_enrollment(
    monkeypatch,
):
    async def fake_read_lesson_view_surface(
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
                lesson_title="Admin still needs enrollment",
                position=1,
            ),
            navigation=course_routes.schemas.LessonViewNavigation(),
            access=course_routes.schemas.LessonViewAccess(
                has_access=False,
                is_enrolled=False,
                is_in_drip=False,
                is_premium=True,
                can_enroll=False,
                can_purchase=True,
            ),
            cta=course_routes.schemas.LessonViewCTA(
                type="buy",
                label="lesson.cta.buy",
                enabled=True,
                price={
                    "price_amount_cents": 12000,
                    "price_currency": "sek",
                    "formatted": "120 SEK",
                },
                action={"type": "purchase"},
            ),
            pricing=course_routes.schemas.LessonViewPricing(
                price_amount_cents=12000,
                price_currency="sek",
                formatted="120 SEK",
            ),
            progression=course_routes.schemas.LessonViewProgression(
                unlocked=False,
                reason="no_access",
            ),
            media=[],
        )

    async def fail_list_course_lessons(course_id: str):
        raise AssertionError("admin must not reach protected lesson structure without enrollment")

    async def fail_read_protected_lesson_content_surface(
        lesson_id: str,
        *,
        user_id: str,
    ):
        raise AssertionError("admin must not read protected lesson content without enrollment")

    monkeypatch.setattr(
        course_routes.courses_service,
        "read_lesson_view_surface",
        fake_read_lesson_view_surface,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_course_lessons",
        fail_list_course_lessons,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "read_protected_lesson_content_surface",
        fail_read_protected_lesson_content_surface,
        raising=True,
    )

    response = await course_routes.lesson_detail(
        LESSON_ID,
        {"id": UUID(USER_ID), "role": "admin"},
    )

    payload = _json_payload(response)
    assert payload["lesson"]["content_document"] is None
    assert payload["media"] == []
    assert payload["access"]["can_purchase"] is True
    assert payload["progression"] == {"unlocked": False, "reason": "no_access"}
    assert payload["cta"]["text_id"] == "lesson.cta.buy"
    assert "label" not in payload["cta"]
    assert "text_bundle" not in payload
    assert "lesson_media_id" not in str(payload)
    assert "resolved_url" not in str(payload)


async def test_course_enrollment_cannot_substitute_for_global_app_entry(
    async_client,
    monkeypatch,
):
    from app import auth
    from app.main import app

    async def fake_get_current_user() -> dict[str, object]:
        return {
            "id": USER_ID,
            "email": "learner@example.com",
            "onboarding_state": "completed",
            "role": "learner",
        }

    async def no_membership(_: str) -> None:
        return None

    async def fail_list_my_courses(_: str):
        raise AssertionError("course enrollment state must not run before app-entry")

    app.dependency_overrides[auth.get_current_user] = fake_get_current_user
    monkeypatch.setattr(
        "app.routes.entry_state.memberships_repo.get_membership",
        no_membership,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "list_my_courses",
        fail_list_my_courses,
        raising=True,
    )

    try:
        response = await async_client.get("/courses/me")
    finally:
        app.dependency_overrides.pop(auth.get_current_user, None)

    assert response.status_code == 403
    assert response.json()["detail"] == "canonical_app_entry_required"
