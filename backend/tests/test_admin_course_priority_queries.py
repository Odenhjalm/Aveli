from __future__ import annotations

from uuid import uuid4

import pytest

from app import models
from app.routes import admin as admin_routes

pytestmark = pytest.mark.anyio("asyncio")


class _FakeCursor:
    def __init__(self, *, fetchone_rows=None, fetchall_rows=None):
        self._fetchone_rows = list(fetchone_rows or [])
        self._fetchall_rows = list(fetchall_rows or [])
        self.executed: list[tuple[str, object]] = []

    async def execute(self, query: str, params=None) -> None:
        self.executed.append((query, params))

    async def fetchone(self):
        if not self._fetchone_rows:
            return None
        return self._fetchone_rows.pop(0)

    async def fetchall(self):
        if not self._fetchall_rows:
            return []
        return self._fetchall_rows.pop(0)


class _FakeCursorContext:
    def __init__(self, cursor: _FakeCursor):
        self._cursor = cursor

    async def __aenter__(self) -> _FakeCursor:
        return self._cursor

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False


class _FakePoolConnection:
    def __init__(self, cursor: _FakeCursor):
        self._cursor = cursor

    async def __aenter__(self) -> "_FakePoolConnection":
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False

    def cursor(self, row_factory=None):  # noqa: ARG002
        return _FakeCursorContext(self._cursor)


class _FakePool:
    def __init__(self, cursor: _FakeCursor):
        self._connection = _FakePoolConnection(cursor)

    def connection(self) -> _FakePoolConnection:
        return self._connection


def _install_fake_pool(monkeypatch, cursor: _FakeCursor) -> None:
    monkeypatch.setattr(models, "pool", _FakePool(cursor), raising=True)


async def test_list_teacher_course_priorities_uses_canonical_course_teacher_id(
    monkeypatch,
):
    teacher_id = str(uuid4())
    cursor = _FakeCursor(fetchall_rows=[[{"teacher_id": teacher_id}]])
    _install_fake_pool(monkeypatch, cursor)

    rows = await models.list_teacher_course_priorities(limit=5)

    assert rows == [{"teacher_id": teacher_id}]
    query, params = cursor.executed[0]
    assert params == (5,)
    assert "teacher_id AS teacher_id" in query
    assert "GROUP BY teacher_id" in query
    assert "created_by AS teacher_id" not in query
    assert "GROUP BY created_by" not in query


async def test_get_teacher_course_priority_uses_canonical_course_teacher_id(
    monkeypatch,
):
    teacher_id = str(uuid4())
    cursor = _FakeCursor(fetchone_rows=[{"teacher_id": teacher_id}])
    _install_fake_pool(monkeypatch, cursor)

    row = await models.get_teacher_course_priority(teacher_id)

    assert row == {"teacher_id": teacher_id}
    query, params = cursor.executed[0]
    assert params == (teacher_id,)
    assert "teacher_id AS teacher_id" in query
    assert "GROUP BY teacher_id" in query
    assert "created_by AS teacher_id" not in query
    assert "GROUP BY created_by" not in query


async def test_admin_settings_route_still_returns_canonical_priority_surface(
    monkeypatch,
):
    teacher_id = str(uuid4())
    current = {"id": str(uuid4()), "is_admin": True}

    async def fake_list_teacher_course_priorities(limit=None):
        assert limit is None
        return [
            {
                "teacher_id": teacher_id,
                "display_name": "Teacher",
                "email": "teacher@example.com",
                "photo_url": None,
                "priority": 10,
                "notes": "Canonical owner",
                "updated_at": None,
                "updated_by": None,
                "updated_by_name": None,
                "total_courses": 2,
                "published_courses": 1,
            }
        ]

    async def fake_fetch_admin_metrics():
        return {
            "total_users": 1,
            "total_teachers": 1,
            "total_courses": 2,
            "published_courses": 1,
            "paid_orders_total": 0,
            "paid_orders_30d": 0,
            "paying_customers_total": 0,
            "paying_customers_30d": 0,
            "revenue_total_cents": 0,
            "revenue_30d_cents": 0,
            "login_events_7d": 0,
            "active_users_7d": 0,
        }

    monkeypatch.setattr(
        admin_routes.models,
        "list_teacher_course_priorities",
        fake_list_teacher_course_priorities,
        raising=True,
    )
    monkeypatch.setattr(
        admin_routes.models,
        "fetch_admin_metrics",
        fake_fetch_admin_metrics,
        raising=True,
    )
    response = await admin_routes.admin_settings(current)

    assert response.metrics.total_teachers == 1
    assert [item.model_dump(mode="json") for item in response.priorities] == [
        {
            "teacher_id": teacher_id,
            "display_name": "Teacher",
            "email": "teacher@example.com",
            "photo_url": None,
            "priority": 10,
            "notes": "Canonical owner",
            "updated_at": None,
            "updated_by": None,
            "updated_by_name": None,
            "total_courses": 2,
            "published_courses": 1,
        }
    ]


async def test_admin_set_teacher_priority_route_still_works(
    monkeypatch,
):
    teacher_id = str(uuid4())
    current = {"id": str(uuid4()), "is_admin": True}
    updated_by = current["id"]
    seen: list[tuple[str, int, str | None, str | None]] = []

    existing = {
        "teacher_id": teacher_id,
        "display_name": "Teacher",
        "email": "teacher@example.com",
        "photo_url": None,
        "priority": 100,
        "notes": None,
        "updated_at": None,
        "updated_by": None,
        "updated_by_name": None,
        "total_courses": 3,
        "published_courses": 2,
    }
    updated = {
        **existing,
        "priority": 5,
        "notes": "Pinned",
        "updated_by": updated_by,
        "updated_by_name": "Admin",
    }
    get_calls = {"count": 0}

    async def fake_get_teacher_course_priority(candidate_teacher_id: str):
        assert candidate_teacher_id == teacher_id
        get_calls["count"] += 1
        return existing if get_calls["count"] == 1 else updated

    async def fake_upsert_teacher_course_priority(
        *,
        teacher_id: str,
        priority: int,
        updated_by: str | None,
        notes: str | None = None,
    ):
        seen.append((teacher_id, priority, updated_by, notes))
        return {
            "teacher_id": teacher_id,
            "priority": priority,
            "notes": notes,
            "updated_by": updated_by,
        }

    monkeypatch.setattr(
        admin_routes.models,
        "get_teacher_course_priority",
        fake_get_teacher_course_priority,
        raising=True,
    )
    monkeypatch.setattr(
        admin_routes.models,
        "upsert_teacher_course_priority",
        fake_upsert_teacher_course_priority,
        raising=True,
    )
    response = await admin_routes.admin_set_teacher_priority(
        teacher_id=teacher_id,
        payload=admin_routes.schemas.TeacherPriorityUpdate(priority=5, notes="Pinned"),
        current=current,
    )

    assert seen == [(teacher_id, 5, updated_by, "Pinned")]
    assert str(response.teacher_id) == teacher_id
    assert response.priority == 5
    assert str(response.updated_by) == updated_by
