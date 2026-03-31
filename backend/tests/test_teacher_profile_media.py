from datetime import datetime, timezone
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app import schemas


def _uuid() -> str:
    return str(uuid4())


def _timestamp() -> datetime:
    return datetime.now(timezone.utc)


def test_profile_media_create_requires_explicit_non_default_fields() -> None:
    with pytest.raises(ValidationError):
        schemas.TeacherProfileMediaCreate(
            media_kind=schemas.TeacherProfileMediaKind.lesson_media,
            lesson_media_id=_uuid(),
        )


def test_profile_media_create_accepts_explicit_lesson_media_identity() -> None:
    payload = schemas.TeacherProfileMediaCreate(
        media_kind=schemas.TeacherProfileMediaKind.lesson_media,
        lesson_media_id=_uuid(),
        position=0,
        is_published=True,
        enabled_for_home_player=False,
    )

    assert payload.lesson_media_id is not None
    assert payload.seminar_recording_id is None
    assert payload.external_url is None


def test_profile_media_create_accepts_explicit_seminar_recording_identity() -> None:
    payload = schemas.TeacherProfileMediaCreate(
        media_kind=schemas.TeacherProfileMediaKind.seminar_recording,
        seminar_recording_id=_uuid(),
        position=1,
        is_published=False,
        enabled_for_home_player=True,
    )

    assert payload.lesson_media_id is None
    assert payload.seminar_recording_id is not None
    assert payload.external_url is None


def test_profile_media_create_accepts_explicit_external_identity() -> None:
    payload = schemas.TeacherProfileMediaCreate(
        media_kind=schemas.TeacherProfileMediaKind.external,
        external_url="https://example.com/feature",
        position=3,
        is_published=True,
        enabled_for_home_player=False,
    )

    assert payload.lesson_media_id is None
    assert payload.seminar_recording_id is None
    assert payload.external_url == "https://example.com/feature"


def test_profile_media_create_rejects_mixed_identity_variants() -> None:
    with pytest.raises(
        ValidationError, match="lesson_media_id/seminar_recording_id"
    ):
        schemas.TeacherProfileMediaCreate(
            media_kind=schemas.TeacherProfileMediaKind.external,
            lesson_media_id=_uuid(),
            external_url="https://example.com/feature",
            position=0,
            is_published=True,
            enabled_for_home_player=False,
        )


def test_profile_media_item_has_no_blob_or_alias_fields() -> None:
    item = schemas.TeacherProfileMediaItem(
        id=_uuid(),
        teacher_id=_uuid(),
        media_kind=schemas.TeacherProfileMediaKind.external,
        lesson_media_id=None,
        seminar_recording_id=None,
        external_url="https://example.com/feature",
        title="Feature",
        description="Explicit profile-media contract",
        cover_media_id=None,
        cover_image_url=None,
        position=0,
        is_published=True,
        enabled_for_home_player=False,
        created_at=_timestamp(),
        updated_at=_timestamp(),
    )

    dumped = item.model_dump()

    assert "metadata" not in dumped
    assert "source" not in dumped
    assert "media_id" not in dumped
    assert "lesson_media_id" in dumped
    assert "seminar_recording_id" in dumped


def test_profile_media_item_rejects_collapsed_identity() -> None:
    with pytest.raises(ValidationError, match="seminar_recording_id/external_url"):
        schemas.TeacherProfileMediaItem(
            id=_uuid(),
            teacher_id=_uuid(),
            media_kind=schemas.TeacherProfileMediaKind.lesson_media,
            lesson_media_id=_uuid(),
            seminar_recording_id=None,
            external_url="https://example.com/feature",
            title="Invalid",
            description=None,
            cover_media_id=None,
            cover_image_url=None,
            position=0,
            is_published=True,
            enabled_for_home_player=False,
            created_at=_timestamp(),
            updated_at=_timestamp(),
        )


def test_profile_media_response_catalogs_use_explicit_source_lists() -> None:
    response = schemas.TeacherProfileMediaListResponse(
        items=[],
        lesson_media_sources=[],
        seminar_recording_sources=[],
    )

    dumped = response.model_dump()

    assert "lesson_media_sources" in dumped
    assert "seminar_recording_sources" in dumped
    assert "lesson_media" not in dumped
    assert "seminar_recordings" not in dumped
