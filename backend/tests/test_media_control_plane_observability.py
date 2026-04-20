from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from app.media_control_plane.services.media_resolver_service import (
    RuntimeMediaPlaybackMode,
    RuntimeMediaResolution,
    RuntimeMediaResolutionReason,
)
from app.repositories import courses as courses_repo
from app.services import media_control_plane_observability as service


pytestmark = pytest.mark.anyio("asyncio")


def _dt(hour: int, minute: int = 0, second: int = 0) -> datetime:
    return datetime(2026, 3, 23, hour, minute, second, tzinfo=timezone.utc)


def _asset_row(
    asset_id: str,
    *,
    lesson_id: str = "lesson-1",
    media_type: str = "audio",
    purpose: str = "lesson_audio",
    state: str = "ready",
    created_at: datetime | None = None,
    updated_at: datetime | None = None,
    error_message: str | None = None,
) -> dict:
    return {
        "id": asset_id,
        "course_id": "course-1",
        "lesson_id": lesson_id,
        "media_type": media_type,
        "purpose": purpose,
        "ingest_format": "upload",
        "original_object_path": f"source/{asset_id}.wav",
        "original_content_type": "audio/wav",
        "original_size_bytes": 1234,
        "storage_bucket": "course-media",
        "playback_object_path": f"derived/{asset_id}.mp3",
        "playback_format": "mp3",
        "duration_seconds": 42,
        "codec": "aac",
        "state": state,
        "error_message": error_message,
        "processing_attempts": 0,
        "processing_locked_at": None,
        "next_retry_at": None,
        "created_at": created_at or _dt(12, 0, 0),
        "updated_at": updated_at or _dt(12, 5, 0),
    }


def _lesson_media_row(
    lesson_media_id: str,
    *,
    lesson_id: str = "lesson-1",
    asset_id: str = "asset-1",
    media_id: str | None = "media-1",
    kind: str = "audio",
    created_at: datetime | None = None,
    runtime_contract_storage_path: str | None = None,
    runtime_contract_storage_bucket: str | None = None,
) -> dict:
    return {
        "id": lesson_media_id,
        "lesson_id": lesson_id,
        "kind": kind,
        "storage_path": "rendered/path.mp3",
        "storage_bucket": "lesson-media",
        "media_id": media_id,
        "media_asset_id": asset_id,
        "position": 1,
        "runtime_contract_storage_path": runtime_contract_storage_path,
        "runtime_contract_storage_bucket": runtime_contract_storage_bucket,
        "duration_seconds": 42,
        "content_type": "audio/mpeg",
        "media_state": "ready",
        "ingest_format": "upload",
        "playback_format": "mp3",
        "codec": "aac",
        "error_message": None,
        "issue_reason": None,
        "issue_details": {},
        "issue_updated_at": None,
        "created_at": created_at or _dt(12, 1, 0),
    }


def _runtime_row(
    runtime_media_id: str,
    *,
    lesson_media_id: str = "lm-1",
    lesson_id: str = "lesson-1",
    asset_id: str = "asset-1",
    media_object_id: str | None = "media-1",
    reference_type: str = "lesson_media",
    auth_scope: str = "lesson_course",
    fallback_policy: str = "never",
    legacy_storage_bucket: str | None = None,
    legacy_storage_path: str | None = None,
    kind: str = "audio",
    active: bool = True,
    created_at: datetime | None = None,
    updated_at: datetime | None = None,
) -> dict:
    return {
        "id": runtime_media_id,
        "reference_type": reference_type,
        "auth_scope": auth_scope,
        "fallback_policy": fallback_policy,
        "lesson_media_id": lesson_media_id,
        "home_player_upload_id": None,
        "teacher_id": None,
        "course_id": "course-1",
        "lesson_id": lesson_id,
        "media_asset_id": asset_id,
        "media_object_id": media_object_id,
        "legacy_storage_bucket": legacy_storage_bucket,
        "legacy_storage_path": legacy_storage_path,
        "kind": kind,
        "active": active,
        "created_at": created_at or _dt(12, 2, 0),
        "updated_at": updated_at or _dt(12, 3, 0),
    }


