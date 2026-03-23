from __future__ import annotations

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
