from __future__ import annotations

from uuid import UUID

import pytest

from app.services import intro_course_progression_service


pytestmark = pytest.mark.anyio("asyncio")


INTRO_COURSE_ID_1 = "11111111-1111-1111-1111-111111111111"
INTRO_COURSE_ID_2 = "22222222-2222-2222-2222-222222222222"
PURCHASE_COURSE_ID = "33333333-3333-3333-3333-333333333333"


def _progress_row(
    *,
    enrollment_id: str,
    course_id: str,
    current_unlock_position: int,
    max_lesson_position: int,
    lesson_count: int,
    completed_lesson_count: int,
) -> dict[str, object]:
    return {
        "enrollment_id": UUID(enrollment_id),
        "course_id": UUID(course_id),
        "current_unlock_position": current_unlock_position,
        "max_lesson_position": max_lesson_position,
        "lesson_count": lesson_count,
        "completed_lesson_count": completed_lesson_count,
    }


def _course_row(
    *,
    course_id: str,
    required_enrollment_source: str,
    slug: str,
) -> dict[str, object]:
    return {
        "id": UUID(course_id),
        "slug": slug,
        "title": f"title-{slug}",
        "teacher": {"user_id": "teacher-1", "display_name": "Teacher"},
        "course_group_id": UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        "group_position": 0,
        "cover_media_id": None,
        "cover": None,
        "price_amount_cents": None,
        "drip_enabled": False,
        "drip_interval_days": None,
        "required_enrollment_source": required_enrollment_source,
        "enrollable": required_enrollment_source == "intro_enrollment",
        "purchasable": required_enrollment_source == "purchase",
    }


async def test_read_intro_selection_state_returns_incomplete_drip_and_skips_catalog(
    monkeypatch,
) -> None:
    async def _fake_list_intro_selection_progress_rows(*, user_id: str) -> list[dict[str, object]]:
        assert user_id == "user-1"
        return [
            _progress_row(
                enrollment_id="aaaaaaaa-1111-1111-1111-111111111111",
                course_id=INTRO_COURSE_ID_1,
                current_unlock_position=1,
                max_lesson_position=3,
                lesson_count=3,
                completed_lesson_count=1,
            )
        ]

    async def _fail_list_public_courses(**kwargs):
        del kwargs
        raise AssertionError("catalog must not be read when drip is incomplete")

    monkeypatch.setattr(
        intro_course_progression_service.courses_repo,
        "list_intro_selection_progress_rows",
        _fake_list_intro_selection_progress_rows,
        raising=True,
    )
    monkeypatch.setattr(
        intro_course_progression_service.courses_service,
        "list_public_courses",
        _fail_list_public_courses,
        raising=True,
    )

    result = await intro_course_progression_service.read_intro_selection_state(
        user_id="user-1"
    )

    assert result == {
        "selection_locked": True,
        "selection_lock_reason": "incomplete_drip",
        "eligible_courses": [],
    }


async def test_read_intro_selection_state_returns_incomplete_lesson_completion_when_fully_unlocked_but_incomplete(
    monkeypatch,
) -> None:
    async def _fake_list_intro_selection_progress_rows(*, user_id: str) -> list[dict[str, object]]:
        assert user_id == "user-1"
        return [
            _progress_row(
                enrollment_id="bbbbbbbb-1111-1111-1111-111111111111",
                course_id=INTRO_COURSE_ID_1,
                current_unlock_position=3,
                max_lesson_position=3,
                lesson_count=3,
                completed_lesson_count=2,
            )
        ]

    async def _fail_list_public_courses(**kwargs):
        del kwargs
        raise AssertionError("catalog must not be read when completion is incomplete")

    monkeypatch.setattr(
        intro_course_progression_service.courses_repo,
        "list_intro_selection_progress_rows",
        _fake_list_intro_selection_progress_rows,
        raising=True,
    )
    monkeypatch.setattr(
        intro_course_progression_service.courses_service,
        "list_public_courses",
        _fail_list_public_courses,
        raising=True,
    )

    result = await intro_course_progression_service.read_intro_selection_state(
        user_id="user-1"
    )

    assert result == {
        "selection_locked": True,
        "selection_lock_reason": "incomplete_lesson_completion",
        "eligible_courses": [],
    }


