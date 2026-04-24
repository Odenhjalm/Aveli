from __future__ import annotations

import inspect
from pathlib import Path
from unittest.mock import AsyncMock
from uuid import UUID

import pytest
from fastapi import HTTPException
from psycopg import Error as PsycopgError

from app.routes import courses as course_routes
from app.services import courses_service, lesson_playback_service


pytestmark = pytest.mark.anyio("asyncio")


def _course(
    course_id: str = "course-paid",
    *,
    group_position: int = 1,
    price_amount_cents: int | None = 1000,
    sellable: bool | None = None,
    required_enrollment_source: str | None = "purchase",
) -> dict[str, object]:
    return {
        "id": course_id,
        "group_position": group_position,
        "price_amount_cents": price_amount_cents,
        "sellable": price_amount_cents is not None if sellable is None else sellable,
        "required_enrollment_source": required_enrollment_source,
        "visibility": "public",
    }


def _enrollment(
    *,
    source: str,
    position: int = 1,
    next_unlock_at: str | None = None,
) -> dict[str, object]:
    enrollment = {
        "id": "enrollment-1",
        "user_id": "user-1",
        "course_id": "course-paid",
        "source": source,
        "granted_at": "2026-01-01T00:00:00Z",
        "drip_started_at": "2026-01-01T00:00:00Z",
        "current_unlock_position": position,
    }
    if next_unlock_at is not None:
        enrollment["next_unlock_at"] = next_unlock_at
    return enrollment


class _FakeDiag:
    def __init__(self, message_primary: str | None = None) -> None:
        self.message_primary = message_primary


class _FakePsycopgError(PsycopgError):
    def __init__(self, message: str, *, message_primary: str | None = None) -> None:
        super().__init__(message)
        self._fake_diag = _FakeDiag(message_primary)

    @property
    def diag(self) -> _FakeDiag:
        return self._fake_diag


def test_course_required_source_uses_required_enrollment_source_only() -> None:
    source = inspect.getsource(courses_service._course_required_enrollment_source)

    assert "required_enrollment_source" in source
    assert "price_amount_cents" not in source
    assert "sellable" not in source
    assert "group_position" not in source


