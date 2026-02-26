import pytest

from app.utils.media_paths import normalize_storage_path


def test_storage_path_never_contains_bucket_prefix():
    bucket = "public-media"
    lesson_id = "abc123"
    filename = "file.mp3"

    path = f"lessons/{lesson_id}/{filename}"

    assert not path.startswith(f"{bucket}/")


def test_storage_path_rejects_bucket_prefix():
    with pytest.raises(
        RuntimeError,
        match="Invalid storage_path contains bucket prefix: public-media/lessons/x.mp3",
    ):
        normalize_storage_path("public-media", "public-media/lessons/x.mp3")
