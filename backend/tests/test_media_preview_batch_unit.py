import uuid

import pytest
from fastapi import HTTPException

from app import schemas
from app.routes import api_media

pytestmark = pytest.mark.anyio("asyncio")


async def test_request_media_previews_isolates_invalid_and_missing_items(monkeypatch):
    user_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    course_id = str(uuid.uuid4())
    valid_id = str(uuid.uuid4())
    missing_id = str(uuid.uuid4())
    malformed_id = "not-a-uuid"

    async def fake_list_lesson_media_by_ids(candidate_ids: list[str]):
        assert candidate_ids == [valid_id, missing_id]
        return [{"id": valid_id, "lesson_id": lesson_id}]

    async def fake_lesson_course_ids(candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return None, course_id

    async def fake_is_course_owner(candidate_user_id: str, candidate_course_id: str):
        assert candidate_user_id == user_id
        assert candidate_course_id == course_id
        return True

    async def fake_list_lesson_media(candidate_lesson_id: str, mode: str = "editor_preview"):
        assert candidate_lesson_id == lesson_id
        assert mode == "editor_preview"
        return [
            {
                "id": valid_id,
                "lesson_id": lesson_id,
                "kind": "image",
                "original_name": "valid.png",
            }
        ]

    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        assert lesson_media_id == valid_id
        assert user_id
        return {
            "url": f"https://stream.local/{lesson_media_id}.bin",
            "playback_url": f"https://stream.local/{lesson_media_id}.bin",
        }

    monkeypatch.setattr(
        api_media.courses_repo,
        "list_lesson_media_by_ids",
        fake_list_lesson_media_by_ids,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.courses_service,
        "lesson_course_ids",
        fake_lesson_course_ids,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.models,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.courses_service,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    response = await api_media.request_media_previews(
        request=None,
        payload=schemas.MediaPreviewBatchRequest(ids=[valid_id, malformed_id, missing_id]),
        current={"id": user_id},
    )

    assert list(response.items.keys()) == [valid_id, malformed_id, missing_id]
    assert response.items[valid_id].authoritative_editor_ready is True
    assert response.items[valid_id].resolved_preview_url == (
        f"https://stream.local/{valid_id}.bin"
    )
    assert response.items[malformed_id].authoritative_editor_ready is False
    assert response.items[malformed_id].failure_reason == "invalid_id"
    assert response.items[missing_id].authoritative_editor_ready is False
    assert response.items[missing_id].failure_reason == "not_found"


async def test_request_media_previews_isolates_unresolvable_sibling(monkeypatch):
    user_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    course_id = str(uuid.uuid4())
    valid_id = str(uuid.uuid4())
    stale_id = str(uuid.uuid4())

    async def fake_list_lesson_media_by_ids(candidate_ids: list[str]):
        assert candidate_ids == [valid_id, stale_id]
        return [
            {"id": valid_id, "lesson_id": lesson_id},
            {"id": stale_id, "lesson_id": lesson_id},
        ]

    async def fake_lesson_course_ids(candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return None, course_id

    async def fake_is_course_owner(candidate_user_id: str, candidate_course_id: str):
        assert candidate_user_id == user_id
        assert candidate_course_id == course_id
        return True

    async def fake_list_lesson_media(candidate_lesson_id: str, mode: str = "editor_preview"):
        assert candidate_lesson_id == lesson_id
        assert mode == "editor_preview"
        return [
            {
                "id": valid_id,
                "lesson_id": lesson_id,
                "kind": "video",
                "original_name": "valid.mp4",
            },
            {
                "id": stale_id,
                "lesson_id": lesson_id,
                "kind": "video",
                "original_name": "stale.mp4",
            },
        ]

    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        assert user_id
        if lesson_media_id == stale_id:
            raise HTTPException(status_code=404, detail="Lesson media has no playable source")
        assert lesson_media_id == valid_id
        return {
            "url": f"https://stream.local/{lesson_media_id}.mp4",
            "playback_url": f"https://stream.local/{lesson_media_id}.mp4",
        }

    monkeypatch.setattr(
        api_media.courses_repo,
        "list_lesson_media_by_ids",
        fake_list_lesson_media_by_ids,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.courses_service,
        "lesson_course_ids",
        fake_lesson_course_ids,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.models,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.courses_service,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    response = await api_media.request_media_previews(
        request=None,
        payload=schemas.MediaPreviewBatchRequest(ids=[valid_id, stale_id]),
        current={"id": user_id},
    )

    assert list(response.items.keys()) == [valid_id, stale_id]
    assert response.items[valid_id].authoritative_editor_ready is True
    assert response.items[valid_id].resolved_preview_url == (
        f"https://stream.local/{valid_id}.mp4"
    )
    assert response.items[stale_id].authoritative_editor_ready is False
    assert response.items[stale_id].resolved_preview_url is None
    assert response.items[stale_id].failure_reason == "unresolvable"


async def test_request_media_previews_falls_back_to_public_image_url(monkeypatch):
    user_id = str(uuid.uuid4())
    lesson_id = str(uuid.uuid4())
    course_id = str(uuid.uuid4())
    image_id = str(uuid.uuid4())

    async def fake_list_lesson_media_by_ids(candidate_ids: list[str]):
        assert candidate_ids == [image_id]
        return [{"id": image_id, "lesson_id": lesson_id}]

    async def fake_lesson_course_ids(candidate_lesson_id: str):
        assert candidate_lesson_id == lesson_id
        return None, course_id

    async def fake_is_course_owner(candidate_user_id: str, candidate_course_id: str):
        assert candidate_user_id == user_id
        assert candidate_course_id == course_id
        return True

    async def fake_list_lesson_media(candidate_lesson_id: str, mode: str = "editor_preview"):
        assert candidate_lesson_id == lesson_id
        assert mode == "editor_preview"
        return [
            {
                "id": image_id,
                "lesson_id": lesson_id,
                "kind": "image",
                "original_name": "cover.png",
                "preferredUrl": "https://cdn.public.test/course-images/cover.png",
            }
        ]

    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        assert lesson_media_id == image_id
        raise HTTPException(status_code=404, detail="Lesson media has no playable source")

    monkeypatch.setattr(
        api_media.courses_repo,
        "list_lesson_media_by_ids",
        fake_list_lesson_media_by_ids,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.courses_service,
        "lesson_course_ids",
        fake_lesson_course_ids,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.models,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.courses_service,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        api_media.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    response = await api_media.request_media_previews(
        request=None,
        payload=schemas.MediaPreviewBatchRequest(ids=[image_id]),
        current={"id": user_id},
    )

    assert response.items[image_id].authoritative_editor_ready is False
    assert response.items[image_id].resolved_preview_url == (
        "https://cdn.public.test/course-images/cover.png"
    )
    assert response.items[image_id].failure_reason == "unresolvable"
