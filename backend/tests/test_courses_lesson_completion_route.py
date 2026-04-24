from __future__ import annotations

from datetime import datetime, timezone

import pytest

from app import auth, schemas
from app.main import app
from app.routes import courses as course_routes
from app.services.lesson_completion_service import LessonCompletionServiceInvariantError


pytestmark = pytest.mark.anyio("asyncio")

USER_ID = "11111111-1111-1111-1111-111111111111"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"
COMPLETION_ID = "44444444-4444-4444-4444-444444444444"


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


def _completion_payload(*, source: str = "manual") -> dict[str, object]:
    return {
        "id": COMPLETION_ID,
        "user_id": USER_ID,
        "course_id": COURSE_ID,
        "lesson_id": LESSON_ID,
        "completed_at": datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc),
        "completion_source": source,
    }


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


async def test_complete_lesson_route_returns_completed_wrapper_unchanged(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    calls: list[tuple[str, str]] = []
    service_result = {
        "status": "completed",
        "completion": _completion_payload(source="manual"),
    }

    async def _fake_complete_lesson(*, user_id: str, lesson_id: str) -> dict[str, object]:
        calls.append((user_id, lesson_id))
        return service_result

    monkeypatch.setattr(
        course_routes.lesson_completion_service,
        "complete_lesson",
        _fake_complete_lesson,
        raising=True,
    )

    response = await async_client.post(f"/courses/lessons/{LESSON_ID}/complete")

    assert response.status_code == 200, response.text
    assert response.json() == schemas.LessonCompletionCommandResponse(
        **service_result
    ).model_dump(mode="json")
    assert calls == [(USER_ID, LESSON_ID)]


async def test_complete_lesson_route_returns_already_completed_wrapper_unchanged(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    calls: list[tuple[str, str]] = []
    service_result = {
        "status": "already_completed",
        "completion": _completion_payload(source="auto_final_lesson"),
    }

    async def _fake_complete_lesson(*, user_id: str, lesson_id: str) -> dict[str, object]:
        calls.append((user_id, lesson_id))
        return service_result

    monkeypatch.setattr(
        course_routes.lesson_completion_service,
        "complete_lesson",
        _fake_complete_lesson,
        raising=True,
    )

    response = await async_client.post(f"/courses/lessons/{LESSON_ID}/complete")

    assert response.status_code == 200, response.text
    assert response.json() == schemas.LessonCompletionCommandResponse(
        **service_result
    ).model_dump(mode="json")
    assert calls == [(USER_ID, LESSON_ID)]


async def test_complete_lesson_route_maps_not_found_to_404(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    async def _fake_complete_lesson(*, user_id: str, lesson_id: str) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        return {"status": "lesson_not_found", "completion": None}

    monkeypatch.setattr(
        course_routes.lesson_completion_service,
        "complete_lesson",
        _fake_complete_lesson,
        raising=True,
    )

    response = await async_client.post(f"/courses/lessons/{LESSON_ID}/complete")

    assert response.status_code == 404, response.text
    assert response.json() == {"detail": "Lektionen kunde inte hittas."}


async def test_complete_lesson_route_maps_access_denied_to_403(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    async def _fake_complete_lesson(*, user_id: str, lesson_id: str) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        return {"status": "access_denied", "completion": None}

    monkeypatch.setattr(
        course_routes.lesson_completion_service,
        "complete_lesson",
        _fake_complete_lesson,
        raising=True,
    )

    response = await async_client.post(f"/courses/lessons/{LESSON_ID}/complete")

    assert response.status_code == 403, response.text
    assert response.json() == {"detail": "Du har inte åtkomst till den här lektionen."}


async def test_complete_lesson_route_maps_invariant_error_to_500(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _allow_app_entry(monkeypatch)

    async def _fake_complete_lesson(*, user_id: str, lesson_id: str) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        raise LessonCompletionServiceInvariantError("broken invariant")

    monkeypatch.setattr(
        course_routes.lesson_completion_service,
        "complete_lesson",
        _fake_complete_lesson,
        raising=True,
    )

    response = await async_client.post(f"/courses/lessons/{LESSON_ID}/complete")

    assert response.status_code == 500, response.text
    assert response.json() == {"detail": "Internal Server Error"}


async def test_complete_lesson_route_requires_app_entry(
    async_client,
    monkeypatch,
) -> None:
    await _override_current_user()
    await _deny_app_entry(monkeypatch)

    async def _fail_complete_lesson(*, user_id: str, lesson_id: str) -> dict[str, object]:
        del user_id, lesson_id
        raise AssertionError("completion service must not run before app entry")

    monkeypatch.setattr(
        course_routes.lesson_completion_service,
        "complete_lesson",
        _fail_complete_lesson,
        raising=True,
    )

    response = await async_client.post(f"/courses/lessons/{LESSON_ID}/complete")

    assert response.status_code == 403, response.text
    assert response.json() == {"detail": "canonical_app_entry_required"}
