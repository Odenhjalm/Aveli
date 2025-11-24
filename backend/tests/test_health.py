from contextlib import asynccontextmanager

import pytest


@pytest.mark.anyio("asyncio")
async def test_healthz(async_client):
    resp = await async_client.get("/healthz")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload.get("ok") is True


@pytest.mark.anyio("asyncio")
async def test_readyz(async_client):
    resp = await async_client.get("/readyz")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload.get("database") == "ready"


@pytest.mark.anyio("asyncio")
async def test_readyz_handles_db_failure(async_client, monkeypatch):
    @asynccontextmanager
    async def _broken_conn():
        raise RuntimeError("db down")
        yield

    monkeypatch.setattr("app.main.get_conn", _broken_conn)
    resp = await async_client.get("/readyz")
    assert resp.status_code == 503
    assert resp.json()["detail"] == "database unavailable"