def _playable_resolution(
    runtime_media_id: str,
    *,
    lesson_media_id: str = "lm-1",
    lesson_id: str = "lesson-1",
    asset_id: str = "asset-1",
) -> RuntimeMediaResolution:
    return RuntimeMediaResolution(
        lesson_media_id=lesson_media_id,
        media_asset_id=asset_id,
        media_type="audio",
        content_type="audio/mpeg",
        media_state="ready",
        storage_bucket="course-media",
        storage_path="derived/demo.mp3",
        is_playable=True,
        playback_mode=RuntimeMediaPlaybackMode.PIPELINE_ASSET,
        failure_reason=RuntimeMediaResolutionReason.OK_READY_ASSET,
        lesson_id=lesson_id,
        runtime_media_id=runtime_media_id,
        duration_seconds=42,
    )


async def _storage_catalog_present(
    pairs: list[tuple[str, str]],
) -> tuple[dict[tuple[str, str], dict | None], bool]:
    return {pair: None for pair in pairs}, True


async def test_list_lesson_media_for_asset_reads_authored_placement_only(monkeypatch):
    row = {
        "id": "lm-1",
        "lesson_id": "lesson-1",
        "kind": None,
        "position": 1,
        "media_asset_id": "asset-1",
        "media_state": "ready",
        "content_type": None,
        "duration_seconds": None,
        "error_message": None,
        "issue_reason": None,
        "issue_details": None,
        "issue_updated_at": None,
        "created_at": None,
        "storage_bucket": None,
        "storage_path": None,
    }

    class _FakeCursor:
        def __init__(self) -> None:
            self.executed: list[tuple[str, tuple[object, ...]]] = []

        async def execute(
            self,
            query: str,
            params: tuple[object, ...] | list[object] | None = None,
        ) -> None:
            self.executed.append((" ".join(query.split()), tuple(params or ())))

        async def fetchall(self) -> list[dict[str, object | None]]:
            return [row]

    class _FakeConnection:
        def __init__(self, cursor: _FakeCursor) -> None:
            self._cursor = cursor

        def cursor(self, row_factory=None):  # noqa: ANN001
            del row_factory

            @asynccontextmanager
            async def _cursor_ctx():
                yield self._cursor

            return _cursor_ctx()

    class _FakePool:
        def __init__(self, cursor: _FakeCursor) -> None:
            self._cursor = cursor

        def connection(self):
            @asynccontextmanager
            async def _connection_ctx():
                yield _FakeConnection(self._cursor)

            return _connection_ctx()

    cursor = _FakeCursor()
    monkeypatch.setattr(courses_repo, "pool", _FakePool(cursor), raising=True)

    result = await courses_repo.list_lesson_media_for_asset("asset-1", limit=27)

    assert result == [row]
    assert cursor.executed == [
        (
            "select lm.id, lm.lesson_id, null::text as kind, lm.position, lm.media_asset_id, "
            "ma.state::text as media_state, null::text as content_type, null::integer as duration_seconds, "
            "null::text as error_message, null::text as issue_reason, null::jsonb as issue_details, "
            "null::timestamptz as issue_updated_at, null::timestamptz as created_at, null::text as storage_bucket, "
            "null::text as storage_path from app.lesson_media as lm join app.media_assets as ma on ma.id = lm.media_asset_id "
            "where lm.media_asset_id = %s::uuid order by lm.position asc, lm.id asc limit %s",
            ("asset-1", 27),
        )
    ]
    assert "app.runtime_media" not in cursor.executed[0][0]
    assert "lm.kind" not in cursor.executed[0][0]
    assert "lm.storage_path" not in cursor.executed[0][0]


