import importlib
import sys

import pytest

from app.services.special_offers_service import SpecialOfferDomainError


def test_special_offer_execution_service_lazy_loads_composite_module():
    sys.modules.pop("app.services.special_offer_execution_service", None)
    sys.modules.pop("app.services.special_offer_composite_service", None)

    importlib.import_module("app.services.special_offer_execution_service")

    assert "app.services.special_offer_composite_service" not in sys.modules


@pytest.mark.anyio("asyncio")
async def test_compose_special_offer_image_returns_domain_error_without_pillow(
    monkeypatch,
):
    module = importlib.import_module("app.services.special_offer_composition_service")
    monkeypatch.setattr(
        module,
        "_PIL_IMPORT_ERROR",
        ModuleNotFoundError("No module named 'PIL'"),
    )

    with pytest.raises(SpecialOfferDomainError) as exc_info:
        await module.compose_special_offer_image(
            source_bytes=[b"fake-image"],
            price_amount_cents=1000,
        )

    assert exc_info.value.code == "special_offer_domain_unavailable"
    assert exc_info.value.status_code == 503
