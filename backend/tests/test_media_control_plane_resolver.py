import pytest

from app.media_control_plane.services.media_resolver_service import (
    MediaResolverService,
    RuntimeMediaPlaybackMode,
    RuntimeMediaResolutionReason,
)
from app.repositories import storage_objects


pytestmark = pytest.mark.anyio("asyncio")


def _contract_row(
    **overrides,
):
    row = {
        "runtime_media_id": "runtime-media-1",
        "reference_type": "lesson_media",
        "auth_scope": "lesson_course",
        "fallback_policy": "never",
        "active": True,
        "lesson_media_id": "lesson-media-1",
        "home_player_upload_id": None,
        "teacher_id": "teacher-1",
        "course_id": "course-1",
        "lesson_id": "lesson-1",
        "lesson_kind": "audio",
        "lesson_storage_path": None,
        "lesson_storage_bucket": None,
        "media_id": None,
        "media_asset_id": "asset-1",
        "media_object_id": None,
        "object_storage_path": None,
        "object_storage_bucket": None,
        "object_content_type": None,
        "asset_row_id": "asset-1",
        "asset_media_type": "audio",
        "asset_purpose": "lesson_audio",
        "asset_state": "ready",
        "asset_original_object_path": "media/source/audio/courses/demo/lessons/lesson-1/demo.wav",
        "asset_storage_bucket": "course-media",
        "asset_streaming_object_path": "media/derived/audio/courses/demo/lessons/lesson-1/demo.mp3",
        "asset_streaming_storage_bucket": "course-media",
        "asset_original_content_type": "audio/wav",
        "asset_streaming_format": "mp3",
        "asset_error_message": None,
        "duration_seconds": 120,
    }
    row.update(overrides)
    return row


async def test_resolver_returns_playable_ready_asset(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row()

    async def fake_storage_existence(pairs):
        assert pairs == [("course-media", "media/derived/audio/courses/demo/lessons/lesson-1/demo.mp3")]
        return {pairs[0]: True}, True

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )
    monkeypatch.setattr(
        storage_objects,
        "fetch_storage_object_existence",
        fake_storage_existence,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.runtime_media_id == "runtime-media-1"
    assert result.is_playable is True
    assert result.playback_mode == RuntimeMediaPlaybackMode.PIPELINE_ASSET
    assert result.failure_reason == RuntimeMediaResolutionReason.OK_READY_ASSET
    assert result.storage_bucket == "course-media"
    assert result.storage_path == "media/derived/audio/courses/demo/lessons/lesson-1/demo.mp3"
    assert result.duration_seconds == 120


async def test_resolver_returns_not_ready_reason_for_processing_asset(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row(
            asset_state="processing",
            asset_streaming_object_path=None,
        )

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.is_playable is False
    assert result.playback_mode == RuntimeMediaPlaybackMode.NONE
    assert result.failure_reason == RuntimeMediaResolutionReason.ASSET_NOT_READY
    assert result.failure_detail == "media_asset state is processing"


async def test_resolver_classifies_legacy_fallback_when_asset_is_not_ready(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row(
            lesson_kind="video",
            fallback_policy="if_no_ready_asset",
            media_id="legacy-1",
            media_object_id="legacy-1",
            object_storage_path="courses/demo/legacy.mp4",
            object_storage_bucket="course-media",
            object_content_type="video/mp4",
            asset_media_type="video",
            asset_purpose="lesson_media",
            asset_state="processing",
            asset_streaming_object_path=None,
            asset_original_object_path="lessons/lesson-1/video.mp4",
            asset_original_content_type="video/mp4",
            duration_seconds=None,
        )

    async def fake_storage_existence(pairs):
        assert pairs == [("course-media", "courses/demo/legacy.mp4")]
        return {pairs[0]: True}, True

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )
    monkeypatch.setattr(
        storage_objects,
        "fetch_storage_object_existence",
        fake_storage_existence,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.is_playable is True
    assert result.playback_mode == RuntimeMediaPlaybackMode.LEGACY_STORAGE
    assert result.failure_reason == RuntimeMediaResolutionReason.LEGACY_FALLBACK_REQUIRED
    assert result.requires_legacy_fallback is True
    assert result.storage_path == "courses/demo/legacy.mp4"


async def test_resolver_returns_missing_storage_object_for_ready_asset(monkeypatch):
    resolver = MediaResolverService()

    async def fake_fetch(_runtime_media_id: str):
        return _contract_row()

    async def fake_storage_existence(pairs):
        assert pairs == [("course-media", "media/derived/audio/courses/demo/lessons/lesson-1/demo.mp3")]
        return {pairs[0]: False}, True

    monkeypatch.setattr(
        resolver,
        "_fetch_runtime_media_contract_row",
        fake_fetch,
        raising=True,
    )
    monkeypatch.setattr(
        storage_objects,
        "fetch_storage_object_existence",
        fake_storage_existence,
        raising=True,
    )

    result = await resolver.resolve_runtime_media("runtime-media-1")

    assert result.is_playable is False
    assert result.playback_mode == RuntimeMediaPlaybackMode.NONE
    assert result.failure_reason == RuntimeMediaResolutionReason.MISSING_STORAGE_OBJECT
    assert result.failure_detail == "ready media_asset playback object is missing"