async def test_read_intro_selection_state_returns_unlocked_with_filtered_intro_catalog(
    monkeypatch,
) -> None:
    course_rows = [
        _course_row(
            course_id=INTRO_COURSE_ID_2,
            required_enrollment_source="intro_enrollment",
            slug="intro-2",
        ),
        _course_row(
            course_id=PURCHASE_COURSE_ID,
            required_enrollment_source="purchase",
            slug="paid-1",
        ),
    ]

    async def _fake_list_intro_selection_progress_rows(*, user_id: str) -> list[dict[str, object]]:
        assert user_id == "user-1"
        return []

    async def _fake_list_public_courses(
        *,
        search: str | None,
        limit: int | None,
        group_position: int | None,
    ) -> list[dict[str, object]]:
        assert search is None
        assert limit is None
        assert group_position is None
        return course_rows

    monkeypatch.setattr(
        intro_course_progression_service.courses_repo,
        "list_intro_selection_progress_rows",
        _fake_list_intro_selection_progress_rows,
        raising=True,
    )
    monkeypatch.setattr(
        intro_course_progression_service.courses_service,
        "list_public_courses",
        _fake_list_public_courses,
        raising=True,
    )

    result = await intro_course_progression_service.read_intro_selection_state(
        user_id="user-1"
    )

    assert result == {
        "selection_locked": False,
        "selection_lock_reason": None,
        "eligible_courses": [course_rows[0]],
    }


async def test_read_intro_selection_state_excludes_already_enrolled_intro_courses(
    monkeypatch,
) -> None:
    course_rows = [
        _course_row(
            course_id=INTRO_COURSE_ID_1,
            required_enrollment_source="intro_enrollment",
            slug="intro-1",
        ),
        _course_row(
            course_id=INTRO_COURSE_ID_2,
            required_enrollment_source="intro_enrollment",
            slug="intro-2",
        ),
    ]

    async def _fake_list_intro_selection_progress_rows(*, user_id: str) -> list[dict[str, object]]:
        assert user_id == "user-1"
        return [
            _progress_row(
                enrollment_id="cccccccc-1111-1111-1111-111111111111",
                course_id=INTRO_COURSE_ID_1,
                current_unlock_position=3,
                max_lesson_position=3,
                lesson_count=3,
                completed_lesson_count=3,
            )
        ]

    async def _fake_list_public_courses(
        *,
        search: str | None,
        limit: int | None,
        group_position: int | None,
    ) -> list[dict[str, object]]:
        assert search is None
        assert limit is None
        assert group_position is None
        return course_rows

    monkeypatch.setattr(
        intro_course_progression_service.courses_repo,
        "list_intro_selection_progress_rows",
        _fake_list_intro_selection_progress_rows,
        raising=True,
    )
    monkeypatch.setattr(
        intro_course_progression_service.courses_service,
        "list_public_courses",
        _fake_list_public_courses,
        raising=True,
    )

    result = await intro_course_progression_service.read_intro_selection_state(
        user_id="user-1"
    )

    assert result == {
        "selection_locked": False,
        "selection_lock_reason": None,
        "eligible_courses": [course_rows[1]],
    }


async def test_read_intro_selection_state_does_not_lock_when_lesson_count_is_zero(
    monkeypatch,
) -> None:
    async def _fake_list_intro_selection_progress_rows(*, user_id: str) -> list[dict[str, object]]:
        assert user_id == "user-1"
        return [
            _progress_row(
                enrollment_id="dddddddd-1111-1111-1111-111111111111",
                course_id=INTRO_COURSE_ID_1,
                current_unlock_position=0,
                max_lesson_position=0,
                lesson_count=0,
                completed_lesson_count=0,
            )
        ]

    async def _fake_list_public_courses(
        *,
        search: str | None,
        limit: int | None,
        group_position: int | None,
    ) -> list[dict[str, object]]:
        assert search is None
        assert limit is None
        assert group_position is None
        return []

    monkeypatch.setattr(
        intro_course_progression_service.courses_repo,
        "list_intro_selection_progress_rows",
        _fake_list_intro_selection_progress_rows,
        raising=True,
    )
    monkeypatch.setattr(
        intro_course_progression_service.courses_service,
        "list_public_courses",
        _fake_list_public_courses,
        raising=True,
    )

    result = await intro_course_progression_service.read_intro_selection_state(
        user_id="user-1"
    )

    assert result == {
        "selection_locked": False,
        "selection_lock_reason": None,
        "eligible_courses": [],
    }
