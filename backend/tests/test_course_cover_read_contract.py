from __future__ import annotations

from datetime import datetime, timezone
import logging
from types import SimpleNamespace

import pytest

from app.services import courses_service

pytestmark = pytest.mark.anyio("asyncio")


COURSE_ID = "course-1"
MEDIA_ID = "11111111-1111-1111-1111-111111111111"
DERIVED_PATH = "media/derived/cover/courses/course-1/cover.jpg"
LEGACY_URL = "/api/files/public-media/courses/legacy-cover.jpg"


class _FakeStorageService:
    def __init__(self, bucket: str) -> None:
        self.bucket = bucket

    def public_url(self, path: str) -> str:
        normalized = path.lstrip("/")
        return f"https://storage.local/{self.bucket}/{normalized}"

    async def get_presigned_url(self, path: str, ttl: int, *, download: bool = False):
        normalized = path.lstrip("/")
        return SimpleNamespace(
            url=f"https://signed.local/{self.bucket}/{normalized}",
            expires_in=ttl,
            headers={},
        )


def _course(*, cover_media_id: str | None = MEDIA_ID, cover_url: str | None = None) -> dict:
    return {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "cover_media_id": cover_media_id,
        "cover_url": cover_url,
    }


def _asset(*, state: str = "ready", path: str = DERIVED_PATH) -> dict:
    return {
        "id": MEDIA_ID,
        "course_id": COURSE_ID,
        "purpose": "course_cover",
        "state": state,
        "streaming_object_path": path,
        "streaming_storage_bucket": "public-media",
        "storage_bucket": "course-media",
    }


def _install_storage(monkeypatch, *, existing_pairs: dict[tuple[str, str], bool]):
    async def fake_fetch_storage_object_existence(pairs):
        normalized = {tuple(pair): existing_pairs.get(tuple(pair), False) for pair in pairs}
        return normalized, True

    monkeypatch.setattr(
        courses_service.storage_objects,
        "fetch_storage_object_existence",
        fake_fetch_storage_object_existence,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.storage_service,
        "get_storage_service",
        lambda bucket: _FakeStorageService(bucket),
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_signer.settings,
        "supabase_url",
        None,
        raising=False,
    )


async def test_resolve_course_cover_ready_asset_returns_control_plane(monkeypatch):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): True})

    async def fake_get_media_asset(media_id: str):
        assert media_id == MEDIA_ID
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
        cover_url=None,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "ready",
        "resolved_url": f"https://storage.local/public-media/{DERIVED_PATH}",
        "source": "control_plane",
    }


async def test_resolve_course_cover_uploaded_asset_uses_legacy_fallback(monkeypatch):
    async def fake_get_media_asset(media_id: str):
        return _asset(state="uploaded")

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_signer.settings,
        "supabase_url",
        None,
        raising=False,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
        cover_url=LEGACY_URL,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "legacy_fallback",
        "resolved_url": LEGACY_URL,
        "source": "legacy_cover_url",
    }


async def test_resolve_course_cover_missing_asset_uses_legacy_fallback(monkeypatch):
    async def fake_get_media_asset(media_id: str):
        return None

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_signer.settings,
        "supabase_url",
        None,
        raising=False,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
        cover_url=LEGACY_URL,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "legacy_fallback",
        "resolved_url": LEGACY_URL,
        "source": "legacy_cover_url",
    }


async def test_resolve_course_cover_missing_asset_without_legacy_returns_placeholder(
    monkeypatch,
):
    async def fake_get_media_asset(media_id: str):
        return None

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
        cover_url=None,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "placeholder",
        "resolved_url": None,
        "source": "placeholder",
    }


async def test_resolve_course_cover_missing_derived_bytes_never_returns_ready(monkeypatch):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): False})

    async def fake_get_media_asset(media_id: str):
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
        cover_url=LEGACY_URL,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "legacy_fallback",
        "resolved_url": LEGACY_URL,
        "source": "legacy_cover_url",
    }


async def test_resolve_course_cover_logs_source_mismatch(monkeypatch, caplog):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): True})

    async def fake_get_media_asset(media_id: str):
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    with caplog.at_level(logging.WARNING):
        cover = await courses_service.resolve_course_cover(
            course_id=COURSE_ID,
            cover_media_id=MEDIA_ID,
            cover_url="/api/files/public-media/courses/different-cover.jpg",
        )

    assert cover["source"] == "control_plane"
    assert "COURSE_COVER_RESOLVED_SOURCE_DISAGREE" in caplog.text


async def test_attach_course_cover_read_contract_respects_feature_flag(monkeypatch):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): True})

    async def fake_get_media_asset(media_id: str):
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    course_enabled = _course()
    monkeypatch.setenv("COURSE_COVER_RESOLVED_READ_ENABLED", "1")
    await courses_service.attach_course_cover_read_contract(course_enabled)
    assert course_enabled["cover"]["source"] == "control_plane"

    course_disabled = _course()
    monkeypatch.delenv("COURSE_COVER_RESOLVED_READ_ENABLED", raising=False)
    await courses_service.attach_course_cover_read_contract(course_disabled)
    assert "cover" not in course_disabled


async def test_courses_list_response_includes_cover_when_present(
    async_client, monkeypatch
):
    now = datetime.now(timezone.utc)

    async def fake_list_public_courses(**kwargs):
        return [
            {
                "id": MEDIA_ID,
                "slug": "course-1",
                "title": "Course 1",
                "description": "Example",
                "cover_url": None,
                "cover_media_id": MEDIA_ID,
                "cover": {
                    "media_id": MEDIA_ID,
                    "state": "ready",
                    "resolved_url": "https://storage.local/public-media/media/derived/cover/courses/course-1/cover.jpg",
                    "source": "control_plane",
                },
                "video_url": None,
                "is_free_intro": False,
                "journey_step": None,
                "price_amount_cents": 0,
                "currency": "sek",
                "stripe_product_id": None,
                "stripe_price_id": None,
                "is_published": True,
                "created_by": MEDIA_ID,
                "created_at": now,
                "updated_at": now,
            }
        ]

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["items"][0]["cover"]["source"] == "control_plane"


async def test_courses_list_response_omits_cover_when_absent(async_client, monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_list_public_courses(**kwargs):
        return [
            {
                "id": MEDIA_ID,
                "slug": "course-1",
                "title": "Course 1",
                "description": "Example",
                "cover_url": None,
                "cover_media_id": MEDIA_ID,
                "video_url": None,
                "is_free_intro": False,
                "journey_step": None,
                "price_amount_cents": 0,
                "currency": "sek",
                "stripe_product_id": None,
                "stripe_price_id": None,
                "is_published": True,
                "created_by": MEDIA_ID,
                "created_at": now,
                "updated_at": now,
            }
        ]

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    body = response.json()
    assert "cover" not in body["items"][0]
