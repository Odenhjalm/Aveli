from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException

from app.routes import api_events
from app.schemas.events import (
    EventParticipantCreateRequest,
    EventParticipantRole,
    EventUpdateRequest,
)


pytestmark = pytest.mark.anyio("asyncio")


def _event_row(
    *,
    event_id: UUID,
    created_by: str,
    status: str = "scheduled",
    visibility: str = "invited",
) -> dict:
    now = datetime.now(timezone.utc)
    return {
        "id": str(event_id),
        "type": "ceremony",
        "title": "Event",
        "description": None,
        "image_id": None,
        "start_at": now + timedelta(days=1),
        "end_at": now + timedelta(days=1, hours=1),
        "timezone": "UTC",
        "status": status,
        "visibility": visibility,
        "created_by": created_by,
        "created_at": now,
        "updated_at": now,
    }


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
        self.committed = False
        self.rolled_back = False

    async def __aenter__(self) -> "_FakePoolConnection":
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False

    def cursor(self, row_factory=None):  # noqa: ARG002
        return _FakeCursorContext(self._cursor)

    async def commit(self) -> None:
        self.committed = True

    async def rollback(self) -> None:
        self.rolled_back = True


class _FakePool:
    def __init__(self, cursor: _FakeCursor):
        self._connection = _FakePoolConnection(cursor)

    def connection(self) -> _FakePoolConnection:
        return self._connection


def _install_get_conn_sequence(monkeypatch, *cursors: _FakeCursor) -> None:
    queue = list(cursors)

    def _factory():
        if not queue:
            raise AssertionError("No fake cursor left for get_conn()")
        return _FakeCursorContext(queue.pop(0))

    monkeypatch.setattr(api_events, "get_conn", _factory, raising=True)


def _install_fake_pool(monkeypatch, cursor: _FakeCursor) -> _FakePool:
    pool = _FakePool(cursor)
    monkeypatch.setattr(api_events, "pool", pool, raising=True)
    return pool


async def test_active_event_host_query_uses_host_role_only(monkeypatch):
    cursor = _FakeCursor(fetchone_rows=[{"exists": 1}])
    _install_get_conn_sequence(monkeypatch, cursor)

    allowed = await api_events._user_is_active_event_host("event-1", "user-1")

    assert allowed is True
    query, params = cursor.executed[0]
    assert params == ("event-1", "user-1")
    assert "ep.role = 'host'" in query
    assert "ep.status <> 'cancelled'" in query
    assert "created_by" not in query


async def test_events_source_preserves_created_by_as_provenance_only():
    root = Path(__file__).resolve().parents[1]
    source = (root / "app/routes/api_events.py").read_text(encoding="utf-8")

    assert "created_by," in source
    assert 'str(event["created_by"]) == current_id' not in source
    assert 'str(event["created_by"]) != str(current["id"])' not in source
    assert "e.created_by = %(user_id)s" not in source
    assert "Only the event creator may" not in source
    assert "@router.delete" not in source


