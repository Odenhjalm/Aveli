from uuid import uuid4

import pytest
from pydantic import ValidationError

from app import schemas


def _uuid() -> str:
    return str(uuid4())

def test_profile_media_create_requires_explicit_visibility() -> None:
    with pytest.raises(ValidationError):
        schemas.TeacherProfileMediaCreate(media_asset_id=_uuid())


def test_profile_media_create_accepts_canonical_asset_identity() -> None:
    payload = schemas.TeacherProfileMediaCreate(
        media_asset_id=_uuid(),
        visibility=schemas.ProfileMediaVisibility.published,
    )

    assert payload.media_asset_id is not None
    assert payload.visibility == schemas.ProfileMediaVisibility.published


def test_profile_media_create_rejects_legacy_fields() -> None:
    with pytest.raises(
        ValidationError,
    ):
        schemas.TeacherProfileMediaCreate(
            media_asset_id=_uuid(),
            visibility=schemas.ProfileMediaVisibility.draft,
            lesson_media_id=_uuid(),
        )


def test_profile_media_item_has_only_canonical_profile_media_fields() -> None:
    item = schemas.TeacherProfileMediaItem(
        id=_uuid(),
        subject_user_id=_uuid(),
        media_asset_id=_uuid(),
        visibility=schemas.ProfileMediaVisibility.published,
        media=None,
    )

    dumped = item.model_dump()

    assert "subject_user_id" in dumped
    assert "media_asset_id" in dumped
    assert "visibility" in dumped
    assert "media" in dumped
    assert "teacher_id" not in dumped
    assert "media_kind" not in dumped
    assert "lesson_media_id" not in dumped
    assert "seminar_recording_id" not in dumped
    assert "external_url" not in dumped
    assert "cover_image_url" not in dumped
    assert "is_published" not in dumped
    assert "enabled_for_home_player" not in dumped


def test_profile_media_response_contains_only_items() -> None:
    response = schemas.TeacherProfileMediaListResponse(
        items=[],
    )

    dumped = response.model_dump()

    assert dumped == {"items": []}
