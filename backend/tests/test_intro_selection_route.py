from __future__ import annotations

import inspect

import pytest

from app import auth, schemas
from app.main import app
from app.routes import courses as course_routes


pytestmark = pytest.mark.anyio("asyncio")

USER_ID = "11111111-1111-1111-1111-111111111111"
INTRO_COURSE_ID = "22222222-2222-2222-2222-222222222222"
SECOND_INTRO_COURSE_ID = "33333333-3333-3333-3333-333333333333"


@pytest.fixture(autouse=True)
def _clear_dependency_overrides():
    yield
    app.dependency_overrides.clear()


def _current_user() -> dict[str, object]:
    return {
        "id": USER_ID,
        "email": "learner@example.com",
        "onboarding_state": "completed",
        "role": "learner",
    }


async def _override_current_user() -> None:
    async def _fake_get_current_user() -> dict[str, object]:
        return _current_user()

    app.dependency_overrides[auth.get_current_user] = _fake_get_current_user


async def _allow_app_entry(monkeypatch) -> None:
    async def _active_membership(_: str) -> dict[str, object]:
        return {"status": "active", "expires_at": None}

    monkeypatch.setattr(
        "app.routes.entry_state.memberships_repo.get_membership",
        _active_membership,
    )


async def _deny_app_entry(monkeypatch) -> None:
    async def _no_membership(_: str) -> None:
        return None

    monkeypatch.setattr(
        "app.routes.entry_state.memberships_repo.get_membership",
        _no_membership,
    )


def _course_payload(*, course_id: str, slug: str) -> dict[str, object]:
    return {
        "id": course_id,
        "slug": slug,
        "title": f"title-{slug}",
        "teacher": {
            "user_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "display_name": "Teacher",
        },
        "course_group_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "group_position": 0,
        "cover_media_id": None,
        "cover": None,
        "price_amount_cents": None,
        "drip_enabled": False,
        "drip_interval_days": None,
        "required_enrollment_source": "intro",
        "enrollable": True,
        "purchasable": False,
        "description": f"description-{slug}",
        "extra_field": "must-not-leak",
    }


async def test_intro_selection_route_returns_unlocked_state_with_course_payloads(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    calls: list[str] = []
    service_result = {
        "selection_locked": False,
        "selection_lock_reason": None,
        "eligible_courses": [
            _course_payload(course_id=INTRO_COURSE_ID, slug="intro-1"),
            _course_payload(course_id=SECOND_INTRO_COURSE_ID, slug="intro-2"),
        ],
    }

    async def _fake_read_intro_selection_state(*, user_id: str) -> dict[str, object]:
        calls.append(user_id)
        return service_result

    monkeypatch.setattr(
        course_routes.intro_course_progression_service,
        "read_intro_selection_state",
        _fake_read_intro_selection_state,
        raising=True,
    )

    response = await async_client.get("/courses/intro-selection")

    assert response.status_code == 200, response.text
    assert response.json() == schemas.IntroSelectionStateResponse(
        selection_locked=False,
        selection_lock_reason=None,
        eligible_courses=[
            course_routes._course_list_item_response(row)
            for row in service_result["eligible_courses"]
        ],
    ).model_dump(mode="json")
    assert "extra_field" not in response.json()["eligible_courses"][0]
    assert calls == [USER_ID]


async def test_intro_selection_route_returns_incomplete_drip_lock(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    async def _fake_read_intro_selection_state(*, user_id: str) -> dict[str, object]:
        assert user_id == USER_ID
        return {
            "selection_locked": True,
            "selection_lock_reason": "incomplete_drip",
            "eligible_courses": [],
        }

    monkeypatch.setattr(
        course_routes.intro_course_progression_service,
        "read_intro_selection_state",
        _fake_read_intro_selection_state,
        raising=True,
    )

    response = await async_client.get("/courses/intro-selection")

    assert response.status_code == 200, response.text
    assert response.json() == {
        "selection_locked": True,
        "selection_lock_reason": "incomplete_drip",
        "eligible_courses": [],
    }


async def test_intro_selection_route_returns_incomplete_lesson_completion_lock(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    async def _fake_read_intro_selection_state(*, user_id: str) -> dict[str, object]:
        assert user_id == USER_ID
        return {
            "selection_locked": True,
            "selection_lock_reason": "incomplete_lesson_completion",
            "eligible_courses": [],
        }

    monkeypatch.setattr(
        course_routes.intro_course_progression_service,
        "read_intro_selection_state",
        _fake_read_intro_selection_state,
        raising=True,
    )

    response = await async_client.get("/courses/intro-selection")

    assert response.status_code == 200, response.text
    assert response.json() == {
        "selection_locked": True,
        "selection_lock_reason": "incomplete_lesson_completion",
        "eligible_courses": [],
    }


async def test_intro_selection_route_requires_app_entry(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _deny_app_entry(monkeypatch)

    async def _fail_read_intro_selection_state(*, user_id: str) -> dict[str, object]:
        del user_id
        raise AssertionError("selection service must not run before app entry")

    monkeypatch.setattr(
        course_routes.intro_course_progression_service,
        "read_intro_selection_state",
        _fail_read_intro_selection_state,
        raising=True,
    )

    response = await async_client.get("/courses/intro-selection")

    assert response.status_code == 403, response.text
    assert response.json() == {"detail": "canonical_app_entry_required"}


async def test_intro_selection_route_has_no_query_or_body_dependency(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    async def _fake_read_intro_selection_state(*, user_id: str) -> dict[str, object]:
        assert user_id == USER_ID
        return {
            "selection_locked": False,
            "selection_lock_reason": None,
            "eligible_courses": [],
        }

    monkeypatch.setattr(
        course_routes.intro_course_progression_service,
        "read_intro_selection_state",
        _fake_read_intro_selection_state,
        raising=True,
    )

    signature = inspect.signature(course_routes.intro_selection_state)
    assert list(signature.parameters) == ["current"]

    response = await async_client.get("/courses/intro-selection")

    assert response.status_code == 200, response.text
    assert response.json() == {
        "selection_locked": False,
        "selection_lock_reason": None,
        "eligible_courses": [],
    }
