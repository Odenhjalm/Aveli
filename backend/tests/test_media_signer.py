from datetime import datetime

import pytest

from app.utils import media_signer


@pytest.fixture(autouse=True)
def reset_settings(monkeypatch):
    """Ensure settings mutations do not leak between tests."""
    original_secret = media_signer.settings.media_signing_secret
    original_ttl = media_signer.settings.media_signing_ttl_seconds
    original_supabase_url = media_signer.settings.supabase_url
    original_service_role = media_signer.settings.supabase_service_role_key
    monkeypatch.setattr(media_signer.settings, "supabase_url", None, raising=False)
    monkeypatch.setattr(
        media_signer.settings, "supabase_service_role_key", None, raising=False
    )
    yield
    media_signer.settings.media_signing_secret = original_secret
    media_signer.settings.media_signing_ttl_seconds = original_ttl
    media_signer.settings.supabase_url = original_supabase_url
    media_signer.settings.supabase_service_role_key = original_service_role


def test_attach_media_links_without_public_or_signer_emits_no_urls(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_signing_secret", None, raising=False)

    item = {"id": "abc123"}
    media_signer.attach_media_links(item)

    assert "download_url" not in item
    assert "playback_url" not in item
    assert "signed_url" not in item
    assert "signed_url_expires_at" not in item


def test_attach_media_links_strips_noncanonical_legacy_rows(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_signing_secret", None, raising=False)

    item = {
        "id": "xyz789",
        "media_id": "legacy-object-1",
        "storage_bucket": "course-media",
        "storage_path": "media/source/audio/legacy.wav",
    }
    media_signer.attach_media_links(item)

    assert "download_url" not in item
    assert "playback_url" not in item
    assert "signed_url" not in item


def test_attach_media_links_with_signing_secret(monkeypatch):
    monkeypatch.setattr(
        media_signer.settings, "media_signing_secret", "dev-secret", raising=False
    )
    monkeypatch.setattr(
        media_signer.settings, "media_signing_ttl_seconds", 60, raising=False
    )

    item = {"id": "media42", "media_asset_id": "asset-42", "media_state": "ready"}
    media_signer.attach_media_links(item)

    assert "signed_url" in item
    assert item["signed_url"].startswith("/media/stream/")
    expires = datetime.fromisoformat(item["signed_url_expires_at"])
    assert isinstance(expires, datetime)
    assert "download_url" not in item


def test_attach_media_links_uses_supabase_public_url_when_configured(monkeypatch):
    class _FakeUrl:
        def __init__(self, value: str) -> None:
            self._value = value

        def unicode_string(self) -> str:
            return self._value

    monkeypatch.setattr(
        media_signer.settings,
        "supabase_url",
        _FakeUrl("https://example.supabase.co"),
        raising=False,
    )

    item = {
        "id": "media42",
        "media_asset_id": "asset-42",
        "media_state": "ready",
        "storage_path": "public-media/courses/lesson-1/sample.png",
        "storage_bucket": "public-media",
    }
    media_signer.attach_media_links(item)
    url = item["download_url"]
    assert url.startswith("https://example.supabase.co/storage/v1/object/public/public-media/")
    assert "/api/files/" not in url


def test_attach_media_links_falls_back_to_api_files_without_supabase(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "supabase_url", None, raising=False)
    item = {
        "id": "media42",
        "media_asset_id": "asset-42",
        "media_state": "ready",
        "storage_path": "public-media/courses/lesson-1/sample.png",
    }
    media_signer.attach_media_links(item)
    assert item["download_url"] == "/api/files/public-media/courses/lesson-1/sample.png"


def test_attach_media_links_builds_api_files_for_bucket_relative_public_path(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "supabase_url", None, raising=False)
    item = {
        "id": "media43",
        "media_asset_id": "asset-43",
        "media_state": "ready",
        "storage_path": "lessons/lesson-1/images/sample.webp",
        "storage_bucket": "public-media",
        "kind": "image",
    }
    media_signer.attach_media_links(item)
    assert item["download_url"] == "/api/files/public-media/lessons/lesson-1/images/sample.webp"
    assert item["playback_url"] == "/api/files/public-media/lessons/lesson-1/images/sample.webp"


def test_attach_media_links_does_not_sign_images(monkeypatch):
    monkeypatch.setattr(
        media_signer.settings, "media_signing_secret", "dev-secret", raising=False
    )
    monkeypatch.setattr(
        media_signer.settings, "media_signing_ttl_seconds", 60, raising=False
    )
    monkeypatch.setattr(media_signer.settings, "supabase_url", None, raising=False)

    item = {
        "id": "media44",
        "media_asset_id": "asset-44",
        "media_state": "ready",
        "kind": "image",
        "storage_bucket": "public-media",
        "storage_path": "public-media/lessons/lesson-1/images/sample.png",
    }
    media_signer.attach_media_links(item)
    assert item["download_url"] == "/api/files/public-media/lessons/lesson-1/images/sample.png"
    assert "signed_url" not in item
    assert "signed_url_expires_at" not in item


def test_attach_media_links_excludes_private_bucket(monkeypatch):
    monkeypatch.setattr(media_signer.settings, "media_signing_secret", None, raising=False)
    item = {
        "id": "media84",
        "media_asset_id": "asset-84",
        "media_state": "ready",
        "storage_path": "course-media/course-1/lesson-1/private.mp4",
    }
    media_signer.attach_media_links(item)
    assert "download_url" not in item
    assert "playback_url" not in item
    assert "signed_url" not in item


def test_attach_cover_links_strips_legacy_signed_fields_only():
    course = {
        "cover_url": "/studio/media/cover123",
        "signed_cover_url": "/media/stream/legacy",
    }
    media_signer.attach_cover_links(course)
    assert course.get("cover_url") == "/studio/media/cover123"
    assert "signed_cover_url" not in course
    assert "signed_cover_url_expires_at" not in course


def test_attach_cover_links_preserves_cover_url():
    course = {
        "cover_url": "/api/files/public-media/courses/cover.jpg",
    }
    media_signer.attach_cover_links(course)
    assert course.get("cover_url") == "/api/files/public-media/courses/cover.jpg"
