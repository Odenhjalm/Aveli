from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

import pytest

from app.services import lesson_completion_service


pytestmark = pytest.mark.anyio("asyncio")


USER_ID = "11111111-1111-1111-1111-111111111111"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"
COMPLETION_ID = "44444444-4444-4444-4444-444444444444"


class _FakeConnection:
    def __init__(self) -> None:
        self.commits = 0

    async def commit(self) -> None:
        self.commits += 1


class _FakeConnectionContext:
    def __init__(self, conn: _FakeConnection) -> None:
        self._conn = conn

    async def __aenter__(self) -> _FakeConnection:
        return self._conn

    async def __aexit__(self, exc_type, exc, tb) -> None:
        return None


class _FakePool:
    def __init__(self, conn: _FakeConnection) -> None:
        self._conn = conn

    def connection(self) -> _FakeConnectionContext:
        return _FakeConnectionContext(self._conn)


def _access_result(*, can_access: bool) -> dict[str, object]:
    return {
        "lesson": {
            "id": LESSON_ID,
            "course_id": COURSE_ID,
            "lesson_title": "Lesson",
            "position": 1,
        },
        "course": {"id": COURSE_ID},
        "enrollment": {"id": "enrollment-1"},
        "required_enrollment_source": "purchase",
        "current_unlock_position": 1,
        "can_access": can_access,
    }


def _completion_row(*, source: str = "manual") -> dict[str, object]:
    return {
        "id": UUID(COMPLETION_ID),
        "user_id": UUID(USER_ID),
        "course_id": UUID(COURSE_ID),
        "lesson_id": UUID(LESSON_ID),
        "completed_at": datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc),
        "completion_source": source,
    }


@pytest.fixture
def fake_pool(monkeypatch) -> _FakeConnection:
    conn = _FakeConnection()
    monkeypatch.setattr(
        lesson_completion_service,
        "pool",
        _FakePool(conn),
        raising=True,
    )
    return conn


