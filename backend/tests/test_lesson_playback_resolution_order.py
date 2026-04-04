import pytest
from fastapi import HTTPException, status

from app.media_control_plane.services.media_resolver_service import (
    LessonMediaPlaybackMode,
    LessonMediaResolution,
    LessonMediaResolutionReason,
)
from app.services import lesson_playback_service


pytestmark = pytest.mark.anyio("asyncio")


def _resolution(
    *,
    playback_mode: LessonMediaPlaybackMode,
    failure_reason: LessonMediaResolutionReason,
    is_playable: bool,
    runtime_media_id: str = "runtime-media-1",
    media_asset_id: str | None = None,
    media_type: str | None = "audio",
    content_type: str | None = "audio/mpeg",
    media_state: str | None = "ready",
    storage_bucket: str | None = "course-media",
    storage_path: str | None = "media/derived/audio/courses/demo/lessons/demo.mp3",
) -> LessonMediaResolution:
    return LessonMediaResolution(
        lesson_media_id="lesson-media-1",
        lesson_id="lesson-1",
        media_asset_id=media_asset_id,
        media_type=media_type,
        content_type=content_type,
        media_state=media_state,
        duration_seconds=120,
        storage_bucket=storage_bucket,
        storage_path=storage_path,
        is_playable=is_playable,
        playback_mode=playback_mode,
        failure_reason=failure_reason,
        failure_detail=None,
        runtime_media_id=runtime_media_id,
        course_id="course-1",
    )


async def test_resolve_runtime_media_playback_uses_canonical_asset_resolution(monkeypatch):
    resolution = _resolution(
        playback_mode=LessonMediaPlaybackMode.PIPELINE_ASSET,
        failure_reason=LessonMediaResolutionReason.OK_READY_ASSET,
        is_playable=True,
        media_asset_id="asset-1",
    )

    async def fake_resolve_runtime_media(runtime_media_id: str):
        assert runtime_media_id == "runtime-media-1"
        return resolution

    async def fake_pipeline_resolution(*, resolution: LessonMediaResolution, user_id: str):
        assert resolution.failure_reason == LessonMediaResolutionReason.OK_READY_ASSET
        assert resolution.media_asset_id == "asset-1"
        assert user_id == "user-1"
        return {"resolved_url": "https://stream.test/asset.mp3"}

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "resolve_runtime_media",
        fake_resolve_runtime_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "_resolve_pipeline_playback_from_resolution",
        fake_pipeline_resolution,
        raising=True,
    )

    result = await lesson_playback_service.resolve_runtime_media_playback(
        runtime_media_id="runtime-media-1",
        user_id="user-1",
    )

    assert result["resolved_url"] == "https://stream.test/asset.mp3"


async def test_resolve_runtime_media_playback_returns_not_ready_for_unplayable_asset(
    monkeypatch,
):
    resolution = _resolution(
        playback_mode=LessonMediaPlaybackMode.NONE,
        failure_reason=LessonMediaResolutionReason.ASSET_NOT_READY,
        is_playable=False,
        media_asset_id="asset-1",
        media_state="processing",
        storage_bucket=None,
        storage_path=None,
        content_type="audio/wav",
    )

    async def fake_resolve_runtime_media(_runtime_media_id: str):
        return resolution

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "resolve_runtime_media",
        fake_resolve_runtime_media,
        raising=True,
    )

    with pytest.raises(HTTPException) as exc_info:
        await lesson_playback_service.resolve_runtime_media_playback(
            runtime_media_id="runtime-media-1",
            user_id="user-1",
        )

    assert exc_info.value.status_code == status.HTTP_409_CONFLICT
    assert exc_info.value.detail == "Media is not ready"


async def test_resolve_lesson_media_playback_looks_up_runtime_media_and_delegates(
    monkeypatch,
):
    async def fake_lookup_runtime_media_id_for_lesson_media(lesson_media_id: str):
        assert lesson_media_id == "lesson-media-1"
        return "runtime-media-1"

    async def fake_resolve_runtime_media_playback(*, runtime_media_id: str, user_id: str):
        assert runtime_media_id == "runtime-media-1"
        assert user_id == "user-1"
        return {"resolved_url": "https://stream.test/asset.mp3"}

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "lookup_runtime_media_id_for_lesson_media",
        fake_lookup_runtime_media_id_for_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "resolve_runtime_media_playback",
        fake_resolve_runtime_media_playback,
        raising=True,
    )

    result = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id="lesson-media-1",
        user_id="user-1",
    )

    assert result["resolved_url"] == "https://stream.test/asset.mp3"


async def test_resolve_lesson_media_playback_returns_not_found_when_runtime_mapping_is_missing(
    monkeypatch,
):
    async def fake_lookup_runtime_media_id_for_lesson_media(_lesson_media_id: str):
        return None

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "lookup_runtime_media_id_for_lesson_media",
        fake_lookup_runtime_media_id_for_lesson_media,
        raising=True,
    )

    with pytest.raises(HTTPException) as exc_info:
        await lesson_playback_service.resolve_lesson_media_playback(
            lesson_media_id="lesson-media-1",
            user_id="user-1",
        )

    assert exc_info.value.status_code == status.HTTP_404_NOT_FOUND
    assert exc_info.value.detail == "Active runtime media not found"
