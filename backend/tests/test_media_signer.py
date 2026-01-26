from datetime import datetime

import pytest

from app.utils import media_signer


@pytest.fixture(autouse=True)
def reset_settings(monkeypatch):
    """Ensure settings mutations do not leak between tests."""
    original_secret = media_signer.settings.media_signing_secret
    original_ttl = media_signer.settings.media_signing_ttl_seconds
    original_legacy = media_signer.settings.media_allow_legacy_media
    yield
    media_signer.settings.media_signing_secret = original_secret
    media_signer.settings.media_signing_ttl_seconds = original_ttl
    media_signer.settings.media_allow_legacy_media = original_legacy


def test_attach_media_links_when_legacy_enabled(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_allow_legacy_media", True, raising=False)
    monkeypatch.setattr(media_signer.settings, "media_signing_secret", None, raising=False)

    item = {"id": "abc123"}
    media_signer.attach_media_links(item)

    assert item["download_url"] == "/studio/media/abc123"
    assert "signed_url" not in item
    assert "signed_url_expires_at" not in item


def test_attach_media_links_when_legacy_disabled_but_no_signer(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_allow_legacy_media", False, raising=False)
    monkeypatch.setattr(media_signer.settings, "media_signing_secret", None, raising=False)

    item = {"id": "xyz789"}
    media_signer.attach_media_links(item)

    # Fallback should still provide a legacy download URL for local dev.
    assert item["download_url"] == "/studio/media/xyz789"
    assert "signed_url" not in item


def test_attach_media_links_with_signing_secret(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_allow_legacy_media", False, raising=False)
    monkeypatch.setattr(
        media_signer.settings, "media_signing_secret", "dev-secret", raising=False
    )
    monkeypatch.setattr(
        media_signer.settings, "media_signing_ttl_seconds", 60, raising=False
    )

    item = {"id": "media42"}
    media_signer.attach_media_links(item)

    assert "signed_url" in item
    assert item["signed_url"].startswith("/media/stream/")
    # ensure expiry is ISO formatted
    expires = datetime.fromisoformat(item["signed_url_expires_at"])
    assert isinstance(expires, datetime)
    # No legacy URL when signer works.
    assert "download_url" not in item


def test_attach_media_links_prefers_api_files(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_allow_legacy_media", True, raising=False)
    item = {
        "id": "media42",
        "storage_path": "public-media/courses/lesson-1/sample.png",
    }
    media_signer.attach_media_links(item)
    assert item["download_url"] == "/api/files/public-media/courses/lesson-1/sample.png"


def test_attach_media_links_excludes_private_bucket(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_allow_legacy_media", True, raising=False)
    item = {
        "id": "media84",
        "storage_path": "course-media/course-1/lesson-1/private.mp4",
    }
    media_signer.attach_media_links(item)
    assert item["download_url"] == "/studio/media/media84"


def test_attach_cover_links_strips_legacy_cover():
    course = {
        "cover_url": "/studio/media/cover123",
        "signed_cover_url": "/media/stream/legacy",
    }
    media_signer.attach_cover_links(course)
    assert course.get("cover_url") is None
    assert "signed_cover_url" not in course
    assert "signed_cover_url_expires_at" not in course


def test_attach_cover_links_allows_public_media_path():
    course = {
        "cover_url": "/api/files/public-media/courses/cover.jpg",
    }
    media_signer.attach_cover_links(course)
    assert course.get("cover_url") == "/api/files/public-media/courses/cover.jpg"
