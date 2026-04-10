from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
import uuid

import pytest

from app import db
from app.routes import api_events, api_notifications


pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(client, email: str, password: str, display_name: str):
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
    )
    assert register_resp.status_code == 201, register_resp.text

    login_resp = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, login_resp.text
    tokens = login_resp.json()
    access_token = tokens["access_token"]

    profile_resp = await client.get("/profiles/me", headers=auth_header(access_token))
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    return access_token, user_id


async def promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET role_v2 = 'teacher',
                       role = 'teacher'
                WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


def _event_row(
    *,
    event_id: str,
    created_by: str,
    status: str = "scheduled",
    visibility: str = "invited",
) -> dict:
    now = datetime.now(timezone.utc)
    return {
        "id": event_id,
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


def _install_get_conn_sequence(monkeypatch, module, *cursors: _FakeCursor) -> None:
    queue = list(cursors)

    def _factory():
        if not queue:
            raise AssertionError("No fake cursor left for get_conn()")
        return _FakeCursorContext(queue.pop(0))

    monkeypatch.setattr(module, "get_conn", _factory, raising=True)


def _install_fake_pool(monkeypatch, module, cursor: _FakeCursor) -> _FakePool:
    pool = _FakePool(cursor)
    monkeypatch.setattr(module, "pool", pool, raising=True)
    return pool


async def test_events_and_notifications_sources_use_canonical_authority_only():
    root = Path(__file__).resolve().parents[1]
    events_source = (root / "app/routes/api_events.py").read_text(encoding="utf-8")
    notifications_source = (
        root / "app/routes/api_notifications.py"
    ).read_text(encoding="utf-8")

    assert "e.created_by = %(user_id)s" not in events_source
    assert "Only the event creator may" not in events_source
    assert "SELECT created_by FROM app.events" not in notifications_source
    assert "SELECT created_by FROM app.courses" not in notifications_source
    assert "FROM app.enrollments" not in notifications_source
    assert "FROM app.course_enrollments ce" in notifications_source
    assert "FROM app.event_participants ep" in notifications_source


async def test_event_notifications_route_denies_creator_without_active_host(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    token, user_id = await register_user(
        async_client,
        f"event_denied_{uuid.uuid4().hex[:8]}@example.com",
        password,
        "Teacher",
    )
    await promote_to_teacher(user_id)
    event_id = str(uuid.uuid4())

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == event_id
        return _event_row(event_id=event_id, created_by=user_id)

    async def fake_is_host(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == event_id
        assert candidate_user_id == user_id
        return False

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)
    monkeypatch.setattr(
        api_events,
        "_user_is_active_event_host",
        fake_is_host,
        raising=True,
    )

    try:
        response = await async_client.get(
            f"/api/events/{event_id}/notifications",
            headers=auth_header(token),
        )
        assert response.status_code == 403, response.text
        assert (
            response.json()["detail"]
            == "Only an event host may view notifications for this event"
        )
    finally:
        await cleanup_user(user_id)


async def test_event_notifications_route_allows_active_host(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    token, user_id = await register_user(
        async_client,
        f"event_host_{uuid.uuid4().hex[:8]}@example.com",
        password,
        "Teacher",
    )
    await promote_to_teacher(user_id)
    event_id = str(uuid.uuid4())
    notification_id = str(uuid.uuid4())

    campaign_cursor = _FakeCursor(
        fetchall_rows=[
            [
                {
                    "id": notification_id,
                    "type": "manual",
                    "channel": "in_app",
                    "title": "Welcome",
                    "body": "See you soon",
                    "send_at": datetime.now(timezone.utc),
                    "created_by": user_id,
                    "status": "sent",
                    "created_at": datetime.now(timezone.utc),
                    "recipient_count": 2,
                }
            ]
        ]
    )
    audience_cursor = _FakeCursor(
        fetchall_rows=[
            [
                {
                    "id": str(uuid.uuid4()),
                    "notification_id": notification_id,
                    "audience_type": "event_participants",
                    "event_id": event_id,
                    "course_id": None,
                }
            ]
        ]
    )
    _install_get_conn_sequence(monkeypatch, api_events, campaign_cursor, audience_cursor)

    async def fake_get_event_row(candidate_event_id: str):
        assert candidate_event_id == event_id
        return _event_row(event_id=event_id, created_by=user_id)

    async def fake_is_host(candidate_event_id: str, candidate_user_id: str) -> bool:
        assert candidate_event_id == event_id
        assert candidate_user_id == user_id
        return True

    monkeypatch.setattr(api_events, "_get_event_row", fake_get_event_row, raising=True)
    monkeypatch.setattr(
        api_events,
        "_user_is_active_event_host",
        fake_is_host,
        raising=True,
    )

    try:
        response = await async_client.get(
            f"/api/events/{event_id}/notifications",
            headers=auth_header(token),
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert len(body["items"]) == 1
        assert body["items"][0]["title"] == "Welcome"
        assert body["items"][0]["recipient_count"] == 2
        assert body["items"][0]["audiences"][0]["event_id"] == event_id
    finally:
        await cleanup_user(user_id)


async def test_notifications_create_route_rejects_participant_only_teacher(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    token, user_id = await register_user(
        async_client,
        f"notify_denied_{uuid.uuid4().hex[:8]}@example.com",
        password,
        "Teacher",
    )
    await promote_to_teacher(user_id)
    event_id = str(uuid.uuid4())

    async def fake_event_host_access(candidate_event_id: str, candidate_user_id: str):
        assert candidate_event_id == event_id
        assert candidate_user_id == user_id
        return True, False

    monkeypatch.setattr(
        api_notifications,
        "_event_host_access",
        fake_event_host_access,
        raising=True,
    )

    try:
        response = await async_client.post(
            "/api/notifications",
            headers=auth_header(token),
            json={
                "type": "manual",
                "channel": "in_app",
                "title": "Welcome",
                "body": "See you soon",
                "audiences": [
                    {
                        "audience_type": "event_participants",
                        "event_id": event_id,
                    }
                ],
            },
        )
        assert response.status_code == 403, response.text
        assert (
            response.json()["detail"]
            == "You may only notify participants of your own events"
        )
    finally:
        await cleanup_user(user_id)


async def test_notifications_create_route_allows_active_host(
    async_client,
    monkeypatch,
):
    password = "Passw0rd!"
    token, user_id = await register_user(
        async_client,
        f"notify_host_{uuid.uuid4().hex[:8]}@example.com",
        password,
        "Teacher",
    )
    await promote_to_teacher(user_id)
    event_id = str(uuid.uuid4())
    notification_id = str(uuid.uuid4())
    audience_id = str(uuid.uuid4())

    async def fake_event_host_access(candidate_event_id: str, candidate_user_id: str):
        assert candidate_event_id == event_id
        assert candidate_user_id == user_id
        return True, True

    async def fake_resolve_recipients(audiences):
        assert len(audiences) == 1
        return {user_id, str(uuid.uuid4())}

    cursor = _FakeCursor(
        fetchone_rows=[
            {
                "id": notification_id,
                "type": "manual",
                "channel": "in_app",
                "title": "Welcome",
                "body": "See you soon",
                "send_at": datetime.now(timezone.utc),
                "created_by": user_id,
                "status": "sent",
                "created_at": datetime.now(timezone.utc),
            },
            {
                "id": audience_id,
                "notification_id": notification_id,
                "audience_type": "event_participants",
                "event_id": event_id,
                "course_id": None,
            },
        ]
    )
    pool = _install_fake_pool(monkeypatch, api_notifications, cursor)

    monkeypatch.setattr(
        api_notifications,
        "_event_host_access",
        fake_event_host_access,
        raising=True,
    )
    monkeypatch.setattr(
        api_notifications,
        "_resolve_recipients",
        fake_resolve_recipients,
        raising=True,
    )

    try:
        response = await async_client.post(
            "/api/notifications",
            headers=auth_header(token),
            json={
                "type": "manual",
                "channel": "in_app",
                "title": "Welcome",
                "body": "See you soon",
                "audiences": [
                    {
                        "audience_type": "event_participants",
                        "event_id": event_id,
                    }
                ],
            },
        )
        assert response.status_code == 201, response.text
        body = response.json()["notification"]
        assert body["title"] == "Welcome"
        assert body["recipient_count"] == 2
        assert body["audiences"][0]["event_id"] == event_id
        assert pool.connection().committed is True
    finally:
        await cleanup_user(user_id)
