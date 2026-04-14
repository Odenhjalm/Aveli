import pytest
from psycopg import errors

from app.repositories import membership_support


pytestmark = pytest.mark.anyio("asyncio")


class _MissingSupportTableCursor:
    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        return False

    async def execute(self, *args, **kwargs):
        raise errors.UndefinedTable("missing support table")

    async def fetchone(self):
        raise AssertionError("missing support table must not be treated as success")


class _MissingSupportTableConnection:
    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        return False

    def cursor(self):
        return _MissingSupportTableCursor()

    async def commit(self):
        raise AssertionError("missing support table must not commit")

    async def rollback(self):
        return None


class _MissingSupportTablePool:
    def connection(self):
        return _MissingSupportTableConnection()


async def test_payment_events_missing_table_fails_closed(monkeypatch) -> None:
    monkeypatch.setattr(membership_support, "pool", _MissingSupportTablePool())

    with pytest.raises(errors.UndefinedTable):
        await membership_support.claim_payment_event("evt_missing_table")


async def test_billing_logs_missing_table_fails_closed(monkeypatch) -> None:
    monkeypatch.setattr(membership_support, "pool", _MissingSupportTablePool())

    with pytest.raises(errors.UndefinedTable):
        await membership_support.insert_billing_log(
            user_id=None,
            step="webhook_received",
            info={"event_id": "evt_missing_table"},
        )
