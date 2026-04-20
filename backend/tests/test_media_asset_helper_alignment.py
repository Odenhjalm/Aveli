import uuid
from pathlib import Path

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
            playback_object_path="media/derived/audio/demo.mp3",
            storage_bucket=settings.media_source_bucket,
            playback_format="mp3",
        )


async def test_mark_media_asset_ready_from_worker_requires_processing_state(
    monkeypatch,
):
    async def fake_get_media_asset(_: str):
        return {
            "id": str(uuid.uuid4()),
            "media_type": "image",
            "purpose": "course_cover",
            "original_object_path": "media/source/cover/courses/course-1/source.png",
            "playback_object_path": None,
            "playback_format": None,
            "state": "uploaded",
        }

    async def fail_transition(*args, **kwargs):
        raise AssertionError("ready helper must not promote uploaded media")

    monkeypatch.setattr(media_assets_repo, "get_media_asset", fake_get_media_asset)
    monkeypatch.setattr(
        media_assets_repo,
        "_call_canonical_worker_transition",
        fail_transition,
    )

    with pytest.raises(
        RuntimeError,
        match="ready transition requires processing state",
    ):
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=str(uuid.uuid4()),
            playback_object_path="media/derived/cover/courses/course-1/source.jpg",
            playback_format="jpg",
        )


@pytest.mark.parametrize(
    ("media_type", "playback_format"),
    [
        ("image", "jpg"),
        ("image", "png"),
        ("video", "mp4"),
        ("document", "pdf"),
    ],
)
async def test_mark_media_asset_ready_from_worker_allows_lesson_media_formats(
    monkeypatch,
    media_type,
    playback_format,
):
    media_id = str(uuid.uuid4())
    calls: dict[str, object] = {}

    async def fake_get_media_asset(_: str):
        return {
            "id": media_id,
            "media_type": media_type,
            "purpose": "lesson_media",
            "original_object_path": f"source.{playback_format}",
            "playback_object_path": None,
            "playback_format": None,
            "state": "processing",
        }

    async def fake_transition(*args, **kwargs):
        calls["transition"] = kwargs
        return {"id": media_id, "state": "ready"}

    monkeypatch.setattr(media_assets_repo, "get_media_asset", fake_get_media_asset)
    monkeypatch.setattr(
        media_assets_repo,
        "_call_canonical_worker_transition",
        fake_transition,
    )

    result = await media_assets_repo.mark_media_asset_ready_from_worker(
        media_id=media_id,
        playback_object_path=(
            f"media/derived/lesson-media/{media_type}/source.{playback_format}"
        ),
        playback_format=playback_format,
    )

    assert result == {"id": media_id, "state": "ready"}
    assert calls["transition"]["target_state"] == "ready"
    assert calls["transition"]["playback_format"] == playback_format


async def test_mark_media_asset_ready_from_worker_rejects_invalid_lesson_video_format(
    monkeypatch,
):
    media_id = str(uuid.uuid4())

    async def fake_get_media_asset(_: str):
        return {
            "id": media_id,
            "media_type": "video",
            "purpose": "lesson_media",
            "original_object_path": "source.webm",
            "playback_object_path": None,
            "playback_format": None,
            "state": "processing",
        }

    async def fail_transition(*args, **kwargs):
        raise AssertionError("invalid lesson video format must not transition ready")

    monkeypatch.setattr(media_assets_repo, "get_media_asset", fake_get_media_asset)
    monkeypatch.setattr(
        media_assets_repo,
        "_call_canonical_worker_transition",
        fail_transition,
    )

    with pytest.raises(
        RuntimeError,
        match="lesson video ready requires playback_format mp4",
    ):
        await media_assets_repo.mark_media_asset_ready_from_worker(
            media_id=media_id,
            playback_object_path="media/derived/lesson-media/video/source.webm",
            playback_format="webm",
        )


async def test_mark_course_cover_ready_from_worker_requires_playback_format():
    with pytest.raises(
        RuntimeError,
        match="ready transition requires playback_format",
    ):
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(uuid.uuid4()),
            playback_object_path="media/derived/cover/courses/course-1/source.jpg",
            playback_format=None,
        )


async def test_mark_course_cover_ready_from_worker_requires_jpg_format():
    with pytest.raises(
        RuntimeError,
        match="course cover ready requires playback_format jpg",
    ):
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(uuid.uuid4()),
            playback_object_path="media/derived/cover/courses/course-1/source.png",
            playback_format="png",
        )


