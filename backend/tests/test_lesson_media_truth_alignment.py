import pytest

from app.media_control_plane.services.media_resolver_service import (
    RuntimeMediaPlaybackMode,
    RuntimeMediaResolution,
    RuntimeMediaResolutionReason,
)
from app.services import courses_service

pytestmark = pytest.mark.anyio("asyncio")


def _resolution(
    *,
    lesson_media_id: str,
    media_asset_id: str | None,
    media_type: str,
    media_state: str,
    is_playable: bool,
    playback_mode: RuntimeMediaPlaybackMode,
    failure_reason: RuntimeMediaResolutionReason,
) -> RuntimeMediaResolution:
    return RuntimeMediaResolution(
        lesson_media_id=lesson_media_id,
        media_asset_id=media_asset_id,
        media_type=media_type,
        content_type="video/mp4" if media_type == "video" else "audio/mpeg",
        media_state=media_state,
        storage_bucket="course-media",
        storage_path=f"media/derived/{media_type}/{lesson_media_id}",
        is_playable=is_playable,
        playback_mode=playback_mode,
        failure_reason=failure_reason,
    )


async def test_list_lesson_media_editor_uses_canonical_projection_only(
    monkeypatch,
):
    async def fake_list_lesson_media(_lesson_id: str):
        return [
            {
                "id": "image-1",
                "lesson_id": "lesson-1",
                "media_asset_id": "asset-1",
                "position": 1,
                "media_type": "image",
                "state": "processing",
                "preferredUrl": "https://cdn.test/raw-image.png",
                "download_url": "https://cdn.test/raw-image.png",
                "signed_url": "https://signed.test/raw-image.png",
                "original_name": "missing.png",
            }
        ]

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )

    items = list(
        await courses_service.list_lesson_media("lesson-1", mode="editor_preview")
    )

    assert items == [
        {
            "id": "image-1",
            "lesson_id": "lesson-1",
            "media_asset_id": "asset-1",
            "position": 1,
            "media_type": "image",
            "kind": "image",
            "state": "processing",
            "media": None,
            "original_name": "missing.png",
        }
    ]


async def test_list_lesson_media_student_suppresses_non_playable_assets(
    monkeypatch,
):
    async def fake_list_lesson_media(_lesson_id: str):
        return [
            {
                "id": "audio-1",
                "lesson_id": "lesson-1",
                "media_asset_id": "asset-1",
                "position": 1,
                "media_type": "audio",
                "state": "processing",
                "original_name": "missing.mp3",
            }
        ]

    async def fake_resolve_lesson_media(
        lesson_media_id: str,
        *,
        emit_logs: bool = True,
    ) -> RuntimeMediaResolution:
        assert lesson_media_id == "audio-1"
        assert emit_logs is False
        return _resolution(
            lesson_media_id="audio-1",
            media_asset_id="asset-1",
            media_type="audio",
            media_state="processing",
            is_playable=False,
            playback_mode=RuntimeMediaPlaybackMode.NONE,
            failure_reason=RuntimeMediaResolutionReason.ASSET_NOT_READY,
        )

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.canonical_media_resolver,
        "resolve_lesson_media",
        fake_resolve_lesson_media,
        raising=True,
    )

    items = list(
        await courses_service.list_lesson_media(
            "lesson-1",
            mode="student_render",
            user_id="user-1",
        )
    )

    assert len(items) == 1
    item = items[0]
    assert item["media"] is None
    assert "download_url" not in item
    assert "signed_url" not in item
    assert "signed_url_expires_at" not in item


async def test_list_lesson_media_student_suppresses_non_pipeline_resolution(
    monkeypatch,
):
    async def fake_list_lesson_media(_lesson_id: str):
        return [
            {
                "id": "video-1",
                "lesson_id": "lesson-1",
                "media_asset_id": "asset-1",
                "position": 1,
                "media_type": "video",
                "state": "ready",
                "original_name": "demo.mp4",
            }
        ]

    async def fake_resolve_lesson_media(
        lesson_media_id: str,
        *,
        emit_logs: bool = True,
    ) -> RuntimeMediaResolution:
        assert lesson_media_id == "video-1"
        assert emit_logs is False
        return _resolution(
            lesson_media_id="video-1",
            media_asset_id="asset-1",
            media_type="video",
            media_state="ready",
            is_playable=True,
            playback_mode=RuntimeMediaPlaybackMode.NONE,
            failure_reason=RuntimeMediaResolutionReason.UNSUPPORTED_MEDIA_CONTRACT,
        )

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.canonical_media_resolver,
        "resolve_lesson_media",
        fake_resolve_lesson_media,
        raising=True,
    )

    items = list(
        await courses_service.list_lesson_media(
            "lesson-1",
            mode="student_render",
            user_id="user-1",
        )
    )

    assert len(items) == 1
    item = items[0]
    assert item["media"] is None
    assert "download_url" not in item
    assert "signed_url" not in item


async def test_list_lesson_media_student_exposes_only_canonical_pipeline_media(
    monkeypatch,
):
    async def fake_list_lesson_media(_lesson_id: str):
        return [
            {
                "id": "video-2",
                "lesson_id": "lesson-1",
                "media_asset_id": "asset-1",
                "position": 1,
                "media_type": "video",
                "state": "ready",
                "original_name": "demo.mp4",
            }
        ]

    async def fake_resolve_lesson_media(
        lesson_media_id: str,
        *,
        emit_logs: bool = True,
    ) -> RuntimeMediaResolution:
        assert lesson_media_id == "video-2"
        assert emit_logs is False
        return _resolution(
            lesson_media_id="video-2",
            media_asset_id="asset-1",
            media_type="video",
            media_state="ready",
            is_playable=True,
            playback_mode=RuntimeMediaPlaybackMode.PIPELINE_ASSET,
            failure_reason=RuntimeMediaResolutionReason.OK_READY_ASSET,
        )

    async def fake_resolve_lesson_media_playback(
        *,
        lesson_media_id: str,
        user_id: str,
    ):
        assert lesson_media_id == "video-2"
        assert user_id == "user-1"
        return {"resolved_url": "https://cdn.test/pipeline-video.mp4"}

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.canonical_media_resolver,
        "resolve_lesson_media",
        fake_resolve_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    items = list(
        await courses_service.list_lesson_media(
            "lesson-1",
            mode="student_render",
            user_id="user-1",
        )
    )

    assert len(items) == 1
    item = items[0]
    assert item["media"] == {
        "media_id": "asset-1",
        "state": "ready",
        "resolved_url": "https://cdn.test/pipeline-video.mp4",
    }
    assert "download_url" not in item
    assert "signed_url" not in item
