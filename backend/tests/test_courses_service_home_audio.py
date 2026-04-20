import uuid

import pytest

from app.services import courses_service, home_audio_service

pytestmark = pytest.mark.anyio("asyncio")


def _home_audio_item(*, media_id: str) -> dict[str, object]:
    return {
        "source_type": "direct_upload",
        "title": "Canonical track",
        "lesson_title": None,
        "course_id": None,
        "course_title": None,
        "course_slug": None,
        "teacher_id": str(uuid.uuid4()),
        "teacher_name": "Teacher",
        "created_at": None,
        "media": {
            "media_id": media_id,
            "state": "ready",
            "resolved_url": "https://stream.local/canonical.mp3",
        },
    }


async def test_courses_service_home_audio_delegates_to_canonical_owner(monkeypatch):
    user_id = str(uuid.uuid4())
    media_id = str(uuid.uuid4())
    canonical_items = [_home_audio_item(media_id=media_id)]
    calls: list[tuple[str, int]] = []

    async def fake_list_home_audio_media(
        candidate_user_id: str,
        *,
        limit: int = 12,
    ):
        calls.append((candidate_user_id, limit))
        return canonical_items

    monkeypatch.setattr(
        home_audio_service,
        "list_home_audio_media",
        fake_list_home_audio_media,
        raising=True,
    )

    items = await courses_service.list_home_audio_media(user_id, limit=7)

    assert items is canonical_items
    assert calls == [(user_id, 7)]


async def test_courses_service_home_audio_result_matches_canonical_entry_path(
    monkeypatch,
):
    user_id = str(uuid.uuid4())
    canonical_items = [_home_audio_item(media_id=str(uuid.uuid4()))]

    async def fake_list_home_audio_media(
        candidate_user_id: str,
        *,
        limit: int = 12,
    ):
        assert candidate_user_id == user_id
        assert limit == 3
        return canonical_items

    monkeypatch.setattr(
        home_audio_service,
        "list_home_audio_media",
        fake_list_home_audio_media,
        raising=True,
    )

    delegated_items = await courses_service.list_home_audio_media(user_id, limit=3)
    canonical_path_items = await home_audio_service.list_home_audio_media(
        user_id,
        limit=3,
    )

    assert delegated_items == canonical_path_items
    assert set(delegated_items[0]) == {
        "source_type",
        "title",
        "lesson_title",
        "course_id",
        "course_title",
        "course_slug",
        "teacher_id",
        "teacher_name",
        "created_at",
        "media",
    }
    assert set(delegated_items[0]["media"]) == {
        "media_id",
        "state",
        "resolved_url",
    }


def test_courses_service_home_audio_has_no_independent_composition_path():
    assert not hasattr(courses_service, "_compose_home_audio_media")
    assert not hasattr(courses_service, "_normalized_home_audio_state")
    assert not hasattr(courses_service, "home_audio_runtime_repo")
