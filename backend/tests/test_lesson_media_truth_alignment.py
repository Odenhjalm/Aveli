import pytest

from app.services import courses_service

pytestmark = pytest.mark.anyio("asyncio")


async def test_list_lesson_media_editor_suppresses_unresolvable_image_urls(
    monkeypatch,
):
    async def fake_list_lesson_media(_lesson_id: str):
        return [
            {
                "id": "image-1",
                "lesson_id": "lesson-1",
                "kind": "image",
                "storage_bucket": "public-media",
                "storage_path": "lessons/lesson-1/images/missing.png",
                "preferredUrl": "https://cdn.test/raw-image.png",
                "download_url": "https://cdn.test/raw-image.png",
                "playback_url": "https://cdn.test/raw-image.png",
                "original_name": "missing.png",
            }
        ]

    async def fake_fetch_storage_object_existence(_pairs):
        return {}, True

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.storage_objects,
        "fetch_storage_object_existence",
        fake_fetch_storage_object_existence,
        raising=True,
    )

    items = list(
        await courses_service.list_lesson_media("lesson-1", mode="editor_preview")
    )

    assert len(items) == 1
    item = items[0]
    assert item["resolvable_for_editor"] is False
    assert "preferredUrl" not in item
    assert "download_url" not in item
    assert "playback_url" not in item
    assert "signed_url" not in item


async def test_list_lesson_media_student_suppresses_unresolvable_audio_urls(
    monkeypatch,
):
    async def fake_list_lesson_media(_lesson_id: str):
        return [
            {
                "id": "audio-1",
                "lesson_id": "lesson-1",
                "kind": "audio",
                "storage_bucket": "course-media",
                "storage_path": "lessons/lesson-1/audio/missing.mp3",
                "media_id": "media-object-1",
                "original_name": "missing.mp3",
            }
        ]

    async def fake_fetch_storage_object_existence(_pairs):
        return {}, True

    def fake_attach_media_links(item: dict, *, purpose: str | None = None) -> None:
        item["download_url"] = "https://cdn.test/raw-audio.mp3"
        item["playback_url"] = "https://stream.test/raw-audio.mp3"
        item["signed_url"] = "https://signed.test/raw-audio.mp3"
        item["signed_url_expires_at"] = "2099-01-01T00:00:00+00:00"

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.storage_objects,
        "fetch_storage_object_existence",
        fake_fetch_storage_object_existence,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_signer,
        "attach_media_links",
        fake_attach_media_links,
        raising=True,
    )

    items = list(
        await courses_service.list_lesson_media("lesson-1", mode="student_render")
    )

    assert len(items) == 1
    item = items[0]
    assert item["resolvable_for_student"] is False
    assert "download_url" not in item
    assert "playback_url" not in item
    assert "signed_url" not in item
    assert "signed_url_expires_at" not in item
