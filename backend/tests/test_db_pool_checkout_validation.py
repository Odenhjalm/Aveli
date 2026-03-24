from contextlib import asynccontextmanager
from time import monotonic

import pytest
from psycopg import OperationalError

from app import db


class FakeAsyncConnection:
    def __init__(self, *, dead: bool = False, autocommit: bool = False):
        self.dead = dead
        self.autocommit = autocommit
        self.calls: list[tuple[str, object]] = []

    async def execute(self, query: str):
        self.calls.append(("execute", query))
        if self.dead:
            raise OperationalError("connection lost")

    async def set_autocommit(self, value: bool):
        self.calls.append(("set_autocommit", value))
        self.autocommit = value


@pytest.fixture(autouse=True)
def _test_session_scope():
    yield


def test_pool_uses_explicit_checkout_check_callback():
    assert db.pool._check == db.ContextAwareAsyncConnectionPool.check_connection
    assert db.pool._configure is None


@pytest.mark.anyio
async def test_check_connection_validates_liveness():
    conn = FakeAsyncConnection()

    await db.ContextAwareAsyncConnectionPool.check_connection(conn)

    assert conn.calls == [
        ("set_autocommit", True),
        ("execute", ""),
        ("set_autocommit", False),
    ]


@pytest.mark.anyio
async def test_checkout_retries_after_failed_liveness_check(monkeypatch):
    pool = db.ContextAwareAsyncConnectionPool(
        conninfo="postgresql://unused",
        min_size=1,
        max_size=1,
        check=db.ContextAwareAsyncConnectionPool.check_connection,
        open=False,
    )
    stale_conn = FakeAsyncConnection(dead=True)
    healthy_conn = FakeAsyncConnection()
    handed_out = iter([stale_conn, healthy_conn])
    discarded: list[tuple[FakeAsyncConnection, bool]] = []

    async def fake_getconn_unchecked(timeout: float):
        return next(handed_out)

    async def fake_putconn(conn, from_getconn: bool):
        discarded.append((conn, from_getconn))

    monkeypatch.setattr(pool, "_getconn_unchecked", fake_getconn_unchecked)
    monkeypatch.setattr(pool, "_putconn", fake_putconn)

    conn = await pool._getconn_with_check_loop(monotonic() + 1.0)

    assert conn is healthy_conn
    assert discarded == [(stale_conn, True)]


@pytest.mark.anyio
async def test_test_session_setting_remains_per_checkout(monkeypatch):
    fake_conn = FakeAsyncConnection()
    checkout_calls: list[str] = []
    applied_to: list[FakeAsyncConnection] = []

    @asynccontextmanager
    async def fake_super_connection(self, *args, **kwargs):
        checkout_calls.append("checkout")
        yield fake_conn

    async def fake_apply(conn):
        applied_to.append(conn)

    monkeypatch.setattr(db.AsyncConnectionPool, "connection", fake_super_connection)
    monkeypatch.setattr(db, "_apply_test_session_setting", fake_apply)

    pool = db.ContextAwareAsyncConnectionPool(
        conninfo="postgresql://unused",
        min_size=1,
        max_size=1,
        check=db.ContextAwareAsyncConnectionPool.check_connection,
        open=False,
    )

    async with pool.connection() as conn:
        assert conn is fake_conn

    async with pool.connection() as conn:
        assert conn is fake_conn

    assert checkout_calls == ["checkout", "checkout"]
    assert applied_to == [fake_conn, fake_conn]
    assert pool._configure is None
