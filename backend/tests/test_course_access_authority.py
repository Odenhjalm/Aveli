from __future__ import annotations

from pathlib import Path
from uuid import UUID
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.routes import courses as course_routes
from app.services import courses_service, lesson_playback_service


pytestmark = pytest.mark.anyio("asyncio")


def _course(
    course_id: str = "course-paid",
    *,
    group_position: int = 1,
    price_amount_cents: int | None = 1000,
    sellable: bool | None = None,
) -> dict[str, object]:
    return {
        "id": course_id,
        "group_position": group_position,
        "price_amount_cents": price_amount_cents,
        "sellable": price_amount_cents is not None if sellable is None else sellable,
        "visibility": "public",
    }


def _enrollment(*, source: str, position: int = 1) -> dict[str, object]:
    return {
        "id": "enrollment-1",
        "user_id": "user-1",
        "course_id": "course-paid",
        "source": source,
        "current_unlock_position": position,
    }


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

    assert access["expected_source"] == "purchase"
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
        return _course(course_id or "course-intro", group_position=0, price_amount_cents=None)

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

    access = await courses_service.read_canonical_course_access("user-1", "course-intro")

    assert access["expected_source"] == "intro_enrollment"
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
        return _course(course_id or "course-intro", group_position=0, price_amount_cents=None)

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

    access = await courses_service.read_canonical_course_access("user-1", "course-intro")

    assert access["expected_source"] == "intro_enrollment"
    assert access["enrollment"]["source"] == "intro_enrollment"
    assert access["can_access"] is True


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

    assert access["expected_source"] == "purchase"
    assert access["enrollment"]["source"] == "intro_enrollment"
    assert access["can_access"] is False


async def test_create_intro_course_enrollment_uses_intro_enrollment_source(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(course_id or "course-intro", group_position=0, price_amount_cents=None)

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
    assert state["enrollable"] is True
    assert state["purchasable"] is False
    assert state["enrollment"]["source"] == "intro_enrollment"


async def test_create_intro_course_enrollment_rejects_non_intro_course(
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


async def test_sellable_group_position_zero_is_purchasable_not_auto_enrollable(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-paid-intro-position",
            group_position=0,
            price_amount_cents=1000,
            sellable=True,
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


async def test_priced_unsellable_course_is_not_actionable_for_access(
    monkeypatch,
) -> None:
    async def _fake_fetch_course(*, course_id=None, slug=None):
        del slug
        return _course(
            course_id or "course-priced-unsellable",
            group_position=1,
            price_amount_cents=1000,
            sellable=False,
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

    assert access["expected_source"] is None
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
            "expected_source": "purchase",
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
            "course": _course("course-intro", group_position=0, price_amount_cents=None),
            "enrollment": _enrollment(source="intro_enrollment"),
            "expected_source": "intro_enrollment",
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