async def test_get_event_denies_creator_without_active_host_for_draft(monkeypatch):
    event_id = uuid4()
    creator_id = str(uuid4())
    event = _event_row(
        event_id=event_id,
        created_by=creator_id,
        status="draft",
        visibility="invited",
    )

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    async def fake_is_host(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == str(event_id)
        assert candidate_user_id == creator_id
        return False

    async def fake_is_participant(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == str(event_id)
        assert candidate_user_id == creator_id
        return False

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)
    monkeypatch.setattr(
        api_events,
        "_user_is_active_event_host",
        fake_is_host,
        raising=True,
    )
    monkeypatch.setattr(
        api_events,
        "_user_is_event_participant",
        fake_is_participant,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await api_events.get_event(event_id, {"id": creator_id, "is_admin": False})

    assert excinfo.value.status_code == 403
    assert excinfo.value.detail == "You do not have access to this event"


async def test_get_event_keeps_participant_access_separate_from_host_authority(monkeypatch):
    event_id = uuid4()
    participant_id = str(uuid4())
    event = _event_row(
        event_id=event_id,
        created_by=str(uuid4()),
        status="scheduled",
        visibility="invited",
    )

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    async def fake_is_host(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == str(event_id)
        assert candidate_user_id == participant_id
        return False

    async def fake_is_participant(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == str(event_id)
        assert candidate_user_id == participant_id
        return True

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)
    monkeypatch.setattr(
        api_events,
        "_user_is_active_event_host",
        fake_is_host,
        raising=True,
    )
    monkeypatch.setattr(
        api_events,
        "_user_is_event_participant",
        fake_is_participant,
        raising=True,
    )

    record = await api_events.get_event(event_id, {"id": participant_id, "is_admin": False})

    assert str(record.id) == str(event_id)
    assert str(record.created_by) == str(event["created_by"])


async def test_update_event_requires_active_host_not_creator_provenance(monkeypatch):
    event_id = uuid4()
    creator_id = str(uuid4())
    event = _event_row(event_id=event_id, created_by=creator_id)

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    async def fake_is_host(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == str(event_id)
        assert candidate_user_id == creator_id
        return False

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)
    monkeypatch.setattr(
        api_events,
        "_user_is_active_event_host",
        fake_is_host,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await api_events.update_event(
            event_id,
            EventUpdateRequest(title="Updated"),
            {"id": creator_id, "is_admin": False},
        )

    assert excinfo.value.status_code == 403
    assert excinfo.value.detail == "Only an event host may update this event"


async def test_update_event_allows_admin_override(monkeypatch):
    event_id = uuid4()
    admin_id = str(uuid4())
    event = _event_row(event_id=event_id, created_by=str(uuid4()))
    updated = {
        **event,
        "title": "Admin updated",
    }
    cursor = _FakeCursor(fetchone_rows=[updated])
    _install_get_conn_sequence(monkeypatch, cursor)

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)

    record = await api_events.update_event(
        event_id,
        EventUpdateRequest(title="Admin updated"),
        {"id": admin_id, "is_admin": True},
    )

    assert str(record.id) == str(event_id)
    assert record.title == "Admin updated"
    query, _ = cursor.executed[0]
    assert "created_by" not in query.split("WHERE", 1)[0]


async def test_list_events_query_uses_host_subquery_not_created_by(monkeypatch):
    cursor = _FakeCursor(fetchall_rows=[[]])
    _install_get_conn_sequence(monkeypatch, cursor)

    async def fake_has_active_membership(user_id: str) -> bool:
        assert user_id == "user-1"
        return False

    monkeypatch.setattr(
        api_events,
        "_has_active_membership",
        fake_has_active_membership,
        raising=True,
    )

    response = await api_events.list_events(
        {"id": "user-1", "is_admin": False},
        from_time=None,
        to_time=None,
        type=None,
        status_value=None,
        limit=50,
    )

    assert response.items == []
    query, params = cursor.executed[0]
    assert params["user_id"] == "user-1"
    assert "e.created_by = %(user_id)s" not in query
    assert "ep_host.role = 'host'" in query
    assert "ep_participant.status <> 'cancelled'" in query


async def test_register_participant_denies_participant_only_user_for_owner_actions(monkeypatch):
    event_id = uuid4()
    participant_id = str(uuid4())
    target_user_id = uuid4()
    event = _event_row(event_id=event_id, created_by=str(uuid4()))

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    async def fake_is_host(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == str(event_id)
        assert candidate_user_id == participant_id
        return False

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)
    monkeypatch.setattr(
        api_events,
        "_user_is_active_event_host",
        fake_is_host,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await api_events.register_participant(
            event_id,
            EventParticipantCreateRequest(
                user_id=target_user_id,
                role=EventParticipantRole.participant,
            ),
            {"id": participant_id, "is_admin": False},
        )

    assert excinfo.value.status_code == 403
    assert excinfo.value.detail == "Only an event host may register other users"


async def test_register_participant_allows_admin_override(monkeypatch):
    event_id = uuid4()
    admin_id = str(uuid4())
    target_user_id = uuid4()
    event = _event_row(event_id=event_id, created_by=str(uuid4()))
    inserted = {
        "id": uuid4(),
        "event_id": event_id,
        "user_id": target_user_id,
        "role": "participant",
        "status": "registered",
        "registered_at": datetime.now(timezone.utc),
    }
    cursor = _FakeCursor(fetchone_rows=[inserted])
    pool = _install_fake_pool(monkeypatch, cursor)

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)

    record = await api_events.register_participant(
        event_id,
        EventParticipantCreateRequest(
            user_id=target_user_id,
            role=EventParticipantRole.participant,
        ),
        {"id": admin_id, "is_admin": True},
    )

    assert str(record.event_id) == str(event_id)
    assert str(record.user_id) == str(target_user_id)
    assert record.role == EventParticipantRole.participant
    assert pool.connection().committed is True


async def test_list_event_notifications_denies_creator_without_active_host(monkeypatch):
    event_id = uuid4()
    creator_id = str(uuid4())
    event = _event_row(event_id=event_id, created_by=creator_id)

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    async def fake_is_host(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == str(event_id)
        assert candidate_user_id == creator_id
        return False

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)
    monkeypatch.setattr(
        api_events,
        "_user_is_active_event_host",
        fake_is_host,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await api_events.list_event_notifications(
            event_id,
            {"id": creator_id, "is_admin": False},
        )

    assert excinfo.value.status_code == 403
    assert excinfo.value.detail == "Only an event host may view notifications for this event"


async def test_list_event_notifications_allows_admin_override(monkeypatch):
    event_id = uuid4()
    admin_id = str(uuid4())
    event = _event_row(event_id=event_id, created_by=str(uuid4()))
    campaign_cursor = _FakeCursor(
        fetchall_rows=[
            [
                {
                    "id": uuid4(),
                    "type": "manual",
                    "channel": "in_app",
                    "title": "Admin notice",
                    "body": "Hello",
                    "send_at": datetime.now(timezone.utc),
                    "created_by": uuid4(),
                    "status": "sent",
                    "created_at": datetime.now(timezone.utc),
                    "recipient_count": 1,
                }
            ]
        ]
    )
    audience_cursor = _FakeCursor(
        fetchall_rows=[
            [
                {
                    "id": uuid4(),
                    "notification_id": campaign_cursor._fetchall_rows[0][0]["id"],
                    "audience_type": "event_participants",
                    "event_id": event_id,
                    "course_id": None,
                }
            ]
        ]
    )
    _install_get_conn_sequence(monkeypatch, campaign_cursor, audience_cursor)

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == str(event_id)
        return event

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)

    response = await api_events.list_event_notifications(
        event_id,
        {"id": admin_id, "is_admin": True},
    )

    assert len(response.items) == 1
    assert response.items[0].title == "Admin notice"
