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
    legacy_media_object_id: str | None = None,
    kind: str | None = "audio",
    content_type: str | None = "audio/mpeg",
    media_state: str | None = "ready",
    storage_bucket: str | None = "course-media",
    storage_path: str | None = "media/derived/audio/courses/demo/lessons/demo.mp3",
    requires_legacy_fallback: bool = False,
) -> LessonMediaResolution:
    return LessonMediaResolution(
        lesson_media_id="lesson-media-1",
        lesson_id="lesson-1",
        media_asset_id=media_asset_id,
        legacy_media_object_id=legacy_media_object_id,
        kind=kind,
        content_type=content_type,
        media_state=media_state,
        duration_seconds=120,
        storage_bucket=storage_bucket,
        storage_path=storage_path,
        is_playable=is_playable,
        playback_mode=playback_mode,
        failure_reason=failure_reason,
        failure_detail=None,
        asset_purpose="lesson_audio" if media_asset_id else None,
        requires_legacy_fallback=requires_legacy_fallback,
        runtime_media_id=runtime_media_id,
        reference_type="lesson_media",
        auth_scope="lesson_course",
        teacher_id="teacher-1",
        course_id="course-1",
        active=True,
        fallback_policy="never",
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
        return {"url": "https://stream.test/asset.mp3", "media_id": "asset-1"}

    async def fail_legacy_resolution(**_kwargs):
        raise AssertionError("legacy playback should not run for ready asset resolution")

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
    monkeypatch.setattr(
        lesson_playback_service,
        "_resolve_legacy_storage_playback_from_resolution",
        fail_legacy_resolution,
        raising=True,
    )

    result = await lesson_playback_service.resolve_runtime_media_playback(
        runtime_media_id="runtime-media-1",
        user_id="user-1",
    )

    assert result["runtime_media_id"] == "runtime-media-1"
    assert result["playback_url"] == "https://stream.test/asset.mp3"
    assert result["kind"] == "audio"
    assert result["duration_seconds"] == 120


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


async def test_resolve_runtime_media_playback_blocks_legacy_storage_for_lesson_media(
    monkeypatch,
):
    resolution = _resolution(
        playback_mode=LessonMediaPlaybackMode.LEGACY_STORAGE,
        failure_reason=LessonMediaResolutionReason.LEGACY_FALLBACK_REQUIRED,
        is_playable=True,
        media_asset_id="asset-1",
        legacy_media_object_id="legacy-1",
        kind="video",
        content_type="video/mp4",
        media_state="processing",
        storage_path="courses/demo/legacy.mp4",
        requires_legacy_fallback=True,
    )

    async def fake_resolve_runtime_media(_runtime_media_id: str):
        return resolution

    async def fail_pipeline_resolution(**_kwargs):
        raise AssertionError("pipeline playback should not run when resolver chose legacy storage")

    async def fail_legacy_resolution(**_kwargs):
        raise AssertionError("legacy playback should be blocked for lesson media")

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "resolve_runtime_media",
        fake_resolve_runtime_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "_resolve_pipeline_playback_from_resolution",
        fail_pipeline_resolution,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "_resolve_legacy_storage_playback_from_resolution",
        fail_legacy_resolution,
        raising=True,
    )

    with pytest.raises(HTTPException) as exc_info:
        await lesson_playback_service.resolve_runtime_media_playback(
            runtime_media_id="runtime-media-1",
            user_id="user-1",
        )

    assert exc_info.value.status_code == status.HTTP_404_NOT_FOUND
    assert exc_info.value.detail == "Lesson media has no playable source"


async def test_resolve_runtime_media_playback_allows_legacy_image_passthrough_for_lesson_media(
    monkeypatch,
):
    resolution = _resolution(
        playback_mode=LessonMediaPlaybackMode.LEGACY_STORAGE,
        failure_reason=LessonMediaResolutionReason.OK_LEGACY_OBJECT,
        is_playable=True,
        media_asset_id=None,
        legacy_media_object_id="legacy-image-1",
        kind="image",
        content_type="image/webp",
        media_state="ready",
        storage_path="public-media/courses/demo/lessons/demo/image.webp",
        requires_legacy_fallback=False,
    )

    async def fake_resolve_runtime_media(_runtime_media_id: str):
        return resolution

    async def fail_pipeline_resolution(**_kwargs):
        raise AssertionError("pipeline playback should not run for legacy image passthrough")

    async def fake_legacy_resolution(*, resolution: LessonMediaResolution, user_id: str):
        assert resolution.kind == "image"
        assert user_id == "user-1"
        return {
            "url": "https://stream.test/image.webp",
            "playback_url": "https://stream.test/image.webp",
            "media_id": "lesson-media-1",
        }

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "resolve_runtime_media",
        fake_resolve_runtime_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "_resolve_pipeline_playback_from_resolution",
        fail_pipeline_resolution,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "_resolve_legacy_storage_playback_from_resolution",
        fake_legacy_resolution,
        raising=True,
    )

    result = await lesson_playback_service.resolve_runtime_media_playback(
        runtime_media_id="runtime-media-1",
        user_id="user-1",
    )

    assert result["playback_url"] == "https://stream.test/image.webp"
    assert result["kind"] == "image"
    assert result["content_type"] == "image/webp"


