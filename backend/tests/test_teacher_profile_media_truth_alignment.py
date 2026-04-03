from datetime import datetime, timezone
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app import schemas
from app.utils.profile_media import (
    lesson_media_source_from_row,
    recording_source_from_row,
)


def _timestamp() -> datetime:
    return datetime.now(timezone.utc)


def test_profile_media_item_uses_lesson_media_identity_only() -> None:
    row = {
        "id": str(uuid4()),
        "teacher_id": str(uuid4()),
        "media_kind": "lesson_media",
        "lesson_media_id": str(uuid4()),
        "seminar_recording_id": None,
        "external_url": None,
        "title": "Lesson feature",
        "description": "Breathing lesson",
        "cover_media_id": None,
        "cover_image_url": None,
        "position": 2,
        "is_published": True,
        "enabled_for_home_player": False,
        "created_at": _timestamp(),
        "updated_at": _timestamp(),
    }

    item = schemas.TeacherProfileMediaItem(**row)

    assert item.media_kind == schemas.TeacherProfileMediaKind.lesson_media
    assert item.lesson_media_id is not None
    assert item.seminar_recording_id is None
    assert item.external_url is None


def test_profile_media_item_uses_seminar_recording_identity_only() -> None:
    row = {
        "id": str(uuid4()),
        "teacher_id": str(uuid4()),
        "media_kind": "seminar_recording",
        "lesson_media_id": None,
        "seminar_recording_id": str(uuid4()),
        "external_url": None,
        "title": "Recording feature",
        "description": None,
        "cover_media_id": None,
        "cover_image_url": None,
        "position": 0,
        "is_published": False,
        "enabled_for_home_player": True,
        "created_at": _timestamp(),
        "updated_at": _timestamp(),
    }

    item = schemas.TeacherProfileMediaItem(**row)

    assert item.media_kind == schemas.TeacherProfileMediaKind.seminar_recording
    assert item.lesson_media_id is None
    assert item.seminar_recording_id is not None
    assert item.external_url is None


def test_profile_media_item_preserves_external_identity_without_collapse() -> None:
    row = {
        "id": str(uuid4()),
        "teacher_id": str(uuid4()),
        "media_kind": "external",
        "lesson_media_id": None,
        "seminar_recording_id": None,
        "external_url": "https://example.com/profile-media",
        "title": None,
        "description": None,
        "cover_media_id": None,
        "cover_image_url": None,
        "position": 1,
        "is_published": True,
        "enabled_for_home_player": False,
        "created_at": _timestamp(),
        "updated_at": _timestamp(),
    }

    item = schemas.TeacherProfileMediaItem(**row)

    assert item.media_kind == schemas.TeacherProfileMediaKind.external
    assert item.lesson_media_id is None
    assert item.seminar_recording_id is None
    assert item.external_url == "https://example.com/profile-media"


def test_profile_media_item_rejects_missing_explicit_fields() -> None:
    row = {
        "id": str(uuid4()),
        "teacher_id": str(uuid4()),
        "media_kind": "external",
        "lesson_media_id": None,
        "seminar_recording_id": None,
        "external_url": "https://example.com/profile-media",
        "title": None,
        "description": None,
        "cover_media_id": None,
        "cover_image_url": None,
        "position": None,
        "is_published": True,
        "enabled_for_home_player": False,
        "created_at": _timestamp(),
        "updated_at": _timestamp(),
    }

    with pytest.raises(ValidationError):
        schemas.TeacherProfileMediaItem(**row)


def test_lesson_source_preserves_explicit_optional_storage_fields() -> None:
    row = {
        "id": str(uuid4()),
        "lesson_id": str(uuid4()),
        "lesson_title": "Morning flow",
        "course_id": str(uuid4()),
        "course_title": "Breathwork",
        "course_slug": "breathwork",
        "kind": "audio",
        "storage_path": None,
        "storage_bucket": None,
        "content_type": "audio/mpeg",
        "duration_seconds": 320,
        "position": 0,
        "created_at": _timestamp(),
        "download_url": None,
        "signed_url": None,
        "signed_url_expires_at": None,
    }

    source = lesson_media_source_from_row(row)

    assert source.kind == "audio"
    assert source.storage_path is None
    assert source.storage_bucket is None


def test_recording_source_has_no_metadata_contract() -> None:
    row = {
        "id": str(uuid4()),
        "seminar_id": str(uuid4()),
        "seminar_title": "Live breath session",
        "session_id": str(uuid4()),
        "asset_url": "https://example.com/recording.mp4",
        "status": "ready",
        "duration_seconds": 1800,
        "byte_size": 1024,
        "published": True,
        "created_at": _timestamp(),
        "updated_at": _timestamp(),
    }

    source = recording_source_from_row(row)

    assert source.asset_url == "https://example.com/recording.mp4"
    assert source.status == "ready"
    assert not hasattr(source, "metadata")
