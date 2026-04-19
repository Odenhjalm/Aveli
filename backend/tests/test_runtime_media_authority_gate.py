from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.config import settings
from app.services import courses_service


pytestmark = pytest.mark.anyio("asyncio")


class _FakeStorageService:
    def public_url(self, path: str) -> str:
        normalized = path.lstrip("/")
        return f"https://storage.local/{settings.media_public_bucket}/{normalized}"


async def test_course_cover_read_contract_emits_backend_authored_media_only(
    monkeypatch,
) -> None:
    course_id = str(uuid4())
    media_id = str(uuid4())
    row = {
        "id": course_id,
        "cover_media_id": media_id,
    }

    async def _fake_get_course_cover_runtime_media(*, course_id: str, media_asset_id: str):
        assert course_id == row["id"]
        assert media_asset_id == media_id
        return {
            "course_id": course_id,
            "media_asset_id": media_asset_id,
            "media_type": "image",
            "purpose": "course_cover",
            "playback_object_path": "media/derived/cover/example.jpg",
            "playback_format": "jpg",
            "state": "ready",
        }

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        _fake_get_course_cover_runtime_media,
    )
    monkeypatch.setattr(
        courses_service.storage_service,
        "get_storage_service",
        lambda bucket: _FakeStorageService(),
    )

    await courses_service.attach_course_cover_read_contract(row)

    assert row["cover"] == {
        "media_id": media_id,
        "state": "ready",
        "resolved_url": (
            f"https://storage.local/{settings.media_public_bucket}/media/derived/cover/example.jpg"
        ),
    }
    assert "cover_url" not in row
    assert "signed_cover_url" not in row
    assert "signed_cover_url_expires_at" not in row


async def test_course_cover_read_contract_uses_null_without_runtime_row(
    monkeypatch,
) -> None:
    course_id = str(uuid4())
    media_id = str(uuid4())
    row = {
        "id": course_id,
        "cover_media_id": media_id,
    }

    async def _missing_runtime_row(*, course_id: str, media_asset_id: str):
        assert course_id == row["id"]
        assert media_asset_id == media_id
        return None

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        _missing_runtime_row,
    )
    monkeypatch.setattr(
        courses_service.storage_service,
        "get_storage_service",
        lambda bucket: _FakeStorageService(),
    )

    await courses_service.attach_course_cover_read_contract(row)

    assert row["cover"] is None
