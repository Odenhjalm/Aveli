from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import pytest

from app.repositories import media_assets as media_assets_repo
from app.services import course_drip_worker, mvp_worker


def test_media_worker_selected_columns_are_materialized_by_baseline() -> None:
    slot_0007 = Path(
        "backend/supabase/baseline_slots/0007_media_assets_core.sql"
    ).read_text(encoding="utf-8")
    slot_0033 = Path(
        "backend/supabase/baseline_slots/0033_media_worker_operational_metadata.sql"
    ).read_text(encoding="utf-8")
    baseline_sql = f"{slot_0007}\n{slot_0033}".lower()

    for column in {
        "id",
        "media_type",
        "purpose",
        "original_object_path",
        "ingest_format",
        "state",
        *media_assets_repo._QUEUE_SUPPORT_REQUIRED_COLUMNS,
    }:
        assert column in baseline_sql

    worker_sql = media_assets_repo._MEDIA_TRANSCODE_WORKER_SQL
    assert "processing_attempts" in worker_sql
    assert "storage_bucket" not in worker_sql
    assert "original_filename" not in worker_sql
    assert "course_id" not in worker_sql


@pytest.mark.anyio("asyncio")
async def test_course_drip_worker_calls_canonical_worker_function(monkeypatch) -> None:
    fixed_now = datetime(2026, 4, 13, 12, 0, tzinfo=timezone.utc)
    calls: dict[str, object] = {}

    class FakeCursor:
        async def execute(self, query: str, params: tuple[object, ...]) -> None:
            calls["query"] = query
            calls["params"] = params

        async def fetchone(self) -> dict[str, int]:
            return {"advanced_count": 2}

    @asynccontextmanager
    async def fake_get_conn():
        yield FakeCursor()

    monkeypatch.setattr(course_drip_worker, "get_conn", fake_get_conn)

    advanced = await course_drip_worker.run_once(now=fixed_now)

    assert advanced == 2
    assert "canonical_worker_advance_course_enrollment_drip" in str(calls["query"])
    assert calls["params"] == (fixed_now,)


def test_mvp_worker_process_excludes_non_mvp_workers() -> None:
    source = Path(mvp_worker.__file__).read_text(encoding="utf-8")
    fly_config = Path("fly.toml").read_text(encoding="utf-8")

    assert "media_transcode_worker.start_worker" in source
    assert "course_drip_worker.start_worker" in source
    assert "livekit" not in source.lower()
    assert "membership" not in source.lower()

    assert "python -m app.services.mvp_worker" in fly_config
    assert "RUN_MEDIA_WORKER=true" in fly_config
    assert "RUN_COURSE_DRIP_WORKER=true" in fly_config