async def test_mark_course_cover_ready_from_worker_rejects_wrong_media_type(
    monkeypatch,
):
    async def fake_get_course_cover_pipeline_asset(_: str):
        return {
            "id": str(uuid.uuid4()),
            "media_type": "audio",
            "purpose": "course_cover",
            "original_object_path": "media/source/cover/courses/course-1/source.png",
            "playback_object_path": None,
            "playback_format": None,
            "state": "processing",
        }

    monkeypatch.setattr(
        media_assets_repo,
        "get_course_cover_pipeline_asset",
        fake_get_course_cover_pipeline_asset,
    )

    with pytest.raises(RuntimeError, match="course cover ready requires image media"):
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(uuid.uuid4()),
            playback_object_path="media/derived/cover/courses/course-1/source.jpg",
            playback_format="jpg",
        )


async def test_mark_course_cover_ready_from_worker_rejects_wrong_purpose(
    monkeypatch,
):
    async def fake_get_course_cover_pipeline_asset(_: str):
        return {
            "id": str(uuid.uuid4()),
            "media_type": "image",
            "purpose": "profile_media",
            "original_object_path": "media/source/profile-avatar/user-1/avatar.png",
            "playback_object_path": None,
            "playback_format": None,
            "state": "processing",
        }

    monkeypatch.setattr(
        media_assets_repo,
        "get_course_cover_pipeline_asset",
        fake_get_course_cover_pipeline_asset,
    )

    with pytest.raises(
        RuntimeError,
        match="course cover ready requires purpose course_cover",
    ):
        await media_assets_repo.mark_course_cover_ready_from_worker(
            media_id=str(uuid.uuid4()),
            playback_object_path="media/derived/cover/courses/course-1/source.jpg",
            playback_format="jpg",
        )


async def test_mark_course_cover_ready_from_worker_preserves_jpg_format(
    monkeypatch,
):
    media_id = str(uuid.uuid4())
    calls: dict[str, object] = {}

    async def fake_get_course_cover_pipeline_asset(_: str):
        return {
            "id": media_id,
            "media_type": "image",
            "purpose": "course_cover",
            "original_object_path": "media/source/cover/courses/course-1/source.png",
            "playback_object_path": None,
            "playback_format": None,
            "state": "processing",
        }

    async def fake_mark_ready(**kwargs):
        calls["ready"] = kwargs
        return {"id": kwargs["media_id"], "state": "ready"}

    monkeypatch.setattr(
        media_assets_repo,
        "get_course_cover_pipeline_asset",
        fake_get_course_cover_pipeline_asset,
    )
    monkeypatch.setattr(
        media_assets_repo,
        "mark_media_asset_ready_from_worker",
        fake_mark_ready,
    )

    result = await media_assets_repo.mark_course_cover_ready_from_worker(
        media_id=media_id,
        playback_object_path="media/derived/cover/courses/course-1/source.jpg",
        playback_format="jpg",
    )

    assert result == {"updated": True}
    assert calls["ready"] == {
        "media_id": media_id,
        "playback_object_path": "media/derived/cover/courses/course-1/source.jpg",
        "playback_format": "jpg",
    }


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
        }

    monkeypatch.setattr(media_assets_repo, "get_media_asset", fake_get_media_asset)

    media_asset = await media_assets_repo.get_media_asset_access(str(uuid.uuid4()))

    assert media_asset is not None
    assert media_asset["storage_bucket"] == settings.media_public_bucket


async def test_get_media_asset_access_derives_public_profile_media_bucket(monkeypatch):
    async def fake_get_media_asset(_: str):
        return {
            "id": str(uuid.uuid4()),
            "media_type": "image",
            "purpose": "profile_media",
            "original_object_path": ("media/source/profile-avatar/user-1/avatar.png"),
            "playback_object_path": ("media/derived/profile-avatar/user-1/avatar.jpg"),
            "playback_format": "jpg",
            "state": "ready",
            "storage_bucket": None,
        }

    monkeypatch.setattr(media_assets_repo, "get_media_asset", fake_get_media_asset)

    media_asset = await media_assets_repo.get_media_asset_access(str(uuid.uuid4()))

    assert media_asset is not None
    assert media_asset["storage_bucket"] == settings.media_public_bucket


async def test_get_media_asset_access_derives_profile_media_source_bucket(monkeypatch):
    async def fake_get_media_asset(_: str):
        return {
            "id": str(uuid.uuid4()),
            "media_type": "image",
            "purpose": "profile_media",
            "original_object_path": ("media/source/profile-avatar/user-1/avatar.png"),
            "playback_object_path": None,
            "playback_format": None,
            "state": "pending_upload",
            "storage_bucket": None,
        }

    monkeypatch.setattr(media_assets_repo, "get_media_asset", fake_get_media_asset)

    media_asset = await media_assets_repo.get_media_asset_access(str(uuid.uuid4()))

    assert media_asset is not None
    assert media_asset["storage_bucket"] == settings.media_profile_bucket


def test_media_worker_queue_includes_profile_media_images():
    source = Path(media_assets_repo.__file__).read_text(encoding="utf-8")

    assert "'profile_media'::app.media_purpose" in source


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
