import pytest

from app.main import normalize_storage_path
from app.services import courses_service
from app.utils import media_robustness


def test_rejects_bucket_prefix():
    bucket = "public-media"
    path = "public-media/abc/def/file.mp3"
    with pytest.raises(
        RuntimeError,
        match="Invalid storage_path contains bucket prefix: public-media/abc/def/file.mp3",
    ):
        normalize_storage_path(bucket, path)


def test_keeps_valid_path():
    bucket = "public-media"
    path = "abc/def/file.mp3"
    assert normalize_storage_path(bucket, path) == "abc/def/file.mp3"


def test_strips_leading_slash():
    bucket = "public-media"
    path = "/abc/file.mp3"
    assert normalize_storage_path(bucket, path) == "abc/file.mp3"


def test_empty_path_rejected():
    with pytest.raises(ValueError, match="storage_path cannot be empty"):
        normalize_storage_path("public-media", "   ")


def test_legacy_malformed_path_avoids_missing_bytes():
    item = {
        "id": "lesson-media-1",
        "kind": "audio",
        "storage_bucket": "public-media",
        "storage_path": "public-media/lessons/demo/file.mp3",
    }
    courses_service._attach_media_robustness(
        item,
        existence={},
        storage_table_available=True,
    )
    assert item["robustness_status"] == str(media_robustness.MediaStatus.manual_review)


def test_pipeline_malformed_path_avoids_missing_bytes():
    item = {
        "lesson_media_id": "lesson-media-2",
        "media_asset_id": "asset-1",
        "kind": "audio",
        "media_state": "ready",
        "storage_bucket": "public-media",
        "storage_path": "public-media/home-player/demo.mp3",
    }
    courses_service._attach_media_robustness(
        item,
        existence={},
        storage_table_available=True,
    )
    assert item["robustness_status"] == str(media_robustness.MediaStatus.manual_review)


def test_valid_missing_object_remains_missing_bytes():
    item = {
        "id": "lesson-media-3",
        "kind": "audio",
        "storage_bucket": "public-media",
        "storage_path": "lessons/demo/file.mp3",
    }
    courses_service._attach_media_robustness(
        item,
        existence={},
        storage_table_available=True,
    )
    assert item["robustness_status"] == str(media_robustness.MediaStatus.missing_bytes)