async def test_resolve_lesson_media_playback_looks_up_runtime_media_and_delegates(monkeypatch):
    async def fake_lookup_runtime_media_id_for_lesson_media(lesson_media_id: str):
        assert lesson_media_id == "lesson-media-1"
        return "runtime-media-1"

    async def fake_resolve_runtime_media_playback(*, runtime_media_id: str, user_id: str):
        assert runtime_media_id == "runtime-media-1"
        assert user_id == "user-1"
        return {
            "runtime_media_id": runtime_media_id,
            "playback_url": "https://stream.test/asset.mp3",
            "url": "https://stream.test/asset.mp3",
            "kind": "audio",
            "content_type": "audio/mpeg",
            "duration_seconds": 120,
        }

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

    assert result["runtime_media_id"] == "runtime-media-1"
    assert result["playback_url"] == "https://stream.test/asset.mp3"


async def test_resolve_lesson_media_playback_returns_not_found_when_runtime_mapping_is_missing(
    monkeypatch,
):
    missing = _resolution(
        playback_mode=LessonMediaPlaybackMode.NONE,
        failure_reason=LessonMediaResolutionReason.LESSON_MEDIA_NOT_FOUND,
        is_playable=False,
        runtime_media_id="",
        media_asset_id=None,
        legacy_media_object_id=None,
        kind=None,
        content_type=None,
        media_state=None,
        storage_bucket=None,
        storage_path=None,
    )

    async def fake_lookup_runtime_media_id_for_lesson_media(_lesson_media_id: str):
        return None

    async def fake_resolve_lesson_media(_lesson_media_id: str):
        return missing

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "lookup_runtime_media_id_for_lesson_media",
        fake_lookup_runtime_media_id_for_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "resolve_lesson_media",
        fake_resolve_lesson_media,
        raising=True,
    )

    with pytest.raises(HTTPException) as exc_info:
        await lesson_playback_service.resolve_lesson_media_playback(
            lesson_media_id="lesson-media-1",
            user_id="user-1",
        )

    assert exc_info.value.status_code == status.HTTP_404_NOT_FOUND
    assert exc_info.value.detail == "Media not found"


async def test_resolve_lesson_media_playback_uses_legacy_image_passthrough_when_runtime_mapping_is_missing(
    monkeypatch,
):
    resolution = _resolution(
        playback_mode=LessonMediaPlaybackMode.LEGACY_STORAGE,
        failure_reason=LessonMediaResolutionReason.OK_LEGACY_OBJECT,
        is_playable=True,
        runtime_media_id="",
        media_asset_id=None,
        legacy_media_object_id="legacy-image-1",
        kind="image",
        content_type="image/png",
        media_state="ready",
        storage_path="public-media/courses/demo/lessons/demo/image.png",
    )

    async def fake_lookup_runtime_media_id_for_lesson_media(_lesson_media_id: str):
        return None

    async def fake_resolve_lesson_media(_lesson_media_id: str):
        return resolution

    async def fake_resolve_playback_from_resolution(*, resolution: LessonMediaResolution, user_id: str):
        assert resolution.kind == "image"
        assert user_id == "user-1"
        return {
            "url": "https://stream.test/image.png",
            "playback_url": "https://stream.test/image.png",
            "media_id": "lesson-media-1",
        }

    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "lookup_runtime_media_id_for_lesson_media",
        fake_lookup_runtime_media_id_for_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service.canonical_media_resolver,
        "resolve_lesson_media",
        fake_resolve_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "_resolve_playback_from_resolution",
        fake_resolve_playback_from_resolution,
        raising=True,
    )

    result = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id="lesson-media-1",
        user_id="user-1",
    )

    assert result["playback_url"] == "https://stream.test/image.png"
