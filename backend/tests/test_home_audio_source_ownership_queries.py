from __future__ import annotations

import pytest

from app.repositories import home_audio_sources as repo


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
    monkeypatch.setattr(repo, "get_conn", lambda: _FakeConn(cursor))


async def test_resolve_lesson_media_course_owner_uses_canonical_course_teacher_id(
    monkeypatch,
):
    cursor = _FakeCursor(
        {
            "teacher_id": "teacher-1",
            "course_title": "Course",
            "course_is_published": True,
            "media_type": "audio",
        }
    )
    _install_fake_conn(monkeypatch, cursor)

    row = await repo.resolve_lesson_media_course_owner("lesson-media-1")

    assert row is not None
    query, params = cursor.executed[0]
    assert params == ("lesson-media-1",)
    assert "c.teacher_id AS teacher_id" in query
    assert "c.created_by" not in query


async def test_get_home_player_course_link_filters_by_canonical_course_owner(
    monkeypatch,
):
    cursor = _FakeCursor(
        {
            "id": "link-1",
            "teacher_id": "stored-mirror",
            "lesson_media_id": "lesson-media-1",
            "title": "Link",
            "course_title": "Course",
            "enabled": True,
            "status": "active",
            "kind": "audio",
            "created_at": None,
            "updated_at": None,
        }
    )
    _install_fake_conn(monkeypatch, cursor)

    row = await repo.get_home_player_course_link(
        link_id="link-1",
        teacher_id="teacher-1",
    )

    assert row is not None
    query, params = cursor.executed[0]
    assert params == ("link-1", "teacher-1")
    assert "c_owner.teacher_id = %s::uuid" in query
    assert "AND hpcl.teacher_id = %s::uuid" not in query


async def test_update_home_player_course_link_filters_by_canonical_course_owner(
    monkeypatch,
):
    cursor = _FakeCursor(
        {"id": "link-1"},
        {
            "id": "link-1",
            "teacher_id": "stored-mirror",
            "lesson_media_id": "lesson-media-1",
            "title": "Link",
            "course_title": "Course",
            "enabled": False,
            "status": "active",
            "kind": "audio",
            "created_at": None,
            "updated_at": None,
        },
    )
    _install_fake_conn(monkeypatch, cursor)

    row = await repo.update_home_player_course_link(
        link_id="link-1",
        teacher_id="teacher-1",
        fields={"enabled": False},
    )

    assert row is not None
    update_query, params = cursor.executed[0]
    assert params["link_id"] == "link-1"
    assert params["teacher_id"] == "teacher-1"
    assert "c.teacher_id = %(teacher_id)s::uuid" in update_query
    assert "AND teacher_id = %(teacher_id)s::uuid" not in update_query


async def test_delete_home_player_course_link_filters_by_canonical_course_owner(
    monkeypatch,
):
    cursor = _FakeCursor({"id": "link-1"})
    _install_fake_conn(monkeypatch, cursor)

    deleted = await repo.delete_home_player_course_link(
        link_id="link-1",
        teacher_id="teacher-1",
    )

    assert deleted is True
    query, params = cursor.executed[0]
    assert params == ("link-1", "teacher-1")
    assert "c.teacher_id = %s::uuid" in query
    assert "AND teacher_id = %s::uuid" not in query
