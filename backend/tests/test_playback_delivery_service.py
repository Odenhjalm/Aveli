import pytest
from fastapi import HTTPException, status

from app.services import playback_delivery_service


pytestmark = pytest.mark.anyio("asyncio")


async def test_resolve_runtime_media_stream_source_requires_media_asset_id():
    with pytest.raises(HTTPException) as exc_info:
        await playback_delivery_service.resolve_runtime_media_stream_source(
            {
                "id": "runtime-media-1",
                "media_asset_id": None,
            }
        )

    assert exc_info.value.status_code == status.HTTP_404_NOT_FOUND
    assert exc_info.value.detail == "Playable media not found"


async def test_resolve_runtime_media_stream_source_uses_media_asset_only(monkeypatch):
    async def fake_get_media_asset_access(media_asset_id: str):
        assert media_asset_id == "asset-1"
        return {
            "media_type": "audio",
            "streaming_object_path": "media/derived/audio/demo.mp3",
            "streaming_storage_bucket": "course-media",
            "original_content_type": "audio/mpeg",
            "original_filename": "demo.mp3",
        }

    monkeypatch.setattr(
        playback_delivery_service.media_assets_repo,
        "get_media_asset_access",
        fake_get_media_asset_access,
        raising=True,
    )

    result = await playback_delivery_service.resolve_runtime_media_stream_source(
        {
            "id": "runtime-media-1",
            "media_asset_id": "asset-1",
        }
    )

    assert result == {
        "id": "runtime-media-1",
        "kind": "audio",
        "storage_path": "media/derived/audio/demo.mp3",
        "storage_bucket": "course-media",
        "content_type": "audio/mpeg",
        "original_name": "demo.mp3",
    }
