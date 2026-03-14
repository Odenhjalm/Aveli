import pytest
from fastapi import HTTPException, status

from app.services import lesson_playback_service


pytestmark = pytest.mark.anyio("asyncio")


async def test_resolve_lesson_media_playback_prefers_media_asset(monkeypatch):
    async def fake_get_media(_lesson_media_id: str):
        return {
            "id": "lesson-media-1",
            "media_asset_id": "asset-1",
            "media_id": "legacy-1",
            "storage_path": "courses/demo/legacy.mp3",
        }

    async def fake_resolve_pipeline_playback(*, media_asset_id: str, user_id: str):
        assert media_asset_id == "asset-1"
        assert user_id == "user-1"
        return {"url": "https://stream.test/asset.mp3", "media_id": media_asset_id}

    async def fail_legacy_fallback(**_kwargs):
        raise AssertionError("legacy fallback should not run when asset playback succeeds")

    monkeypatch.setattr(
        lesson_playback_service.models,
        "get_media",
        fake_get_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "resolve_pipeline_playback",
        fake_resolve_pipeline_playback,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "resolve_object_media_playback",
        fail_legacy_fallback,
        raising=True,
    )

    result = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id="lesson-media-1",
        user_id="user-1",
    )

    assert result == {"url": "https://stream.test/asset.mp3", "media_id": "asset-1"}


async def test_resolve_lesson_media_playback_falls_back_to_storage_path(monkeypatch):
    async def fake_get_media(_lesson_media_id: str):
        return {
            "id": "lesson-media-1",
            "media_asset_id": "asset-1",
            "media_id": None,
            "storage_path": "courses/demo/legacy.mp3",
        }

    async def fake_resolve_pipeline_playback(*, media_asset_id: str, user_id: str):
        assert media_asset_id == "asset-1"
        assert user_id == "user-1"
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Asset not ready",
        )

    async def fake_resolve_object_media_playback(*, lesson_media_id: str, user_id: str):
        assert lesson_media_id == "lesson-media-1"
        assert user_id == "user-1"
        return {
            "url": "https://stream.test/legacy.mp3",
            "media_id": lesson_media_id,
        }

    monkeypatch.setattr(
        lesson_playback_service.models,
        "get_media",
        fake_get_media,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "resolve_pipeline_playback",
        fake_resolve_pipeline_playback,
        raising=True,
    )
    monkeypatch.setattr(
        lesson_playback_service,
        "resolve_object_media_playback",
        fake_resolve_object_media_playback,
        raising=True,
    )

    result = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id="lesson-media-1",
        user_id="user-1",
    )

    assert result == {
        "url": "https://stream.test/legacy.mp3",
        "media_id": "lesson-media-1",
    }