async def test_validate_runtime_projection_reports_field_level_contract_diffs(monkeypatch):
    lesson_row = {
        "id": "lesson-1",
        "course_id": "course-1",
        "title": "Lesson",
        "position": 1,
        "is_intro": False,
        "created_at": _dt(11, 0, 0),
        "updated_at": _dt(11, 30, 0),
    }
    lesson_media_row = _lesson_media_row("lm-1")
    runtime_row = _runtime_row(
        "rm-1",
        auth_scope="home_teacher_library",
        fallback_policy="if_no_ready_asset",
        media_object_id="media-9",
        legacy_storage_bucket="lesson-media",
        legacy_storage_path="legacy/demo.mp3",
        kind="video",
        active=False,
    )
    runtime_row["course_id"] = "course-9"

    async def _get_lesson(_: str):
        return lesson_row

    async def _list_lesson_media(_: str, *, limit: int):
        assert limit == 101
        return [lesson_media_row]

    async def _list_runtime_media(_: str, *, limit: int):
        assert limit == 101
        return [runtime_row]

    async def _get_media_assets(_: list[str]):
        return {
            "asset-1": _asset_row("asset-1"),
        }

    async def _inspect_runtime_media(runtime_media_id: str):
        return _playable_resolution(runtime_media_id)

    monkeypatch.setattr(service.courses_repo, "get_lesson", _get_lesson)
    monkeypatch.setattr(service.courses_repo, "list_lesson_media", _list_lesson_media)
    monkeypatch.setattr(
        service.runtime_media_repo,
        "list_runtime_media_for_lesson",
        _list_runtime_media,
    )
    monkeypatch.setattr(service.media_assets_repo, "get_media_assets", _get_media_assets)
    monkeypatch.setattr(
        service.media_resolver_service,
        "inspect_runtime_media",
        _inspect_runtime_media,
    )
    monkeypatch.setattr(
        service.storage_objects,
        "fetch_storage_object_details",
        _storage_catalog_present,
    )

    result = await service.validate_runtime_projection("lesson-1")

    item = result["lesson_media"][0]
    assert result["validation"] == {
        "validation_mode": "strict_contract",
        "evaluated_at": result["generated_at"],
        "data_freshness": "snapshot",
    }
    assert result["storage_verification"]["confidence"] in {
        "full",
        "partial",
        "unavailable",
    }
    assert result["state_classification"] == "inconsistent"
    assert item["state_classification"] == "inconsistent"
    assert item["expected_runtime_contract"] == {
        "reference_type": "lesson_media",
        "auth_scope": "lesson_course",
        "course_id": "course-1",
        "lesson_id": "lesson-1",
        "media_asset_id": "asset-1",
        "kind": "audio",
        "active": True,
    }
    assert [diff["field"] for diff in item["contract_diffs"]] == [
        "auth_scope",
        "course_id",
        "kind",
        "active",
    ]
    assert any(
        inconsistency["code"] == "runtime_contract_mismatch"
        for inconsistency in item["detected_inconsistencies"]
    )


