from __future__ import annotations

import pytest

from app.services.domain_observability import media_inspection


pytestmark = pytest.mark.anyio("asyncio")


async def test_inspect_media_asset_keeps_worker_health_out_of_status(monkeypatch):
    async def _fake_get_asset(asset_id: str):
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "asset_id": asset_id,
            "state_classification": "projected_ready",
            "detected_inconsistencies": [],
            "asset": {
                "asset_id": asset_id,
                "lesson_id": "lesson-123",
                "state": "ready",
            },
            "lesson_media_references": [{"lesson_media_id": "lm-1"}],
            "runtime_projection": [{"runtime_media_id": "rm-1"}],
        }

    async def _fake_get_media_failures(*, asset_id: str | None = None):
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "asset_id": asset_id,
            "media_failures": [],
            "summary": {},
        }

    async def _fake_get_worker_health():
        return {
            "generated_at": "2026-03-23T12:00:00+00:00",
            "worker_health": {
                "media_transcode": {
                    "status": "degraded",
                    "worker_running": True,
                    "queue_summary": {"uploaded": 48, "failed": 0},
                    "last_error": {"message": "Historical worker error"},
                },
            },
        }

    monkeypatch.setattr(
        media_inspection.media_control_plane_observability,
        "get_asset",
        _fake_get_asset,
        raising=True,
    )
    monkeypatch.setattr(
        media_inspection.logs_observability,
        "get_media_failures",
        _fake_get_media_failures,
        raising=True,
    )
    monkeypatch.setattr(
        media_inspection.logs_observability,
        "get_worker_health",
        _fake_get_worker_health,
        raising=True,
    )

    result = await media_inspection.inspect_media(asset_id="asset-123")

    assert result["status"] == "ok"
    assert result["violations"] == []
    assert result["environment_signals"]["worker_status"] == "degraded"
    assert result["environment_signals"]["queue_summary"] == {"uploaded": 48, "failed": 0}
