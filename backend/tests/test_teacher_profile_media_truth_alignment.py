from app.repositories import teacher_profile_media


def test_populate_media_links_suppresses_legacy_lesson_source_urls(monkeypatch):
    def fake_attach_media_links(item: dict, *, purpose: str | None = None) -> None:
        item["download_url"] = "https://cdn.test/legacy-lesson.mp3"
        item["signed_url"] = "https://signed.test/legacy-lesson.mp3"
        item["signed_url_expires_at"] = "2099-01-01T00:00:00+00:00"

    monkeypatch.setattr(
        teacher_profile_media.media_signer,
        "attach_media_links",
        fake_attach_media_links,
        raising=True,
    )

    row = teacher_profile_media._populate_media_links(
        {
            "lesson_media_id": "lesson-media-1",
            "lesson_media_storage_bucket": "lesson-media",
            "lesson_media_storage_path": "lessons/lesson-1/audio/legacy.mp3",
            "lesson_media_media_asset_id": None,
            "lesson_media_state": None,
        }
    )

    assert "lesson_media_download_url" not in row
    assert "lesson_media_signed_url" not in row
    assert "lesson_media_signed_url_expires_at" not in row


def test_populate_media_links_keeps_ready_asset_lesson_source_urls(monkeypatch):
    def fake_attach_media_links(item: dict, *, purpose: str | None = None) -> None:
        item["download_url"] = "https://cdn.test/ready-lesson.mp3"
        item["signed_url"] = "https://signed.test/ready-lesson.mp3"
        item["signed_url_expires_at"] = "2099-01-01T00:00:00+00:00"

    monkeypatch.setattr(
        teacher_profile_media.media_signer,
        "attach_media_links",
        fake_attach_media_links,
        raising=True,
    )

    row = teacher_profile_media._populate_media_links(
        {
            "lesson_media_id": "lesson-media-1",
            "lesson_media_storage_bucket": "course-media",
            "lesson_media_storage_path": "media/derived/audio/lesson.mp3",
            "lesson_media_media_asset_id": "asset-1",
            "lesson_media_state": "ready",
        }
    )

    assert row["lesson_media_download_url"] == "https://cdn.test/ready-lesson.mp3"
    assert row["lesson_media_signed_url"] == "https://signed.test/ready-lesson.mp3"
    assert (
        row["lesson_media_signed_url_expires_at"] == "2099-01-01T00:00:00+00:00"
    )
