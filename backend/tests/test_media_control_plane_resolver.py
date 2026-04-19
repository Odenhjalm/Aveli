from pathlib import Path

import pytest

from app.media_control_plane.services.media_resolver_service import (
    MediaResolverService,
    RuntimeMediaPlaybackMode,
    RuntimeMediaResolutionReason,
)


pytestmark = pytest.mark.anyio("asyncio")


def _contract_row(**overrides):
    row = {
        "runtime_media_id": "runtime-media-1",
        "lesson_media_id": "lesson-media-1",
        "course_id": "course-1",
        "lesson_id": "lesson-1",
        "media_asset_id": "asset-1",
        "media_type": "audio",
        "media_state": "ready",
        "playback_object_path": (
            "media/derived/audio/courses/demo/lessons/lesson-1/demo.mp3"
        ),
        "playback_format": "mp3",
        "storage_bucket": "course-media",
    }
    row.update(overrides)
    return row


def test_runtime_media_fetch_uses_projected_asset_state() -> None:
    source = (
        Path(__file__).resolve().parents[1]
        / "app/media_control_plane/services/media_resolver_service.py"
    ).read_text(encoding="utf-8")

    assert "rm.state::text as media_state" in source
    assert "'ready'::text as media_state" not in source


async def test_resolver_returns_playable_ready_asset(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row()

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.runtime_media_id == "runtime-media-1"
    assert result.media_state == "ready"
    assert result.is_playable is True
    assert result.playback_mode == RuntimeMediaPlaybackMode.PIPELINE_ASSET
    assert result.failure_reason == RuntimeMediaResolutionReason.OK_READY_ASSET
    assert result.storage_bucket == "course-media"
    assert (
        result.storage_path
        == "media/derived/audio/courses/demo/lessons/lesson-1/demo.mp3"
    )


async def test_resolver_does_not_fake_readiness_for_processing_asset(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row(
            media_state="processing",
            playback_object_path=(
                "media/derived/audio/courses/demo/lessons/lesson-1/demo.mp3"
            ),
            playback_format="mp3",
        )

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.media_state == "processing"
    assert result.is_playable is False
    assert result.playback_mode == RuntimeMediaPlaybackMode.NONE
    assert result.failure_reason == RuntimeMediaResolutionReason.ASSET_NOT_READY
    assert result.failure_detail == "media_asset state is processing"


async def test_resolver_rejects_ready_asset_missing_playback_path(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row(playback_object_path=None)

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.media_state == "ready"
    assert result.is_playable is False
    assert result.playback_mode == RuntimeMediaPlaybackMode.NONE
    assert result.failure_reason == RuntimeMediaResolutionReason.MISSING_STORAGE_OBJECT
    assert result.failure_detail == "runtime_media playback_object_path is missing"


async def test_resolver_rejects_ready_asset_missing_playback_format(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row(playback_format=None)

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.media_state == "ready"
    assert result.is_playable is False
    assert result.playback_mode == RuntimeMediaPlaybackMode.NONE
    assert result.failure_reason == RuntimeMediaResolutionReason.INVALID_CONTENT_TYPE
    assert result.failure_detail == "runtime_media playback_format is invalid or missing"
