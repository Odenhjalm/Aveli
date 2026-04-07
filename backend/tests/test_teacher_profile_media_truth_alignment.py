import asyncio
from datetime import datetime, timezone
from uuid import uuid4

from types import SimpleNamespace

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


def test_profile_media_item_from_row_uses_runtime_media_for_ready_image(monkeypatch) -> None:
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
            "playback_object_path": "profiles/example.jpg",
            "playback_format": "jpeg",
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
