from __future__ import annotations

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.config import Settings


def _set_local_db_env(monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_HOST", "localhost")
    monkeypatch.setenv("DATABASE_PORT", "5432")
    monkeypatch.setenv("DATABASE_NAME", "aveli_local")
    monkeypatch.setenv("DATABASE_USER", "postgres")
    monkeypatch.setenv("DATABASE_PASSWORD", "pw")


def _clear_cloud_runtime_env(monkeypatch) -> None:
    for key in ("FLY_APP_NAME", "K_SERVICE", "AWS_EXECUTION_ENV", "DYNO"):
        monkeypatch.delenv(key, raising=False)


def test_settings_use_explicit_production_database_for_mcp_mode(monkeypatch):
    _clear_cloud_runtime_env(monkeypatch)
    _set_local_db_env(monkeypatch)
    monkeypatch.setenv("DATABASE_URL", "postgresql://postgres:pw@db:5432/ignored_by_settings")
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
    _clear_cloud_runtime_env(monkeypatch)
    _set_local_db_env(monkeypatch)
    monkeypatch.setenv("DATABASE_URL", "postgresql://postgres:pw@db:5432/ignored_by_settings")
    monkeypatch.delenv("SUPABASE_DB_URL", raising=False)
    monkeypatch.setenv("MCP_MODE", "production")
    monkeypatch.delenv("MCP_PRODUCTION_DATABASE_URL", raising=False)
    monkeypatch.delenv("MCP_PRODUCTION_SUPABASE_DB_URL", raising=False)

    with pytest.raises(ValueError, match="MCP_MODE=production requires"):
        Settings()


def test_settings_derive_local_database_url_from_components(monkeypatch):
    _clear_cloud_runtime_env(monkeypatch)
    _set_local_db_env(monkeypatch)
    monkeypatch.setenv("DATABASE_URL", "postgresql://postgres:pw@aveli-db:5432/ignored_by_settings")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.delenv("MCP_PRODUCTION_DATABASE_URL", raising=False)
    monkeypatch.delenv("MCP_PRODUCTION_SUPABASE_DB_URL", raising=False)

    settings = Settings()

    assert settings.database_url is not None
    assert (
        settings.database_url.unicode_string()
        == "postgresql://postgres:pw@localhost:5432/aveli_local"
    )


def test_settings_use_database_url_in_cloud_runtime_without_mcp_production(monkeypatch):
    _set_local_db_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql://postgres.prodref:pw@db.prodref.supabase.co:5432/postgres?sslmode=require",
    )
    monkeypatch.delenv("MCP_PRODUCTION_DATABASE_URL", raising=False)
    monkeypatch.delenv("MCP_PRODUCTION_SUPABASE_DB_URL", raising=False)

    settings = Settings(_env_file=None)

    assert settings.mcp_production_mode is False
    assert settings.database_url is not None
    assert (
        settings.database_url.unicode_string()
        == "postgresql://postgres.prodref:pw@db.prodref.supabase.co:5432/postgres?sslmode=require"
    )


def test_settings_reject_cloud_runtime_without_database_url(monkeypatch):
    _set_local_db_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("MCP_PRODUCTION_DATABASE_URL", raising=False)
    monkeypatch.delenv("MCP_PRODUCTION_SUPABASE_DB_URL", raising=False)

    with pytest.raises(ValueError, match="Cloud runtime requires DATABASE_URL"):
        Settings(_env_file=None)


