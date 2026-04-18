from __future__ import annotations

from pathlib import Path

from app.repositories import media_assets as media_assets_repo
from app.services import course_drip_worker, mvp_worker


def test_media_worker_selected_columns_are_materialized_by_baseline() -> None:
    slot_v2_0003 = Path(
        "backend/supabase/baseline_v2_slots/V2_0003_media_assets.sql"
    ).read_text(encoding="utf-8")
    slot_v2_0013 = Path(
        "backend/supabase/baseline_v2_slots/V2_0013_workers.sql"
    ).read_text(encoding="utf-8")
    baseline_sql = f"{slot_v2_0003}\n{slot_v2_0013}".lower()

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


def test_course_drip_worker_uses_v2_enrollment_worker_signature() -> None:
    source = Path(course_drip_worker.__file__).read_text(encoding="utf-8")
    normalized = " ".join(source.split())
    worker_function = "canonical_worker_advance_course_enrollment_drip"
    legacy_one_argument_call = f"{worker_function}(%s)"
    legacy_count_alias = "advanced" + "_count"

    assert f"{worker_function}(%s, %s)" in normalized
    assert legacy_one_argument_call not in normalized
    assert legacy_count_alias not in normalized


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


def test_backend_lifespan_excludes_paused_livekit_worker() -> None:
    source = Path("backend/app/main.py").read_text(encoding="utf-8")

    assert '"livekit_webhooks"' not in source
    assert "livekit_events.start_worker" not in source
