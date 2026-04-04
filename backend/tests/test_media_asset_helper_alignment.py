import uuid

import pytest

from app.config import settings
from app.repositories import media_assets as media_assets_repo
from app.routes import api_media

pytestmark = pytest.mark.anyio("asyncio")


async def test_create_media_asset_requires_pending_upload_initial_state():
    with pytest.raises(
        RuntimeError,
        match="canonical pending_upload initial state",
    ):
        await media_assets_repo.create_media_asset(
            media_asset_id=str(uuid.uuid4()),
            media_type="audio",
            purpose="lesson_audio",
            original_object_path=(
                "media/source/audio/courses/course-1/lessons/lesson-1/demo.wav"
            ),
            ingest_format="wav",
            state="uploaded",
        )


async def test_create_media_asset_rejects_playback_metadata():
    with pytest.raises(
        RuntimeError,
        match="playback metadata is assigned only through canonical worker helpers",
    ):
        await media_assets_repo.create_media_asset(
            media_asset_id=str(uuid.uuid4()),
            media_type="audio",
            purpose="lesson_audio",
            original_object_path=(
                "media/source/audio/courses/course-1/lessons/lesson-1/demo.wav"
            ),
            ingest_format="wav",
            state="pending_upload",
            playback_object_path=(
                "media/derived/audio/courses/course-1/lessons/lesson-1/demo.mp3"
            ),
            playback_format="mp3",
        )


async def test_update_media_asset_state_enforces_uploaded_transition_boundary():
    media_asset_id = str(uuid.uuid4())

    with pytest.raises(
        RuntimeError,
        match="canonical uploaded transition",
    ):
        await media_assets_repo.update_media_asset_state(
            media_asset_id,
            state="ready",
        )

    with pytest.raises(
        RuntimeError,
        match="playback metadata is assigned only through canonical worker helpers",
    ):
        await media_assets_repo.update_media_asset_state(
            media_asset_id,
            state="uploaded",
            playback_object_path=(
                "media/derived/audio/courses/course-1/lessons/lesson-1/demo.mp3"
            ),
        )


async def test_mark_media_asset_ready_passthrough_is_removed():
    with pytest.raises(
        RuntimeError,
        match="removed from canonical runtime",
    ):
        await media_assets_repo.mark_media_asset_ready_passthrough(
            media_id=str(uuid.uuid4()),
            streaming_object_path="media/derived/audio/demo.mp3",
            storage_bucket=settings.media_source_bucket,
            streaming_format="mp3",
        )


async def test_get_media_asset_access_derives_public_cover_bucket(monkeypatch):
    async def fake_get_media_asset(_: str):
        return {
            "id": str(uuid.uuid4()),
            "media_type": "image",
            "purpose": "course_cover",
            "original_object_path": "media/source/cover/courses/course-1/source.png",
            "playback_object_path": "media/derived/cover/courses/course-1/cover.jpg",
            "playback_format": "jpg",
            "state": "ready",
            "storage_bucket": None,
            "streaming_storage_bucket": None,
        }

    monkeypatch.setattr(media_assets_repo, "get_media_asset", fake_get_media_asset)

    media_asset = await media_assets_repo.get_media_asset_access(str(uuid.uuid4()))

    assert media_asset is not None
    assert media_asset["storage_bucket"] == settings.media_public_bucket


async def test_canonical_media_asset_scope_uses_path_authority_for_lesson_audio():
    scope = api_media._canonical_media_asset_scope(
        {
            "media_type": "audio",
            "purpose": "lesson_audio",
            "original_object_path": (
                "media/source/audio/courses/course-1/lessons/lesson-1/demo.wav"
            ),
            "course_id": "legacy-course",
            "lesson_id": "legacy-lesson",
            "storage_bucket": "legacy-bucket",
        }
    )

    assert scope.course_id == "course-1"
    assert scope.lesson_id == "lesson-1"
    assert scope.storage_bucket == api_media.storage_service.storage_service.bucket


async def test_canonical_media_asset_scope_uses_public_image_bucket():
    scope = api_media._canonical_media_asset_scope(
        {
            "media_type": "image",
            "purpose": "lesson_media",
            "original_object_path": "lessons/lesson-1/images/diagram.png",
            "storage_bucket": "legacy-bucket",
        }
    )

    assert scope.lesson_id == "lesson-1"
    assert scope.storage_bucket == settings.media_public_bucket