def test_settings_reject_cloud_runtime_with_local_database_url(monkeypatch):
    _set_local_db_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.setenv("DATABASE_URL", "postgresql://postgres:pw@127.0.0.1:5432/aveli_local")
    monkeypatch.delenv("MCP_PRODUCTION_DATABASE_URL", raising=False)
    monkeypatch.delenv("MCP_PRODUCTION_SUPABASE_DB_URL", raising=False)

    with pytest.raises(
        ValueError, match="Refusing to start cloud runtime with local database target"
    ):
        Settings(_env_file=None)


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
async def test_livekit_worker_verification_mode_skips_write_paths(monkeypatch):
    from app.services import livekit_events

    release_jobs = AsyncMock()
    get_counts = AsyncMock(return_value={"pending": 2, "failed": 1})
    fetch_due = AsyncMock(return_value=[])

    monkeypatch.setattr(
        livekit_events.repositories,
        "release_processing_webhook_jobs",
        release_jobs,
        raising=True,
    )
    monkeypatch.setattr(
        livekit_events.repositories,
        "get_webhook_job_counts",
        get_counts,
        raising=True,
    )
    monkeypatch.setattr(
        livekit_events.repositories,
        "fetch_and_lock_due_webhook_jobs",
        fetch_due,
        raising=True,
    )
    monkeypatch.setattr(livekit_events, "_queue", None, raising=False)
    monkeypatch.setattr(livekit_events, "_worker_task", None, raising=False)
    monkeypatch.setattr(livekit_events, "_poller_task", None, raising=False)
    monkeypatch.setattr(livekit_events, "_verification_mode", False, raising=False)

    await livekit_events.start_worker(verification_mode=True)
    await asyncio.sleep(0)

    metrics = livekit_events.get_metrics()
    assert metrics["worker_running"] is True
    assert metrics["verification_mode"] is True
    assert metrics["write_suppressed"] is True
    assert metrics["pending_jobs"] == 2
    assert metrics["failed_jobs"] == 1
    release_jobs.assert_not_awaited()
    fetch_due.assert_not_awaited()
    get_counts.assert_awaited_once()

    await livekit_events.stop_worker()


@pytest.mark.anyio("asyncio")
async def test_media_transcode_worker_verification_mode_skips_release(monkeypatch):
    from app.services import media_transcode_worker as worker

    release_locks = AsyncMock(return_value=0)
    queue_supported = AsyncMock(return_value=True)
    queue_summary = AsyncMock(
        return_value={
            "pending_upload": 0,
            "uploaded": 0,
            "processing": 0,
            "failed": 0,
            "ready": 0,
            "stale_processing_locks": 0,
            "oldest_unfinished_created_at": None,
            "queue_contract_supported": True,
        }
    )

    monkeypatch.delenv("RUN_MEDIA_WORKER", raising=False)
    monkeypatch.setattr(worker.settings, "mcp_mode", "local", raising=False)
    monkeypatch.setattr(worker, "_worker_task", None, raising=False)
    monkeypatch.setattr(worker, "_verification_mode", False, raising=False)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "release_processing_media_assets",
        release_locks,
        raising=True,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "media_processing_queue_supported",
        queue_supported,
        raising=True,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "get_media_processing_worker_summary",
        queue_summary,
        raising=True,
    )

    await worker.start_worker(verification_mode=True)
    await asyncio.sleep(0)

    metrics = await worker.get_metrics()
    assert metrics["worker_running"] is True
    assert metrics["verification_mode"] is True
    assert metrics["write_suppressed"] is True
    assert metrics["final_state"] is True
    assert worker._worker_run_started_at is not None
    release_locks.assert_not_awaited()

    await worker.stop_worker()
    assert worker._worker_run_started_at is None


def test_membership_worker_metrics_scope_last_error_to_current_run(monkeypatch):
    from app.services import membership_expiry_warnings as worker

    seen: dict[str, object] = {}

    def fake_list_events(**kwargs):
        seen.update(kwargs)
        return [{"message": "current error"}]

    monkeypatch.setattr(worker, "_worker_task", SimpleNamespace(done=lambda: False), raising=False)
    monkeypatch.setattr(worker, "_worker_run_started_at", 123.0, raising=False)
    monkeypatch.setattr(worker, "_verification_mode", False, raising=False)
    monkeypatch.setattr(worker.log_buffer, "list_events", fake_list_events, raising=True)

    metrics = worker.get_metrics()

    assert seen["since_epoch_seconds"] == 123.0
    assert metrics["last_error"] == {"message": "current error"}


