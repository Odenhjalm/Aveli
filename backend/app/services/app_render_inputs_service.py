from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from ..config import settings
from . import storage_service


@dataclass(frozen=True)
class _PublicRenderAsset:
    asset_key: str
    object_path: str


_BRAND_HEADER_LOGO = _PublicRenderAsset(
    asset_key="aveli_brand_logo_header",
    object_path="brand/logos/v1/aveli_logo_header_cropped.png",
)

_UI_BACKGROUND_DEFAULT = _PublicRenderAsset(
    asset_key="aveli_ui_background_default",
    object_path="ui/backgrounds/v1/bakgrund.png",
)

_UI_BACKGROUND_LESSON = _PublicRenderAsset(
    asset_key="aveli_ui_background_lesson",
    object_path="ui/backgrounds/v1/bakgrundlektion.png",
)

_UI_BACKGROUND_OBSERVATORY = _PublicRenderAsset(
    asset_key="aveli_ui_background_observatory",
    object_path="ui/backgrounds/v1/observatorium_bg.png",
)


def _public_render_asset_url(asset: _PublicRenderAsset) -> str:
    url = storage_service.StorageService(
        bucket=settings.media_public_bucket
    ).public_url(asset.object_path)
    normalized = str(url or "").strip()
    if not normalized:
        raise storage_service.StorageServiceError(
            f"Render input URL is empty for {asset.asset_key}"
        )
    return normalized


def build_app_render_inputs_payload() -> dict[str, Any]:
    return {
        "brand": {
            "logo": {
                "resolved_url": _public_render_asset_url(_BRAND_HEADER_LOGO),
            },
        },
        "ui": {
            "backgrounds": {
                "default": {
                    "resolved_url": _public_render_asset_url(
                        _UI_BACKGROUND_DEFAULT
                    ),
                },
                "lesson": {
                    "resolved_url": _public_render_asset_url(_UI_BACKGROUND_LESSON),
                },
                "observatory": {
                    "resolved_url": _public_render_asset_url(
                        _UI_BACKGROUND_OBSERVATORY
                    ),
                },
            },
        },
    }
