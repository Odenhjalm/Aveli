import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app import schemas
from app.routes import render_inputs
from app.services import app_render_inputs_service, storage_service


class _StaticUrl:
    def __init__(self, value: str):
        self._value = value

    def unicode_string(self) -> str:
        return self._value


class _EmptyStorage:
    def __init__(self, *, bucket: str):
        self.bucket = bucket

    def public_url(self, path: str) -> str:
        return " "


class _LessonBackgroundEmptyStorage:
    def __init__(self, *, bucket: str):
        self.bucket = bucket

    def public_url(self, path: str) -> str:
        if path == "ui/backgrounds/v1/bakgrundlektion.png":
            return " "
        return f"https://storage.test/storage/v1/object/public/{self.bucket}/{path}"


class _RecordingStorage:
    calls: list[tuple[str, str]] = []

    def __init__(self, *, bucket: str):
        self.bucket = bucket

    def public_url(self, path: str) -> str:
        self.calls.append((self.bucket, path))
        return f"https://storage.test/{self.bucket}/{path}"


@pytest.fixture(autouse=True)
def _public_storage_url(monkeypatch):
    monkeypatch.setattr(
        app_render_inputs_service.settings,
        "supabase_url",
        _StaticUrl("https://storage.test"),
        raising=False,
    )


def _expected_payload() -> dict:
    return {
        "brand": {
            "logo": {
                "resolved_url": (
                    "https://storage.test/storage/v1/object/public/public-media/"
                    "brand/logos/v1/aveli_logo_header_cropped.png"
                ),
            },
        },
        "ui": {
            "backgrounds": {
                "default": {
                    "resolved_url": (
                        "https://storage.test/storage/v1/object/public/public-media/"
                        "ui/backgrounds/v1/bakgrund.png"
                    ),
                },
                "lesson": {
                    "resolved_url": (
                        "https://storage.test/storage/v1/object/public/public-media/"
                        "ui/backgrounds/v1/bakgrundlektion.png"
                    ),
                },
                "observatory": {
                    "resolved_url": (
                        "https://storage.test/storage/v1/object/public/public-media/"
                        "ui/backgrounds/v1/observatorium_bg.png"
                    ),
                },
            },
        },
    }


def test_app_render_inputs_payload_resolves_assets_from_public_storage():
    payload = app_render_inputs_service.build_app_render_inputs_payload()

    assert payload == _expected_payload()
    assert set(payload["brand"]["logo"]) == {"resolved_url"}
    assert set(payload["ui"]["backgrounds"]["default"]) == {"resolved_url"}
    assert set(payload["ui"]["backgrounds"]["lesson"]) == {"resolved_url"}
    assert set(payload["ui"]["backgrounds"]["observatory"]) == {"resolved_url"}


def test_app_render_inputs_uses_storage_public_url_for_every_asset(monkeypatch):
    _RecordingStorage.calls = []
    monkeypatch.setattr(
        app_render_inputs_service.storage_service,
        "StorageService",
        _RecordingStorage,
    )

    app_render_inputs_service.build_app_render_inputs_payload()

    assert _RecordingStorage.calls == [
        ("public-media", "brand/logos/v1/aveli_logo_header_cropped.png"),
        ("public-media", "ui/backgrounds/v1/bakgrund.png"),
        ("public-media", "ui/backgrounds/v1/bakgrundlektion.png"),
        ("public-media", "ui/backgrounds/v1/observatorium_bg.png"),
    ]


def test_app_render_inputs_schema_forbids_authority_leaks():
    with pytest.raises(ValidationError):
        schemas.AppRenderInputsResponse(
            brand={
                "logo": {
                    "resolved_url": "https://storage.test/logo.png",
                    "asset_key": "aveli_brand_logo_header",
                },
            },
            ui={
                "backgrounds": {
                    "default": {"resolved_url": "https://storage.test/default.png"},
                    "lesson": {"resolved_url": "https://storage.test/lesson.png"},
                    "observatory": {
                        "resolved_url": "https://storage.test/observatory.png"
                    },
                },
            },
        )

    with pytest.raises(ValidationError):
        schemas.AppRenderInputsResponse(
            brand={
                "logo": {
                    "resolved_url": "https://storage.test/logo.png",
                },
            },
            ui={
                "backgrounds": {
                    "default": {
                        "resolved_url": "https://storage.test/default.png",
                        "object_path": "ui/backgrounds/v1/bakgrund.png",
                    },
                    "lesson": {"resolved_url": "https://storage.test/lesson.png"},
                    "observatory": {
                        "resolved_url": "https://storage.test/observatory.png"
                    },
                },
                "bucket": "public-media",
            },
        )


def test_app_render_inputs_payload_fails_when_any_url_is_empty(monkeypatch):
    monkeypatch.setattr(
        app_render_inputs_service.storage_service,
        "StorageService",
        _EmptyStorage,
    )

    with pytest.raises(storage_service.StorageServiceError):
        app_render_inputs_service.build_app_render_inputs_payload()

    monkeypatch.setattr(
        app_render_inputs_service.storage_service,
        "StorageService",
        _LessonBackgroundEmptyStorage,
    )

    with pytest.raises(storage_service.StorageServiceError):
        app_render_inputs_service.build_app_render_inputs_payload()


@pytest.mark.anyio("asyncio")
async def test_app_render_inputs_endpoint_returns_resolved_url_only(async_client):
    response = await async_client.get("/app/render-inputs")

    assert response.status_code == 200, response.text
    assert response.json() == _expected_payload()


def test_app_render_inputs_endpoint_fails_when_render_input_url_is_empty(monkeypatch):
    monkeypatch.setattr(
        app_render_inputs_service.storage_service,
        "StorageService",
        _EmptyStorage,
    )

    with pytest.raises(HTTPException) as exc_info:
        render_inputs.app_render_inputs()

    assert exc_info.value.status_code == 503
    assert exc_info.value.detail == "App render inputs are unavailable."