async def test_trace_asset_lifecycle_marks_snapshot_transitions_as_reconstructed(monkeypatch):
    snapshot = {
        "asset_id": "asset-1",
        "asset": {"asset_id": "asset-1", "state": "ready"},
        "state_classification": "projected_ready",
        "detected_inconsistencies": [],
        "storage_verification": {
            "storage_catalog_available": True,
            "confidence": "full",
            "checks": [],
        },
        "raw": {
            "asset_rows": [_asset_row("asset-1", created_at=_dt(12, 0, 0), updated_at=_dt(12, 4, 0))],
            "lesson_media_rows": [
                _lesson_media_row("lm-1", created_at=_dt(12, 1, 0)),
            ],
            "runtime_rows": [
                _runtime_row("rm-1", created_at=_dt(12, 2, 0), updated_at=_dt(12, 3, 0)),
            ],
        },
    }

    async def _collect_asset_snapshot(_: str):
        return snapshot

    async def _list_recent_media_resolution_failures(*, limit: int, media_asset_id: str):
        assert limit == 25
        assert media_asset_id == "asset-1"
        return [
            {
                "created_at": _dt(12, 5, 0),
                "lesson_media_id": "lm-1",
                "lesson_id": "lesson-1",
                "media_asset_id": "asset-1",
                "mode": "student_render",
                "reason": "missing_object",
                "details": {},
            }
        ]

    monkeypatch.setattr(service, "_collect_asset_snapshot", _collect_asset_snapshot)
    monkeypatch.setattr(
        service.media_resolution_failures_repo,
        "list_recent_media_resolution_failures",
        _list_recent_media_resolution_failures,
    )
    monkeypatch.setattr(service.log_buffer, "list_events", lambda **_: [])

    result = await service.trace_asset_lifecycle("asset-1")

    assert result["validation"] == {
        "validation_mode": "strict_contract",
        "evaluated_at": result["generated_at"],
        "data_freshness": "snapshot",
    }
    assert result["storage_verification"] == snapshot["storage_verification"]
    assert result["storage_verification"]["confidence"] in {
        "full",
        "partial",
        "unavailable",
    }
    assert result["timeline_mode"] == "reconstructed_snapshot_timeline"
    snapshot_transitions = [
        transition
        for transition in result["state_transitions"]
        if transition["source"] in {"media_assets", "lesson_media", "runtime_media"}
    ]
    assert snapshot_transitions
    assert all(
        transition["certainty"] in {"inferred", "reconstructed"}
        for transition in snapshot_transitions
    )
    observed_transitions = [
        transition
        for transition in result["state_transitions"]
        if transition["source"] == "media_resolution_failures"
    ]
    assert observed_transitions
    assert all(transition["certainty"] == "observed" for transition in observed_transitions)


async def test_list_orphaned_assets_exposes_grace_window_and_runtime_gap(monkeypatch):
    fixed_now = _dt(13, 0, 0)
    rows = [
        _asset_row(
            "asset-awaiting",
            state="uploaded",
            updated_at=fixed_now - timedelta(minutes=5),
        )
        | {
            "lesson_media_count": 0,
            "runtime_media_count": 0,
            "home_player_upload_count": 0,
        },
        _asset_row(
            "asset-stalled",
            state="processing",
            updated_at=fixed_now - timedelta(hours=2),
        )
        | {
            "lesson_media_count": 0,
            "runtime_media_count": 0,
            "home_player_upload_count": 0,
        },
        _asset_row(
            "asset-gap",
            purpose="home_player_audio",
            state="ready",
            updated_at=fixed_now - timedelta(minutes=20),
        )
        | {
            "lesson_media_count": 0,
            "runtime_media_count": 0,
            "home_player_upload_count": 1,
        },
    ]

    async def _list_orphaned_control_plane_assets(*, limit: int):
        assert limit == 101
        return rows

    monkeypatch.setattr(service, "_now", lambda: fixed_now)
    monkeypatch.setattr(
        service.media_assets_repo,
        "list_orphaned_control_plane_assets",
        _list_orphaned_control_plane_assets,
    )

    result = await service.list_orphaned_assets()

    assert result["validation"] == {
        "validation_mode": "strict_contract",
        "evaluated_at": result["generated_at"],
        "data_freshness": "snapshot",
    }
    assert result["inspection_scope"] == "unlinked_control_plane_assets"
    assert result["state_classification"] == "inconsistent"
    assert result["summary"]["grace_window_seconds"] == 1800
    classifications = {
        item["asset"]["asset_id"]: item["state_classification"]
        for item in result["orphaned_assets"]
    }
    assert classifications == {
        "asset-awaiting": "awaiting_link",
        "asset-stalled": "unlinked_stalled",
        "asset-gap": "strict_orphan",
    }
    stalled_item = next(
        item
        for item in result["orphaned_assets"]
        if item["asset"]["asset_id"] == "asset-stalled"
    )
    assert stalled_item["linkage_timing"]["within_grace_window"] is False