@pytest.mark.anyio("asyncio")
async def test_membership_worker_verification_mode_sets_and_resets_run_scope(monkeypatch):
    from app.services import membership_expiry_warnings as worker

    monkeypatch.setattr(worker, "_worker_task", None, raising=False)
    monkeypatch.setattr(worker, "_worker_run_started_at", None, raising=False)
    monkeypatch.setattr(worker, "_verification_mode", False, raising=False)

    await worker.start_worker(verification_mode=True)
    await asyncio.sleep(0)

    metrics = worker.get_metrics()
    assert metrics["worker_running"] is True
    assert metrics["verification_mode"] is True
    assert metrics["write_suppressed"] is True
    assert worker._worker_run_started_at is not None

    await worker.stop_worker()
    assert worker._worker_run_started_at is None


@pytest.mark.anyio("asyncio")
async def test_media_transcode_worker_metrics_scope_last_error_to_current_run(monkeypatch):
    from app.services import media_transcode_worker as worker

    seen: dict[str, object] = {}

    def fake_list_events(**kwargs):
        seen.update(kwargs)
        return [{"message": "current error"}]

    queue_supported = AsyncMock(return_value=True)
    queue_summary = AsyncMock(
        return_value={
            "pending_upload": 0,
            "uploaded": 0,
            "processing": 0,
            "failed": 0,
            "ready": 0,
            "stale_processing_locks": 0,
            "oldest_unfinished_created_at": None,
            "queue_contract_supported": True,
        }
    )

    monkeypatch.setattr(worker.settings, "mcp_mode", "local", raising=False)
    monkeypatch.setattr(worker, "_worker_task", SimpleNamespace(done=lambda: False), raising=False)
    monkeypatch.setattr(worker, "_worker_run_started_at", 456.0, raising=False)
    monkeypatch.setattr(worker, "_verification_mode", False, raising=False)
    monkeypatch.setattr(
        worker.media_assets_repo,
        "media_processing_queue_supported",
        queue_supported,
        raising=True,
    )
    monkeypatch.setattr(
        worker.media_assets_repo,
        "get_media_processing_worker_summary",
        queue_summary,
        raising=True,
    )
    monkeypatch.setattr(worker.log_buffer, "list_events", fake_list_events, raising=True)

    metrics = await worker.get_metrics()

    assert seen["since_epoch_seconds"] == 456.0
    assert metrics["last_error"] == {"message": "current error"}


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
    monkeypatch.setattr(main.settings, "runtime_verify_no_write", False, raising=False)
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


@pytest.mark.anyio("asyncio")
async def test_lifespan_starts_and_stops_background_workers_in_local_mode(
    monkeypatch,
    tmp_path,
):
    from app import main

    call_order: list[str] = []

    async def pool_open(*args, **kwargs):
        call_order.append("pool_open")

    async def pool_close(*args, **kwargs):
        call_order.append("pool_close")

    async def livekit_start(*, verification_mode=False):
        call_order.append(f"livekit_start:{verification_mode}")

    async def livekit_stop():
        call_order.append("livekit_stop")

    async def transcode_start(*, verification_mode=False):
        call_order.append(f"transcode_start:{verification_mode}")

    async def transcode_stop():
        call_order.append("transcode_stop")

    async def membership_start(*, verification_mode=False):
        call_order.append(f"membership_start:{verification_mode}")

    async def membership_stop():
        call_order.append("membership_stop")

    _clear_cloud_runtime_env(monkeypatch)
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
    monkeypatch.setattr(main.settings, "mcp_mode", "local", raising=False)
    monkeypatch.setattr(main.settings, "runtime_verify_no_write", False, raising=False)
    monkeypatch.setattr(main.settings, "media_root", str(tmp_path / "media"), raising=False)

    async with main.lifespan(main.app):
        assert call_order == [
            "pool_open",
            "livekit_start:False",
            "transcode_start:False",
            "membership_start:False",
        ]

    assert call_order == [
        "pool_open",
        "livekit_start:False",
        "transcode_start:False",
        "membership_start:False",
        "membership_stop",
        "transcode_stop",
        "livekit_stop",
        "pool_close",
    ]


