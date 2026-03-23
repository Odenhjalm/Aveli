from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock

import pytest

from app.config import Settings


def test_settings_use_explicit_production_database_for_mcp_mode(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://postgres:pw@localhost:5432/aveli_local")
    monkeypatch.delenv("SUPABASE_DB_URL", raising=False)
    monkeypatch.setenv("MCP_MODE", "production")
    monkeypatch.setenv(
        "MCP_PRODUCTION_DATABASE_URL",
        "postgresql://postgres.prodref:pw@db.prodref.supabase.co:5432/postgres?sslmode=require",
    )

    settings = Settings()

    assert settings.mcp_production_mode is True
    assert settings.mcp_workers_enabled is False
    assert settings.database_url is not None
    assert (
        settings.database_url.unicode_string()
        == "postgresql://postgres.prodref:pw@db.prodref.supabase.co:5432/postgres?sslmode=require"
    )
    assert settings.mcp_environment == {
        "mcp_mode": "production",
        "production_data": True,
        "access_mode": "read_only",
    }


def test_settings_require_explicit_production_database_for_mcp_mode(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://postgres:pw@localhost:5432/aveli_local")
    monkeypatch.delenv("SUPABASE_DB_URL", raising=False)
    monkeypatch.setenv("MCP_MODE", "production")
    monkeypatch.delenv("MCP_PRODUCTION_DATABASE_URL", raising=False)
    monkeypatch.delenv("MCP_PRODUCTION_SUPABASE_DB_URL", raising=False)

    with pytest.raises(ValueError, match="MCP_MODE=production requires"):
        Settings()


@pytest.mark.anyio("asyncio")
async def test_media_transcode_worker_enablement_follows_mcp_mode(monkeypatch):
    from app.services import media_transcode_worker as worker

    async def fake_poll_loop() -> None:
        return None

    release_locks = AsyncMock(return_value=0)

    monkeypatch.delenv("RUN_MEDIA_WORKER", raising=False)
    monkeypatch.setattr(worker.settings, "mcp_mode", "local", raising=False)
    monkeypatch.setattr(worker, "_worker_task", None, raising=False)
    monkeypatch.setattr(worker, "_poll_loop", fake_poll_loop, raising=True)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "release_processing_media_assets",
        release_locks,
        raising=True,
    )

    await worker.start_worker()
    await asyncio.sleep(0)

    assert worker._enablement_state() == {
        "enabled_by_mcp_mode": True,
        "enabled_by_env": False,
        "enabled_by_config": True,
        "final_state": True,
    }
    assert worker._worker_task is not None
    release_locks.assert_awaited_once()

    worker._worker_task = None

    monkeypatch.setattr(worker.settings, "mcp_mode", "production", raising=False)
    release_locks.reset_mock()

    await worker.start_worker()

    assert worker._enablement_state() == {
        "enabled_by_mcp_mode": False,
        "enabled_by_env": False,
        "enabled_by_config": False,
        "final_state": False,
    }
    assert worker._worker_task is None
    release_locks.assert_not_awaited()


@pytest.mark.anyio("asyncio")
async def test_media_transcode_worker_env_override_can_force_enable(monkeypatch):
    from app.services import media_transcode_worker as worker

    async def fake_poll_loop() -> None:
        return None

    release_locks = AsyncMock(return_value=0)

    monkeypatch.setenv("RUN_MEDIA_WORKER", "1")
    monkeypatch.setattr(worker.settings, "mcp_mode", "production", raising=False)
    monkeypatch.setattr(worker, "_worker_task", None, raising=False)
    monkeypatch.setattr(worker, "_poll_loop", fake_poll_loop, raising=True)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "release_processing_media_assets",
        release_locks,
        raising=True,
    )

    await worker.start_worker()
    await asyncio.sleep(0)

    assert worker._enablement_state() == {
        "enabled_by_mcp_mode": False,
        "enabled_by_env": True,
        "enabled_by_config": False,
        "final_state": True,
    }
    assert worker._worker_task is not None
    release_locks.assert_awaited_once()

    worker._worker_task = None


@pytest.mark.anyio("asyncio")
async def test_lifespan_skips_background_workers_in_mcp_production_mode(
    monkeypatch,
    tmp_path,
):
    from app import main

    pool_open = AsyncMock()
    pool_close = AsyncMock()
    livekit_start = AsyncMock()
    livekit_stop = AsyncMock()
    transcode_start = AsyncMock()
    transcode_stop = AsyncMock()
    membership_start = AsyncMock()
    membership_stop = AsyncMock()

    monkeypatch.setattr(main.pool, "open", pool_open)
    monkeypatch.setattr(main.pool, "close", pool_close)
    monkeypatch.setattr(main.livekit_events, "start_worker", livekit_start)
    monkeypatch.setattr(main.livekit_events, "stop_worker", livekit_stop)
    monkeypatch.setattr(main.media_transcode_worker, "start_worker", transcode_start)
    monkeypatch.setattr(main.media_transcode_worker, "stop_worker", transcode_stop)
    monkeypatch.setattr(
        main.membership_expiry_warnings,
        "start_worker",
        membership_start,
    )
    monkeypatch.setattr(
        main.membership_expiry_warnings,
        "stop_worker",
        membership_stop,
    )
    monkeypatch.setattr(main.settings, "mcp_mode", "production", raising=False)
    monkeypatch.setattr(main.settings, "media_root", str(tmp_path / "media"), raising=False)

    async with main.lifespan(main.app):
        pass

    pool_open.assert_awaited_once()
    pool_close.assert_awaited_once()
    livekit_start.assert_not_awaited()
    transcode_start.assert_not_awaited()
    membership_start.assert_not_awaited()
    livekit_stop.assert_not_awaited()
    transcode_stop.assert_not_awaited()
    membership_stop.assert_not_awaited()