async def test_validate_runtime_projection_sorts_correlation_asset_ids(monkeypatch):
    lesson_row = {
        "id": "lesson-1",
        "course_id": "course-1",
        "title": "Lesson",
        "position": 1,
        "is_intro": False,
        "created_at": _dt(11, 0, 0),
        "updated_at": _dt(11, 30, 0),
    }
    lesson_media_rows = [
        _lesson_media_row("lm-b", asset_id="asset-b", created_at=_dt(12, 2, 0)),
        _lesson_media_row("lm-a", asset_id="asset-a", created_at=_dt(12, 1, 0)),
    ]

    async def _get_lesson(_: str):
        return lesson_row

    async def _list_lesson_media(_: str, *, limit: int):
        return lesson_media_rows

    async def _list_runtime_media(_: str, *, limit: int):
        return []

    async def _get_media_assets(_: list[str]):
        return {
            "asset-b": _asset_row("asset-b", updated_at=_dt(12, 6, 0)),
            "asset-a": _asset_row("asset-a", updated_at=_dt(12, 5, 0)),
        }

    monkeypatch.setattr(service.courses_repo, "get_lesson", _get_lesson)
    monkeypatch.setattr(service.courses_repo, "list_lesson_media", _list_lesson_media)
    monkeypatch.setattr(
        service.runtime_media_repo,
        "list_runtime_media_for_lesson",
        _list_runtime_media,
    )
    monkeypatch.setattr(service.media_assets_repo, "get_media_assets", _get_media_assets)
    monkeypatch.setattr(
        service.storage_objects,
        "fetch_storage_object_details",
        _storage_catalog_present,
    )

    result = await service.validate_runtime_projection("lesson-1")

    assert result["correlation"]["asset_ids"] == ["asset-a", "asset-b"]
    assert result["storage_verification"]["confidence"] in {
        "full",
        "partial",
        "unavailable",
    }


async def test_get_asset_adds_validation_metadata_and_storage_confidence(monkeypatch):
    snapshot = {
        "asset_id": "asset-1",
        "state_classification": "projected_ready",
        "detected_inconsistencies": [],
        "asset": {"asset_id": "asset-1", "state": "ready"},
        "lesson_media_references": [],
        "runtime_projection": [],
        "storage_verification": {
            "storage_catalog_available": True,
            "confidence": "full",
            "checks": [],
        },
        "correlation": {
            "asset_ids": ["asset-1"],
            "lesson_ids": [],
            "lesson_media_ids": [],
            "runtime_media_ids": [],
            "timestamps": [],
            "state_transitions": [],
        },
        "truncation": {
            "lesson_media_references_truncated": False,
            "runtime_projection_truncated": False,
        },
    }

    async def _collect_asset_snapshot(_: str):
        return snapshot

    monkeypatch.setattr(service, "_collect_asset_snapshot", _collect_asset_snapshot)

    result = await service.get_asset("asset-1")

    assert result["validation"] == {
        "validation_mode": "strict_contract",
        "evaluated_at": result["generated_at"],
        "data_freshness": "snapshot",
    }
    assert result["storage_verification"]["confidence"] == "full"


async def test_get_asset_missing_snapshot_reports_storage_verification_unavailable(monkeypatch):
    async def _get_media_asset(_: str):
        return None

    monkeypatch.setattr(service.media_assets_repo, "get_media_asset", _get_media_asset)

    result = await service.get_asset("missing-asset")

    assert result["storage_verification"] == {
        "storage_catalog_available": False,
        "confidence": "unavailable",
        "checks": [],
    }


