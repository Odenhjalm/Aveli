from __future__ import annotations

from dataclasses import dataclass

from ..config import settings
from . import storage_service


@dataclass(frozen=True)
class _BrandLogoAsset:
    asset_key: str
    object_path: str


_BRAND_HEADER_LOGO = _BrandLogoAsset(
    asset_key="aveli_brand_logo_header",
    object_path="brand/logos/v1/aveli_logo_header_cropped.png",
)


def _public_brand_logo_url(asset: _BrandLogoAsset) -> str:
    url = storage_service.StorageService(
        bucket=settings.media_public_bucket
    ).public_url(asset.object_path)
    normalized = str(url or "").strip()
    if not normalized:
        raise storage_service.StorageServiceError(
            f"Brand logo URL is empty for {asset.asset_key}"
        )
    return normalized


def build_app_render_inputs_payload() -> dict[str, dict[str, dict[str, str]]]:
    return {
        "brand": {
            "logo": {
                "resolved_url": _public_brand_logo_url(_BRAND_HEADER_LOGO),
            },
        },
    }
