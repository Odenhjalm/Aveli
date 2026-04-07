from __future__ import annotations

from pathlib import Path
from uuid import UUID

import pytest
from fastapi import HTTPException

from app.routes import courses as course_routes
from app.services import courses_service

pytestmark = pytest.mark.anyio("asyncio")


USER_ID = "11111111-1111-1111-1111-111111111111"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"


def test_lesson_content_surface_sql_requires_enrollment_and_unlock_only():
    sql = Path("backend/supabase/baseline_slots/0016_lesson_content_surface.sql").read_text()

    assert "from app.course_enrollments as ce" in sql
    assert "l.position <= ce.current_unlock_position" in sql
    assert "request.jwt.claim.sub" in sql
    assert "memberships" not in sql.lower()


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
            "expected_source": "purchase",
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
            "expected_source": "purchase",
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


async def test_lesson_detail_denies_before_media_or_structure_reads(monkeypatch):
    async def fake_read_canonical_lesson_access(user_id: str, lesson_id: str):
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        return {
            "lesson": {
                "id": LESSON_ID,
                "course_id": COURSE_ID,
                "lesson_title": "Locked lesson",
                "position": 2,
                "content_markdown": "# Locked",
            },
            "course": {"id": COURSE_ID},
            "enrollment": {
                "id": "enrollment-1",
                "course_id": COURSE_ID,
                "user_id": USER_ID,
                "source": "purchase",
                "current_unlock_position": 1,
            },
            "expected_source": "purchase",
            "current_unlock_position": 1,
            "can_access": False,
        }

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
        "read_canonical_lesson_access",
        fake_read_canonical_lesson_access,
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

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.lesson_detail(LESSON_ID, {"id": UUID(USER_ID)})

    assert excinfo.value.status_code == 403
