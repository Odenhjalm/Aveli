from __future__ import annotations

import pytest

from app import models


pytestmark = pytest.mark.anyio("asyncio")


class _FakeCursor:
    def __init__(self, *rows):
        self._rows = list(rows)
        self.executed: list[tuple[str, object]] = []

    async def execute(self, query: str, params=None) -> None:
        self.executed.append((query, params))

    async def fetchone(self):
        if not self._rows:
            return None
        return self._rows.pop(0)


class _FakeConn:
    def __init__(self, cursor: _FakeCursor):
        self._cursor = cursor

    async def __aenter__(self) -> _FakeCursor:
        return self._cursor

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False


def _install_fake_conn(monkeypatch, cursor: _FakeCursor) -> None:
    monkeypatch.setattr(models, "get_conn", lambda: _FakeConn(cursor))


async def test_quiz_belongs_to_user_uses_canonical_course_teacher_id(monkeypatch):
    cursor = _FakeCursor({"course_id": "course-1", "teacher_id": "teacher-1"})
    _install_fake_conn(monkeypatch, cursor)

    allowed = await models.quiz_belongs_to_user("quiz-1", "teacher-1")

    assert allowed is True
    query, params = cursor.executed[0]
    assert params == ("quiz-1",)
    assert "c.teacher_id" in query
    assert "c.created_by" not in query


async def test_quiz_belongs_to_user_denies_when_teacher_id_differs(monkeypatch):
    cursor = _FakeCursor({"course_id": "course-1", "teacher_id": "teacher-2"})
    _install_fake_conn(monkeypatch, cursor)

    allowed = await models.quiz_belongs_to_user("quiz-1", "teacher-1")

    assert allowed is False