@pytest.mark.anyio("asyncio")
async def test_lifespan_skips_background_workers_in_cloud_runtime(
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

    monkeypatch.setenv("FLY_APP_NAME", "aveli")
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
    monkeypatch.setattr(main.settings, "mcp_mode", "local", raising=False)
    monkeypatch.setattr(main.settings, "runtime_verify_no_write", False, raising=False)
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


@pytest.mark.anyio("asyncio")
async def test_lifespan_starts_background_workers_in_no_write_verification_mode(
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

    _clear_cloud_runtime_env(monkeypatch)
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
    monkeypatch.setattr(main.settings, "mcp_mode", "local", raising=False)
    monkeypatch.setattr(main.settings, "runtime_verify_no_write", True, raising=False)
    monkeypatch.setattr(main.settings, "media_root", str(tmp_path / "media"), raising=False)

    async with main.lifespan(main.app):
        pass

    pool_open.assert_awaited_once()
    pool_close.assert_awaited_once()
    livekit_start.assert_awaited_once_with(verification_mode=True)
    transcode_start.assert_awaited_once_with(verification_mode=True)
    membership_start.assert_awaited_once_with(verification_mode=True)
    membership_stop.assert_awaited_once()
    transcode_stop.assert_awaited_once()
    livekit_stop.assert_awaited_once()


@pytest.mark.anyio("asyncio")
async def test_logs_worker_health_reports_ok_in_no_write_verification_mode(monkeypatch):
    from app.services import logs_observability

    async def fake_transcode_metrics():
        return {
            "worker_running": True,
            "enabled_by_mcp_mode": True,
            "enabled_by_env": False,
            "enabled_by_config": True,
            "final_state": True,
            "poll_interval_seconds": 10,
            "batch_size": 3,
            "max_attempts": 5,
            "queue_summary": {
                "pending_upload": 0,
                "uploaded": 4,
                "processing": 0,
                "failed": 2,
                "ready": 0,
                "stale_processing_locks": 1,
                "oldest_unfinished_created_at": None,
            },
            "last_error": None,
            "verification_mode": True,
            "write_suppressed": True,
        }

    def fake_webhook_metrics():
        return {
            "worker_running": True,
            "queue_size": 0,
            "pending_jobs": 0,
            "failed_jobs": 3,
            "last_failure": None,
            "verification_mode": True,
            "write_suppressed": True,
        }

    async def fake_queue_snapshot():
        return {
            "pending": 0,
            "processing": 0,
            "failed": 3,
            "next_due_at": None,
            "last_failed_at": None,
        }

    def fake_membership_metrics():
        return {
            "worker_running": True,
            "poll_interval_seconds": 86400,
            "last_error": None,
            "verification_mode": True,
            "write_suppressed": True,
        }

    monkeypatch.setattr(
        logs_observability.media_transcode_worker,
        "get_metrics",
        fake_transcode_metrics,
        raising=True,
    )
    monkeypatch.setattr(
        logs_observability.livekit_events,
        "get_metrics",
        fake_webhook_metrics,
        raising=True,
    )
    monkeypatch.setattr(
        logs_observability.livekit_jobs_repo,
        "get_webhook_queue_snapshot",
        fake_queue_snapshot,
        raising=True,
    )
    monkeypatch.setattr(
        logs_observability.membership_expiry_warnings,
        "get_metrics",
        fake_membership_metrics,
        raising=True,
    )

    result = await logs_observability.get_worker_health()

    assert result["worker_health"]["media_transcode"]["status"] == "ok"
    assert result["worker_health"]["livekit_webhooks"]["status"] == "ok"
    assert result["worker_health"]["membership_expiry_warnings"]["status"] == "ok"
    assert result["worker_health"]["media_transcode"]["verification_mode"] is True
    assert result["worker_health"]["livekit_webhooks"]["write_suppressed"] is True
    assert result["worker_health"]["membership_expiry_warnings"]["verification_mode"] is True
