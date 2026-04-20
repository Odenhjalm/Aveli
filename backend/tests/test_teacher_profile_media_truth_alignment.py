import asyncio
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app import schemas
from app.config import settings
from app.utils import profile_media as profile_media_utils


def _timestamp() -> datetime:
    return datetime.now(timezone.utc)


def test_profile_media_item_uses_subject_asset_visibility_shape() -> None:
    row = {
        "id": str(uuid4()),
        "subject_user_id": str(uuid4()),
        "media_asset_id": str(uuid4()),
        "visibility": "published",
        "media": None,
    }

    item = schemas.TeacherProfileMediaItem(**row)

    assert item.subject_user_id is not None
    assert item.media_asset_id is not None
    assert item.visibility == schemas.ProfileMediaVisibility.published


def test_profile_media_item_from_row_uses_runtime_media_for_ready_jpg_image(
    monkeypatch,
) -> None:
    row = {
        "id": str(uuid4()),
        "subject_user_id": str(uuid4()),
        "media_asset_id": str(uuid4()),
        "visibility": "published",
    }

    async def _fake_runtime_row(media_asset_id: str):
        assert media_asset_id == row["media_asset_id"]
        return {
            "media_type": "image",
            "purpose": "profile_media",
            "playback_object_path": "profiles/example.jpg",
            "playback_format": "jpg",
            "state": "ready",
        }

    monkeypatch.setattr(
        profile_media_utils.runtime_media_repo,
        "get_profile_runtime_media",
        _fake_runtime_row,
    )
    monkeypatch.setattr(
        profile_media_utils.storage_service,
        "get_storage_service",
        lambda bucket: SimpleNamespace(
            public_url=lambda path: f"https://cdn.example/{bucket}/{path}"
        ),
    )

    item = asyncio.run(profile_media_utils.profile_media_item_from_row(row))

    assert item.media is not None
    assert str(item.media.media_id) == row["media_asset_id"]
    assert item.media.state == "ready"
    assert (
        item.media.resolved_url
        == f"https://cdn.example/{settings.media_public_bucket}/profiles/example.jpg"
    )
    dumped = item.model_dump(mode="json")
    assert set(dumped["media"]) == {"media_id", "state", "resolved_url"}
    assert "storage_path" not in dumped
    assert "playback_object_path" not in dumped
    assert "original_object_path" not in dumped


def test_profile_media_item_from_row_hides_media_when_runtime_truth_is_missing(
    monkeypatch,
) -> None:
    row = {
        "id": str(uuid4()),
        "subject_user_id": str(uuid4()),
        "media_asset_id": str(uuid4()),
        "visibility": "draft",
    }

    async def _missing_runtime_row(media_asset_id: str):
        assert media_asset_id == row["media_asset_id"]
        return None

    monkeypatch.setattr(
        profile_media_utils.runtime_media_repo,
        "get_profile_runtime_media",
        _missing_runtime_row,
    )

    item = asyncio.run(profile_media_utils.profile_media_item_from_row(row))

    assert item.visibility == schemas.ProfileMediaVisibility.draft
    assert item.media is None


@pytest.mark.parametrize("playback_format", ["jpeg", "png"])
def test_profile_media_item_from_row_blocks_noncanonical_ready_image_formats(
    monkeypatch,
    playback_format: str,
) -> None:
    row = {
        "id": str(uuid4()),
        "subject_user_id": str(uuid4()),
        "media_asset_id": str(uuid4()),
        "visibility": "published",
    }

    async def _fake_runtime_row(media_asset_id: str):
        assert media_asset_id == row["media_asset_id"]
        return {
            "media_type": "image",
            "purpose": "profile_media",
            "playback_object_path": f"profiles/example.{playback_format}",
            "playback_format": playback_format,
            "state": "ready",
        }

    monkeypatch.setattr(
        profile_media_utils.runtime_media_repo,
        "get_profile_runtime_media",
        _fake_runtime_row,
    )
    monkeypatch.setattr(
        profile_media_utils.storage_service,
        "get_storage_service",
        lambda bucket: SimpleNamespace(
            public_url=lambda path: f"https://cdn.example/{bucket}/{path}"
        ),
    )

    item = asyncio.run(profile_media_utils.profile_media_item_from_row(row))

    assert item.media is None


@pytest.mark.parametrize(
    "runtime_row",
    [
        {
            "media_type": "image",
            "purpose": "profile_media",
            "playback_object_path": "profiles/example.jpg",
            "playback_format": "jpg",
            "state": "uploaded",
        },
        {
            "media_type": "image",
            "purpose": "course_cover",
            "playback_object_path": "profiles/example.jpg",
            "playback_format": "jpg",
            "state": "ready",
        },
        {
            "media_type": "audio",
            "purpose": "profile_media",
            "playback_object_path": "profiles/example.mp3",
            "playback_format": "mp3",
            "state": "ready",
        },
        {
            "media_type": "image",
            "purpose": "profile_media",
            "playback_object_path": "",
            "playback_format": "jpg",
            "state": "ready",
        },
    ],
)
def test_profile_media_item_from_row_hides_noncanonical_runtime_rows(
    monkeypatch,
    runtime_row: dict[str, str],
) -> None:
    row = {
        "id": str(uuid4()),
        "subject_user_id": str(uuid4()),
        "media_asset_id": str(uuid4()),
        "visibility": "published",
    }

    async def _fake_runtime_row(media_asset_id: str):
        assert media_asset_id == row["media_asset_id"]
        return dict(runtime_row)

    monkeypatch.setattr(
        profile_media_utils.runtime_media_repo,
        "get_profile_runtime_media",
        _fake_runtime_row,
    )

    item = asyncio.run(profile_media_utils.profile_media_item_from_row(row))

    assert item.media is None


def test_profile_media_item_from_row_hides_media_when_resolved_url_is_missing(
    monkeypatch,
) -> None:
    row = {
        "id": str(uuid4()),
        "subject_user_id": str(uuid4()),
        "media_asset_id": str(uuid4()),
        "visibility": "published",
    }

    async def _fake_runtime_row(media_asset_id: str):
        assert media_asset_id == row["media_asset_id"]
        return {
            "media_type": "image",
            "purpose": "profile_media",
            "playback_object_path": "profiles/example.jpg",
            "playback_format": "jpg",
            "state": "ready",
        }

    monkeypatch.setattr(
        profile_media_utils.runtime_media_repo,
        "get_profile_runtime_media",
        _fake_runtime_row,
    )
    monkeypatch.setattr(
        profile_media_utils.storage_service,
        "get_storage_service",
        lambda bucket: SimpleNamespace(public_url=lambda path: "   "),
    )

    item = asyncio.run(profile_media_utils.profile_media_item_from_row(row))

    assert item.media is None
