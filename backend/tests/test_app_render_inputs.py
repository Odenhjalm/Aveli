import pytest
from pydantic import ValidationError

from app import schemas
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


@pytest.fixture(autouse=True)
def _brand_logo_public_storage_url(monkeypatch):
    monkeypatch.setattr(
        app_render_inputs_service.settings,
        "supabase_url",
        _StaticUrl("https://storage.test"),
        raising=False,
    )


def test_app_render_inputs_payload_resolves_brand_logo_from_public_storage():
    payload = app_render_inputs_service.build_app_render_inputs_payload()

    assert payload == {
        "brand": {
            "logo": {
                "resolved_url": (
                    "https://storage.test/storage/v1/object/public/public-media/"
                    "brand/logos/v1/aveli_logo_header_cropped.png"
                ),
            },
        },
    }
    assert set(payload["brand"]["logo"]) == {"resolved_url"}


def test_app_render_inputs_schema_forbids_logo_authority_leaks():
    with pytest.raises(ValidationError):
        schemas.AppRenderInputsResponse(
            brand={
                "logo": {
                    "resolved_url": "https://storage.test/logo.png",
                    "asset_key": "aveli_brand_logo_header",
                },
            },
        )

    with pytest.raises(ValidationError):
        schemas.AppRenderInputsResponse(
            brand={
                "logo": {
                    "resolved_url": "https://storage.test/logo.png",
                    "bucket": "public-media",
                },
            },
        )


def test_app_render_inputs_payload_fails_when_brand_logo_url_is_empty(monkeypatch):
    monkeypatch.setattr(
        app_render_inputs_service.storage_service,
        "StorageService",
        _EmptyStorage,
    )

    with pytest.raises(storage_service.StorageServiceError):
        app_render_inputs_service.build_app_render_inputs_payload()


@pytest.mark.anyio("asyncio")
async def test_app_render_inputs_endpoint_returns_resolved_url_only(async_client):
    response = await async_client.get("/app/render-inputs")

    assert response.status_code == 200, response.text
    assert response.json() == {
        "brand": {
            "logo": {
                "resolved_url": (
                    "https://storage.test/storage/v1/object/public/public-media/"
                    "brand/logos/v1/aveli_logo_header_cropped.png"
                ),
            },
        },
    }


@pytest.mark.anyio("asyncio")
async def test_app_render_inputs_endpoint_fails_when_brand_logo_url_is_empty(
    async_client,
    monkeypatch,
):
    monkeypatch.setattr(
        app_render_inputs_service.storage_service,
        "StorageService",
        _EmptyStorage,
    )

    response = await async_client.get("/app/render-inputs")

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal Server Error"}