async def test_complete_lesson_returns_not_found_without_repository_calls(
    monkeypatch,
    fake_pool,
) -> None:
    async def _fake_read_canonical_lesson_access(
        user_id: str,
        lesson_id: str,
        *,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        return {
            "lesson": None,
            "course": None,
            "enrollment": None,
            "required_enrollment_source": None,
            "current_unlock_position": 0,
            "can_access": False,
        }

    async def _fail_get_lesson_completion(**kwargs):
        del kwargs
        raise AssertionError("repository read must not run when lesson is missing")

    async def _fail_create_lesson_completion(**kwargs):
        del kwargs
        raise AssertionError("repository write must not run when lesson is missing")

    monkeypatch.setattr(
        lesson_completion_service.courses_service,
        "read_canonical_lesson_access",
        _fake_read_canonical_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "get_lesson_completion",
        _fail_get_lesson_completion,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "create_lesson_completion",
        _fail_create_lesson_completion,
        raising=True,
    )

    result = await lesson_completion_service.complete_lesson(
        user_id=USER_ID,
        lesson_id=LESSON_ID,
    )

    assert result == {"status": "lesson_not_found", "completion": None}
    assert fake_pool.commits == 0


async def test_complete_lesson_returns_access_denied_without_repository_write(
    monkeypatch,
    fake_pool,
) -> None:
    async def _fake_read_canonical_lesson_access(
        user_id: str,
        lesson_id: str,
        *,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        return _access_result(can_access=False)

    async def _fail_get_lesson_completion(**kwargs):
        del kwargs
        raise AssertionError("repository read must not run when access is denied")

    async def _fail_create_lesson_completion(**kwargs):
        del kwargs
        raise AssertionError("repository write must not run when access is denied")

    monkeypatch.setattr(
        lesson_completion_service.courses_service,
        "read_canonical_lesson_access",
        _fake_read_canonical_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "get_lesson_completion",
        _fail_get_lesson_completion,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "create_lesson_completion",
        _fail_create_lesson_completion,
        raising=True,
    )

    result = await lesson_completion_service.complete_lesson(
        user_id=USER_ID,
        lesson_id=LESSON_ID,
    )

    assert result == {"status": "access_denied", "completion": None}
    assert fake_pool.commits == 0


async def test_complete_lesson_returns_completed_on_first_success(
    monkeypatch,
    fake_pool,
) -> None:
    created_row = _completion_row(source="manual")
    call_order: list[str] = []

    async def _fake_read_canonical_lesson_access(
        user_id: str,
        lesson_id: str,
        *,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        call_order.append("access")
        return _access_result(can_access=True)

    async def _fake_get_lesson_completion(
        *,
        user_id: str,
        lesson_id: str,
        conn,
    ) -> None:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        call_order.append("get")
        return None

    async def _fake_create_lesson_completion(
        *,
        user_id: str,
        course_id: str,
        lesson_id: str,
        completion_source: str,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        assert lesson_id == LESSON_ID
        assert completion_source == "manual"
        assert conn is fake_pool
        call_order.append("create")
        return created_row

    monkeypatch.setattr(
        lesson_completion_service.courses_service,
        "read_canonical_lesson_access",
        _fake_read_canonical_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "get_lesson_completion",
        _fake_get_lesson_completion,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "create_lesson_completion",
        _fake_create_lesson_completion,
        raising=True,
    )

    result = await lesson_completion_service.complete_lesson(
        user_id=USER_ID,
        lesson_id=LESSON_ID,
    )

    assert result == {"status": "completed", "completion": created_row}
    assert call_order == ["access", "get", "create"]
    assert fake_pool.commits == 1


async def test_complete_lesson_returns_already_completed_on_preread_duplicate(
    monkeypatch,
    fake_pool,
) -> None:
    existing_row = _completion_row(source="manual")
    call_order: list[str] = []

    async def _fake_read_canonical_lesson_access(
        user_id: str,
        lesson_id: str,
        *,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        call_order.append("access")
        return _access_result(can_access=True)

    async def _fake_get_lesson_completion(
        *,
        user_id: str,
        lesson_id: str,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        call_order.append("get")
        return existing_row

    async def _fail_create_lesson_completion(**kwargs):
        del kwargs
        raise AssertionError("repository write must not run when preread finds a row")

    monkeypatch.setattr(
        lesson_completion_service.courses_service,
        "read_canonical_lesson_access",
        _fake_read_canonical_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "get_lesson_completion",
        _fake_get_lesson_completion,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "create_lesson_completion",
        _fail_create_lesson_completion,
        raising=True,
    )

    result = await lesson_completion_service.complete_lesson(
        user_id=USER_ID,
        lesson_id=LESSON_ID,
    )

    assert result == {"status": "already_completed", "completion": existing_row}
    assert call_order == ["access", "get"]
    assert fake_pool.commits == 0


async def test_complete_lesson_returns_already_completed_on_race_duplicate(
    monkeypatch,
    fake_pool,
) -> None:
    existing_row = _completion_row(source="manual")
    call_order: list[str] = []
    get_calls = 0

    async def _fake_read_canonical_lesson_access(
        user_id: str,
        lesson_id: str,
        *,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        call_order.append("access")
        return _access_result(can_access=True)

    async def _fake_get_lesson_completion(
        *,
        user_id: str,
        lesson_id: str,
        conn,
    ) -> dict[str, object] | None:
        nonlocal get_calls
        assert user_id == USER_ID
        assert lesson_id == LESSON_ID
        assert conn is fake_pool
        call_order.append("get")
        get_calls += 1
        if get_calls == 1:
            return None
        return existing_row

    async def _fake_create_lesson_completion(
        *,
        user_id: str,
        course_id: str,
        lesson_id: str,
        completion_source: str,
        conn,
    ) -> dict[str, object]:
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        assert lesson_id == LESSON_ID
        assert completion_source == "manual"
        assert conn is fake_pool
        call_order.append("create")
        raise lesson_completion_service.lesson_completions.LessonCompletionAlreadyExistsError()

    monkeypatch.setattr(
        lesson_completion_service.courses_service,
        "read_canonical_lesson_access",
        _fake_read_canonical_lesson_access,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "get_lesson_completion",
        _fake_get_lesson_completion,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_completion_service.lesson_completions,
        "create_lesson_completion",
        _fake_create_lesson_completion,
        raising=True,
    )

    result = await lesson_completion_service.complete_lesson(
        user_id=USER_ID,
        lesson_id=LESSON_ID,
    )

    assert result == {"status": "already_completed", "completion": existing_row}
    assert call_order == ["access", "get", "create", "get"]
    assert fake_pool.commits == 0