async def test_get_asset_failed_unlinked_home_audio_without_active_upload_is_not_inconsistent(
    monkeypatch,
):
    async def _get_media_asset(_: str):
        return _asset_row(
            "asset-home",
            lesson_id=None,
            purpose="home_player_audio",
            state="failed",
            error_message="missing_source",
        )

    async def _list_lesson_media_for_asset(_: str, *, limit: int):
        assert limit == 26
        return []

    async def _list_runtime_media_for_asset(_: str, *, limit: int):
        assert limit == 26
        return []

    async def _get_active_home_upload_by_media_asset_id(_: str):
        return None

    monkeypatch.setattr(service.media_assets_repo, "get_media_asset", _get_media_asset)
    monkeypatch.setattr(
        service.courses_repo,
        "list_lesson_media_for_asset",
        _list_lesson_media_for_asset,
    )
    monkeypatch.setattr(
        service.runtime_media_repo,
        "list_runtime_media_for_asset",
        _list_runtime_media_for_asset,
    )
    monkeypatch.setattr(
        service.home_audio_sources_repo,
        "get_active_home_upload_by_media_asset_id",
        _get_active_home_upload_by_media_asset_id,
    )
    monkeypatch.setattr(
        service.storage_objects,
        "fetch_storage_object_details",
        _storage_catalog_present,
    )

    result = await service.get_asset("asset-home")

    assert result["state_classification"] == "failed_unlinked"
    assert not any(
        item["code"] == "home_runtime_projection_missing"
        for item in result["detected_inconsistencies"]
    )


async def test_get_asset_failed_home_audio_with_active_upload_requires_runtime_projection(
    monkeypatch,
):
    async def _get_media_asset(_: str):
        return _asset_row(
            "asset-home",
            lesson_id=None,
            purpose="home_player_audio",
            state="failed",
            error_message="missing_source",
        )

    async def _list_lesson_media_for_asset(_: str, *, limit: int):
        assert limit == 26
        return []

    async def _list_runtime_media_for_asset(_: str, *, limit: int):
        assert limit == 26
        return []

    async def _get_active_home_upload_by_media_asset_id(_: str):
        return {
            "teacher_id": "teacher-1",
            "active": True,
            "media_asset_id": "asset-home",
            "state": "failed",
        }

    monkeypatch.setattr(service.media_assets_repo, "get_media_asset", _get_media_asset)
    monkeypatch.setattr(
        service.courses_repo,
        "list_lesson_media_for_asset",
        _list_lesson_media_for_asset,
    )
    monkeypatch.setattr(
        service.runtime_media_repo,
        "list_runtime_media_for_asset",
        _list_runtime_media_for_asset,
    )
    monkeypatch.setattr(
        service.home_audio_sources_repo,
        "get_active_home_upload_by_media_asset_id",
        _get_active_home_upload_by_media_asset_id,
    )
    monkeypatch.setattr(
        service.storage_objects,
        "fetch_storage_object_details",
        _storage_catalog_present,
    )

    result = await service.get_asset("asset-home")

    assert result["state_classification"] == "asset_failed"
    assert not any(
        item["code"] == "home_runtime_projection_missing"
        for item in result["detected_inconsistencies"]
    )


async def test_media_control_plane_docs_cover_hardened_contract_states():
    docs_path = (
        Path(__file__).resolve().parents[2]
        / "archive"
        / "docs"
        / "media_control_plane_mcp.md"
    )
    text = docs_path.read_text(encoding="utf-8")

    for token in (
        "validation_mode",
        "data_freshness",
        "timeline_mode",
        "inspection_scope",
        "\"confidence\": \"full | partial | unavailable\"",
        "Storage verification confidence",
        "When at least one storage lookup was skipped",
        "\"storage_verification\": {",
        "strict_orphan",
        "failed_unlinked",
        "unlinked_stalled",
        "expected_runtime_contract",
        "actual_runtime_contract",
        "contract_diffs",
        "unresolved",
        "runtime_rows_without_lesson_media_count",
    ):
        assert token in text