async def test_canonical_course_access_denies_paid_course_without_enrollment(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-paid")

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return None

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-paid")

    assert access["required_enrollment_source"] == "purchase"
    assert access["is_intro_course"] is False
    assert access["selection_locked"] is False
    assert access["enrollment"] is None
    assert access["can_access"] is False
    assert courses_service.build_course_access_model(access["course"]) == {
        "required_enrollment_source": "purchase",
        "enrollable": False,
        "purchasable": True,
    }


async def test_canonical_course_access_denies_intro_course_without_intro_enrollment(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return None

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        AsyncMock(
            return_value={
                "selection_locked": False,
                "selection_lock_reason": None,
            }
        ),
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-intro")

    assert access["required_enrollment_source"] == "intro_enrollment"
    assert access["is_intro_course"] is True
    assert access["enrollment"] is None
    assert access["can_access"] is False
    assert courses_service.build_course_access_model(access["course"]) == {
        "required_enrollment_source": "intro_enrollment",
        "enrollable": True,
        "purchasable": False,
    }


async def test_canonical_course_access_allows_intro_only_with_intro_enrollment(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(source="intro_enrollment")

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        AsyncMock(
            return_value={
                "selection_locked": False,
                "selection_lock_reason": None,
            }
        ),
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-intro")

    assert access["required_enrollment_source"] == "intro_enrollment"
    assert access["is_intro_course"] is True
    assert access["enrollment"]["source"] == "intro_enrollment"
    assert access["can_access"] is True


async def test_canonical_course_access_allows_paid_only_with_purchase_enrollment(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-paid")

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(source="purchase")

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-paid")

    assert access["required_enrollment_source"] == "purchase"
    assert access["is_intro_course"] is False
    assert access["selection_locked"] is False
    assert access["enrollment"]["source"] == "purchase"
    assert access["can_access"] is True


async def test_canonical_course_access_projects_next_unlock_at_for_matching_source(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-paid")

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(
            source="purchase",
            next_unlock_at="2026-01-08T00:00:00Z",
        )

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-paid")

    assert access["is_intro_course"] is False
    assert access["selection_locked"] is False
    assert access["can_access"] is True
    assert access["next_unlock_at"] == "2026-01-08T00:00:00Z"
    assert access["enrollment"] is not None
    assert "next_unlock_at" not in access["enrollment"]


async def test_canonical_course_access_denies_wrong_enrollment_source(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-paid")

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(source="intro_enrollment")

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-paid")

    assert access["required_enrollment_source"] == "purchase"
    assert access["is_intro_course"] is False
    assert access["selection_locked"] is False
    assert access["enrollment"]["source"] == "intro_enrollment"
    assert access["can_access"] is False


async def test_read_canonical_course_access_marks_intro_course_and_locked_when_global_intro_lock_is_active(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(source="intro_enrollment")

    async def _fake_read_intro_selection_lock(*, user_id: str):
        assert user_id == "user-1"
        return {
            "selection_locked": True,
            "selection_lock_reason": "incomplete_drip",
        }

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        AsyncMock(
            return_value={
                "selection_locked": False,
                "selection_lock_reason": None,
            }
        ),
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        _fake_read_intro_selection_lock,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-intro")

    assert access["required_enrollment_source"] == "intro_enrollment"
    assert access["is_intro_course"] is True
    assert access["selection_locked"] is True
    assert "selection_lock_reason" not in access
    assert access["can_access"] is True


async def test_read_canonical_course_access_marks_intro_course_and_unlocked_when_global_intro_lock_is_inactive(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(source="intro_enrollment")

    async def _fake_read_intro_selection_lock(*, user_id: str):
        assert user_id == "user-1"
        return {
            "selection_locked": False,
            "selection_lock_reason": None,
        }

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        AsyncMock(
            return_value={
                "selection_locked": False,
                "selection_lock_reason": None,
            }
        ),
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        _fake_read_intro_selection_lock,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-intro")

    assert access["required_enrollment_source"] == "intro_enrollment"
    assert access["is_intro_course"] is True
    assert access["selection_locked"] is False
    assert "selection_lock_reason" not in access
    assert access["can_access"] is True


async def test_read_canonical_course_access_keeps_non_intro_selection_locked_false_even_when_global_intro_lock_is_active(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-paid")

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(source="purchase")

    read_intro_selection_lock = AsyncMock(
        return_value={
            "selection_locked": True,
            "selection_lock_reason": "incomplete_drip",
        }
    )

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        read_intro_selection_lock,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-paid")

    assert access["required_enrollment_source"] == "purchase"
    assert access["is_intro_course"] is False
    assert access["selection_locked"] is False
    assert access["can_access"] is True
    read_intro_selection_lock.assert_not_awaited()


async def test_canonical_course_access_hides_next_unlock_at_for_wrong_source(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-paid")

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(
            source="intro_enrollment",
            next_unlock_at="2026-01-08T00:00:00Z",
        )

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-paid")

    assert access["can_access"] is False
    assert access["next_unlock_at"] is None
    assert access["enrollment"] is not None
    assert "next_unlock_at" not in access["enrollment"]


async def test_canonical_course_access_denies_intro_course_with_purchase_enrollment(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return _enrollment(source="purchase")

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        AsyncMock(
            return_value={
                "selection_locked": False,
                "selection_lock_reason": None,
            }
        ),
        raising=True,
    )

    access = await courses_service.read_canonical_course_access("user-1", "course-intro")

    assert access["required_enrollment_source"] == "intro_enrollment"
    assert access["is_intro_course"] is True
    assert access["selection_locked"] is False
    assert access["enrollment"]["source"] == "purchase"
    assert access["can_access"] is False


async def test_create_intro_course_enrollment_uses_intro_enrollment_source(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    create_course_enrollment = AsyncMock(
        return_value=_enrollment(source="intro_enrollment")
    )

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        create_course_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.intro_selection_state,
        "read_intro_selection_lock",
        AsyncMock(
            return_value={
                "selection_locked": True,
                "selection_lock_reason": "incomplete_drip",
            }
        ),
        raising=True,
    )

    state = await courses_service.create_intro_course_enrollment(
        user_id="user-1",
        course_id="course-intro",
    )

    create_course_enrollment.assert_awaited_once_with(
        user_id="user-1",
        course_id="course-intro",
        source="intro_enrollment",
    )
    assert state["required_enrollment_source"] == "intro_enrollment"
    assert state["is_intro_course"] is True
    assert state["selection_locked"] is True
    assert state["enrollable"] is True
    assert state["purchasable"] is False
    assert state["enrollment"]["source"] == "intro_enrollment"


async def test_create_intro_course_enrollment_purchase_required_behavior_remains_unchanged(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-paid")

    create_course_enrollment = AsyncMock()

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        create_course_enrollment,
        raising=True,
    )

    with pytest.raises(PermissionError, match="purchase enrollment required"):
        await courses_service.create_intro_course_enrollment(
            user_id="user-1",
            course_id="course-paid",
        )

    create_course_enrollment.assert_not_awaited()


async def test_create_intro_course_enrollment_maps_incomplete_drip_sql_failure_to_typed_error(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _raise_incomplete_drip(**kwargs):
        del kwargs
        raise _FakePsycopgError(
            "fallback text should not be used",
            message_primary=(
                "intro course selection locked by incomplete drip for course "
                "course-intro"
            ),
        )

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        _raise_incomplete_drip,
        raising=True,
    )

    with pytest.raises(
        courses_service.IntroCourseSelectionLockedByIncompleteDripError
    ) as excinfo:
        await courses_service.create_intro_course_enrollment(
            user_id="user-1",
            course_id="course-intro",
        )

    assert excinfo.value.reason == "incomplete_drip"
    assert not hasattr(excinfo.value, "course_id")


async def test_create_intro_course_enrollment_maps_incomplete_completion_sql_failure_to_typed_error(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _raise_incomplete_completion(**kwargs):
        del kwargs
        raise _FakePsycopgError(
            "fallback text should not be used",
            message_primary=(
                "intro course selection locked by incomplete lesson completion "
                "for course course-intro"
            ),
        )

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        _raise_incomplete_completion,
        raising=True,
    )

    with pytest.raises(
        courses_service.IntroCourseSelectionLockedByIncompleteLessonCompletionError
    ) as excinfo:
        await courses_service.create_intro_course_enrollment(
            user_id="user-1",
            course_id="course-intro",
        )

    assert excinfo.value.reason == "incomplete_completion"
    assert not hasattr(excinfo.value, "course_id")


async def test_create_intro_course_enrollment_maps_sql_failure_using_str_fallback_when_message_primary_missing(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    async def _raise_incomplete_drip(**kwargs):
        del kwargs
        raise _FakePsycopgError(
            "intro course selection locked by incomplete drip for course course-intro"
        )

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        _raise_incomplete_drip,
        raising=True,
    )

    with pytest.raises(
        courses_service.IntroCourseSelectionLockedByIncompleteDripError
    ) as excinfo:
        await courses_service.create_intro_course_enrollment(
            user_id="user-1",
            course_id="course-intro",
        )

    assert excinfo.value.reason == "incomplete_drip"


async def test_create_intro_course_enrollment_propagates_unrelated_database_error_unchanged(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-intro",
            group_position=0,
            price_amount_cents=None,
            required_enrollment_source="intro_enrollment",
        )

    original_error = _FakePsycopgError(
        "some unrelated enrollment database failure",
        message_primary="some unrelated enrollment database failure",
    )

    async def _raise_unrelated_error(**kwargs):
        del kwargs
        raise original_error

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        _raise_unrelated_error,
        raising=True,
    )

    with pytest.raises(_FakePsycopgError) as excinfo:
        await courses_service.create_intro_course_enrollment(
            user_id="user-1",
            course_id="course-intro",
        )

    assert excinfo.value is original_error


async def test_create_intro_course_enrollment_not_found_behavior_remains_unchanged(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del course_id, slug
        return None

    create_course_enrollment = AsyncMock()

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        create_course_enrollment,
        raising=True,
    )

    with pytest.raises(LookupError, match="course not found"):
        await courses_service.create_intro_course_enrollment(
            user_id="user-1",
            course_id="course-intro",
        )

    create_course_enrollment.assert_not_awaited()


async def test_required_source_purchase_ignores_group_position_and_sellable(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-paid-intro-position",
            group_position=0,
            price_amount_cents=1000,
            sellable=True,
            required_enrollment_source="purchase",
        )

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return None

    create_course_enrollment = AsyncMock()

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course_enrollment",
        create_course_enrollment,
        raising=True,
    )

    state = await courses_service.read_canonical_course_state(
        "user-1",
        "course-paid-intro-position",
    )

    assert state is not None
    assert state["group_position"] == 0
    assert state["required_enrollment_source"] == "purchase"
    assert state["is_intro_course"] is False
    assert state["selection_locked"] is False
    assert state["enrollable"] is False
    assert state["purchasable"] is True

    with pytest.raises(PermissionError, match="purchase enrollment required"):
        await courses_service.create_intro_course_enrollment(
            user_id="user-1",
            course_id="course-paid-intro-position",
        )

    create_course_enrollment.assert_not_awaited()


async def test_enroll_route_maps_purchase_required_to_swedish_safe_error(
    monkeypatch,
) -> None:
    async def _fake_create_intro_course_enrollment(*, user_id: str, course_id: str):
        del user_id, course_id
        raise PermissionError("purchase enrollment required")

    monkeypatch.setattr(
        course_routes.courses_service,
        "create_intro_course_enrollment",
        _fake_create_intro_course_enrollment,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.enroll_course(
            UUID("77777777-7777-7777-7777-777777777777"),
            {"id": UUID("88888888-8888-8888-8888-888888888888")},
        )

    assert excinfo.value.status_code == 403
    assert excinfo.value.detail == "Kursen kräver köp innan du kan fortsätta."
    assert "purchase" not in str(excinfo.value.detail).lower()


async def test_enroll_route_maps_incomplete_drip_selection_lock_to_409(
    monkeypatch,
) -> None:
    async def _fake_create_intro_course_enrollment(*, user_id: str, course_id: str):
        del user_id, course_id
        raise courses_service.IntroCourseSelectionLockedByIncompleteDripError()

    monkeypatch.setattr(
        course_routes.courses_service,
        "create_intro_course_enrollment",
        _fake_create_intro_course_enrollment,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.enroll_course(
            UUID("77777777-7777-7777-7777-777777777777"),
            {"id": UUID("88888888-8888-8888-8888-888888888888")},
        )

    assert excinfo.value.status_code == 409
    assert excinfo.value.detail == {"reason": "incomplete_drip"}


async def test_enroll_route_maps_incomplete_lesson_completion_selection_lock_to_409(
    monkeypatch,
) -> None:
    async def _fake_create_intro_course_enrollment(*, user_id: str, course_id: str):
        del user_id, course_id
        raise (
            courses_service.IntroCourseSelectionLockedByIncompleteLessonCompletionError()
        )

    monkeypatch.setattr(
        course_routes.courses_service,
        "create_intro_course_enrollment",
        _fake_create_intro_course_enrollment,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.enroll_course(
            UUID("77777777-7777-7777-7777-777777777777"),
            {"id": UUID("88888888-8888-8888-8888-888888888888")},
        )

    assert excinfo.value.status_code == 409
    assert excinfo.value.detail == {"reason": "incomplete_lesson_completion"}


async def test_enroll_route_maps_not_found_to_existing_safe_error(
    monkeypatch,
) -> None:
    async def _fake_create_intro_course_enrollment(*, user_id: str, course_id: str):
        del user_id, course_id
        raise LookupError("course not found")

    monkeypatch.setattr(
        course_routes.courses_service,
        "create_intro_course_enrollment",
        _fake_create_intro_course_enrollment,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.enroll_course(
            UUID("77777777-7777-7777-7777-777777777777"),
            {"id": UUID("88888888-8888-8888-8888-888888888888")},
        )

    assert excinfo.value.status_code == 404
    assert excinfo.value.detail == "Kursen kunde inte hittas."


def test_enroll_route_catches_only_typed_selection_lock_errors() -> None:
    source = inspect.getsource(course_routes.enroll_course)

    assert "IntroCourseSelectionLockedByIncompleteDripError" in source
    assert "IntroCourseSelectionLockedByIncompleteLessonCompletionError" in source
    assert "intro course selection locked by incomplete drip" not in source
    assert (
        "intro course selection locked by incomplete lesson completion" not in source
    )
    assert "message_primary" not in source


async def test_course_access_route_projects_backend_can_access(monkeypatch) -> None:
    course_id = UUID("77777777-7777-7777-7777-777777777777")

    async def _fake_read_course_state_or_404(*, user_id: str, course_id: str):
        assert user_id == "88888888-8888-8888-8888-888888888888"
        return {
            "course_id": course_id,
            "group_position": 1,
            "required_enrollment_source": "purchase",
            "is_intro_course": False,
            "selection_locked": False,
            "enrollable": False,
            "purchasable": True,
            "can_access": False,
            "next_unlock_at": None,
            "enrollment": {
                "id": "99999999-9999-9999-9999-999999999999",
                "user_id": "88888888-8888-8888-8888-888888888888",
                "course_id": course_id,
                "source": "intro_enrollment",
                "granted_at": "2026-01-01T00:00:00Z",
                "drip_started_at": "2026-01-01T00:00:00Z",
                "current_unlock_position": 1,
            },
        }

    monkeypatch.setattr(
        course_routes,
        "_read_course_state_or_404",
        _fake_read_course_state_or_404,
        raising=True,
    )

    response = await course_routes.course_access(
        course_id,
        {"id": UUID("88888888-8888-8888-8888-888888888888")},
    )

    assert response.can_access is False
    assert response.next_unlock_at is None
    assert response.enrollment is not None
    assert response.enrollment.source == "intro_enrollment"


async def test_course_access_route_projects_backend_next_unlock_at(monkeypatch) -> None:
    course_id = UUID("77777777-7777-7777-7777-777777777777")

    async def _fake_read_course_state_or_404(*, user_id: str, course_id: str):
        assert user_id == "88888888-8888-8888-8888-888888888888"
        return {
            "course_id": course_id,
            "group_position": 0,
            "required_enrollment_source": "intro_enrollment",
            "is_intro_course": True,
            "selection_locked": False,
            "enrollable": True,
            "purchasable": False,
            "can_access": True,
            "next_unlock_at": "2026-01-08T00:00:00Z",
            "enrollment": {
                "id": "99999999-9999-9999-9999-999999999999",
                "user_id": "88888888-8888-8888-8888-888888888888",
                "course_id": course_id,
                "source": "intro_enrollment",
                "granted_at": "2026-01-01T00:00:00Z",
                "drip_started_at": "2026-01-01T00:00:00Z",
                "current_unlock_position": 1,
            },
        }

    monkeypatch.setattr(
        course_routes,
        "_read_course_state_or_404",
        _fake_read_course_state_or_404,
        raising=True,
    )

    response = await course_routes.course_access(
        course_id,
        {"id": UUID("88888888-8888-8888-8888-888888888888")},
    )

    assert response.can_access is True
    assert response.next_unlock_at is not None
    assert response.next_unlock_at.isoformat() == "2026-01-08T00:00:00+00:00"


async def test_course_access_route_projects_is_intro_course_and_selection_locked(
    monkeypatch,
) -> None:
    course_id = UUID("77777777-7777-7777-7777-777777777777")

    async def _fake_read_course_state_or_404(*, user_id: str, course_id: str):
        assert user_id == "88888888-8888-8888-8888-888888888888"
        return {
            "course_id": course_id,
            "group_position": 0,
            "required_enrollment_source": "intro_enrollment",
            "is_intro_course": True,
            "selection_locked": True,
            "enrollable": True,
            "purchasable": False,
            "can_access": True,
            "next_unlock_at": "2026-01-08T00:00:00Z",
            "enrollment": {
                "id": "99999999-9999-9999-9999-999999999999",
                "user_id": "88888888-8888-8888-8888-888888888888",
                "course_id": course_id,
                "source": "intro_enrollment",
                "granted_at": "2026-01-01T00:00:00Z",
                "drip_started_at": "2026-01-01T00:00:00Z",
                "current_unlock_position": 1,
            },
        }

    monkeypatch.setattr(
        course_routes,
        "_read_course_state_or_404",
        _fake_read_course_state_or_404,
        raising=True,
    )

    response = await course_routes.course_access(
        course_id,
        {"id": UUID("88888888-8888-8888-8888-888888888888")},
    )

    assert response.is_intro_course is True
    assert response.selection_locked is True
    assert not hasattr(response, "selection_lock_reason")
    assert response.can_access is True
    assert response.enrollment is not None
    assert response.enrollment.current_unlock_position == 1


async def test_enrollment_status_route_projects_is_intro_course_and_selection_locked(
    monkeypatch,
) -> None:
    course_id = UUID("77777777-7777-7777-7777-777777777777")

    async def _fake_read_course_state_or_404(*, user_id: str, course_id: str):
        assert user_id == "88888888-8888-8888-8888-888888888888"
        return {
            "course_id": course_id,
            "group_position": 0,
            "required_enrollment_source": "intro_enrollment",
            "is_intro_course": True,
            "selection_locked": False,
            "enrollable": True,
            "purchasable": False,
            "can_access": True,
            "next_unlock_at": "2026-01-08T00:00:00Z",
            "enrollment": {
                "id": "99999999-9999-9999-9999-999999999999",
                "user_id": "88888888-8888-8888-8888-888888888888",
                "course_id": course_id,
                "source": "intro_enrollment",
                "granted_at": "2026-01-01T00:00:00Z",
                "drip_started_at": "2026-01-01T00:00:00Z",
                "current_unlock_position": 1,
            },
        }

    monkeypatch.setattr(
        course_routes,
        "_read_course_state_or_404",
        _fake_read_course_state_or_404,
        raising=True,
    )

    response = await course_routes.enrollment_status(
        course_id,
        {"id": UUID("88888888-8888-8888-8888-888888888888")},
    )

    assert response.is_intro_course is True
    assert response.selection_locked is False
    assert not hasattr(response, "selection_lock_reason")
    assert response.can_access is True
    assert response.next_unlock_at is not None
    assert response.next_unlock_at.isoformat() == "2026-01-08T00:00:00+00:00"


async def test_missing_required_source_fails_closed_even_when_priced_or_sellable(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-priced-unsellable",
            group_position=1,
            price_amount_cents=1000,
            sellable=True,
            required_enrollment_source=None,
        )

    async def _fake_get_enrollment(user_id: str, course_id: str):
        del user_id, course_id
        return None

    monkeypatch.setattr(courses_service, "fetch_course", _fake_fetch_course, raising=True)
    monkeypatch.setattr(
        courses_service,
        "get_course_enrollment",
        _fake_get_enrollment,
        raising=True,
    )

    access = await courses_service.read_canonical_course_access(
        "user-1",
        "course-priced-unsellable",
    )

    assert access["required_enrollment_source"] is None
    assert access["can_access"] is False
    assert courses_service.build_course_access_model(access["course"]) == {
        "required_enrollment_source": None,
        "enrollable": False,
        "purchasable": False,
    }


async def test_lesson_playback_access_does_not_fall_back_to_entitlements(
    monkeypatch,
) -> None:
    async def _fake_read_lesson_access(user_id: str, lesson_id: str):
        del user_id
        return {
            "lesson": {"id": lesson_id, "course_id": "course-paid"},
            "course": _course("course-paid"),
            "enrollment": None,
            "required_enrollment_source": "purchase",
            "current_unlock_position": 0,
            "can_access": False,
        }

    monkeypatch.setattr(
        lesson_playback_service.courses_service,
        "read_canonical_lesson_access",
        _fake_read_lesson_access,
        raising=True,
    )
    assert not hasattr(lesson_playback_service, "entitlement_service")

    with pytest.raises(HTTPException) as excinfo:
        await lesson_playback_service._authorize_lesson_resolution_playback(
            user_id="user-1",
            lesson_id="lesson-1",
            course_id=None,
        )

    assert excinfo.value.status_code == 403


async def test_lesson_playback_access_allows_canonical_lesson_access(
    monkeypatch,
) -> None:
    async def _fake_read_lesson_access(user_id: str, lesson_id: str):
        del user_id
        return {
            "lesson": {"id": lesson_id, "course_id": "course-intro"},
            "course": _course(
                "course-intro",
                group_position=0,
                price_amount_cents=None,
                required_enrollment_source="intro_enrollment",
            ),
            "enrollment": _enrollment(source="intro_enrollment"),
            "required_enrollment_source": "intro_enrollment",
            "current_unlock_position": 1,
            "can_access": True,
        }

    monkeypatch.setattr(
        lesson_playback_service.courses_service,
        "read_canonical_lesson_access",
        _fake_read_lesson_access,
        raising=True,
    )
    assert not hasattr(lesson_playback_service, "entitlement_service")

    await lesson_playback_service._authorize_lesson_resolution_playback(
        user_id="user-1",
        lesson_id="lesson-1",
        course_id=None,
    )


def test_course_access_sources_do_not_import_legacy_entitlements() -> None:
    root = Path(__file__).resolve().parents[1]
    paths = [
        root / "app/services/courses_service.py",
        root / "app/services/lesson_playback_service.py",
        root / "app/routes/courses.py",
        root / "app/routes/playback.py",
    ]
    source = "\n".join(path.read_text(encoding="utf-8") for path in paths)

    assert "entitlement_service" not in source
    assert "app.entitlements" not in source
