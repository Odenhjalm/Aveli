from __future__ import annotations

from contextlib import asynccontextmanager

import pytest
from psycopg import errors

from app.repositories import courses as courses_repo


pytestmark = pytest.mark.anyio("asyncio")


class _FakeConnection:
    def __init__(self) -> None:
        self.rollback_calls = 0

    async def rollback(self) -> None:
        self.rollback_calls += 1


class _FakeCursor:
    def __init__(self, connection: _FakeConnection) -> None:
        self.connection = connection
        self.executed: list[tuple[str, tuple[object, ...]]] = []

    async def execute(
        self,
        query: str,
        params: tuple[object, ...] | list[object] | None = None,
    ) -> None:
        normalized_query = " ".join(query.split())
        normalized_params = tuple(params or ())
        self.executed.append((normalized_query, normalized_params))
        if len(self.executed) == 1 and "c.step_level" in normalized_query:
            raise errors.UndefinedColumn('column "step_level" does not exist')

    async def fetchone(self) -> dict[str, object] | None:
        return {"exists": 1}


async def test_user_owns_any_course_step_rolls_back_before_fallback(monkeypatch):
    connection = _FakeConnection()
    cursor = _FakeCursor(connection)

    @asynccontextmanager
    async def fake_get_conn():
        yield cursor

    monkeypatch.setattr(courses_repo, "get_conn", fake_get_conn, raising=True)

    result = await courses_repo.user_owns_any_course_step("user-1", "step1")

    assert result is True
    assert connection.rollback_calls == 1
    assert len(cursor.executed) == 2
    assert "c.step_level" in cursor.executed[0][0]
    assert "coalesce(" in cursor.executed[1][0].lower()
    assert cursor.executed[0][1] == ("user-1", "step1")
    assert cursor.executed[1][1] == ("user-1", "step1")
