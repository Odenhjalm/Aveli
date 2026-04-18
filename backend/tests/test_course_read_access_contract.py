from __future__ import annotations

import pytest

from app.repositories import courses as courses_repo


pytestmark = pytest.mark.anyio("asyncio")


class _FakeCursor:
    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple[object, ...]]] = []

    async def execute(
        self,
        query: str,
        params: tuple[object, ...] | list[object] | None = None,
    ) -> None:
        normalized_query = " ".join(query.split())
        self.executed.append((normalized_query, tuple(params or ())))

    async def fetchone(self) -> dict[str, object] | None:
        return {"exists": 1}


class _FakeConnection:
    def __init__(self, cursor: _FakeCursor) -> None:
        self._cursor = cursor

    async def __aenter__(self) -> "_FakeConnection":
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False

    def cursor(self):
        return _FakeCursorContext(self._cursor)


class _FakeCursorContext:
    def __init__(self, cursor: _FakeCursor) -> None:
        self._cursor = cursor

    async def __aenter__(self) -> _FakeCursor:
        return self._cursor

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False


class _FakePool:
    def __init__(self, cursor: _FakeCursor) -> None:
        self._cursor = cursor

    def connection(self) -> _FakeConnection:
        return _FakeConnection(self._cursor)


async def test_is_course_owner_uses_canonical_teacher_id(monkeypatch):
    cursor = _FakeCursor()
    monkeypatch.setattr(courses_repo, "pool", _FakePool(cursor), raising=True)

    result = await courses_repo.is_course_owner("course-1", "teacher-1")

    assert result is True
    assert len(cursor.executed) == 1
    query, params = cursor.executed[0]
    assert "c.teacher_id = %s::uuid" in query
    assert "created_by" not in query
    assert "group_position" not in query
    assert params == ("course-1", "teacher-1")
