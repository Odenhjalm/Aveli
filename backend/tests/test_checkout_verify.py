import pytest
import stripe

from app.config import settings

pytestmark = pytest.mark.anyio("asyncio")


def _set_stripe_env(monkeypatch) -> None:
    for key in (
        "STRIPE_SECRET_KEY",
        "STRIPE_TEST_SECRET_KEY",
        "STRIPE_LIVE_SECRET_KEY",
    ):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setattr(settings, "stripe_secret_key", "sk_test_value", raising=False)
    monkeypatch.setattr(settings, "stripe_test_secret_key", None, raising=False)
    monkeypatch.setattr(settings, "stripe_live_secret_key", None, raising=False)


async def test_checkout_verify_invalid_id(async_client):
    resp = await async_client.get("/api/checkout/verify", params={"session_id": "bad"})
    assert resp.status_code == 400


async def test_checkout_verify_not_found(async_client, monkeypatch):
    _set_stripe_env(monkeypatch)

    def fake_retrieve(session_id):
        raise stripe.error.InvalidRequestError(  # type: ignore[arg-type]
            "missing",
            param="id",
            code="resource_missing",
        )

    monkeypatch.setattr("stripe.checkout.Session.retrieve", fake_retrieve)

    resp = await async_client.get(
        "/api/checkout/verify", params={"session_id": "cs_missing"}
    )
    assert resp.status_code == 404


async def test_checkout_verify_success(async_client, monkeypatch):
    _set_stripe_env(monkeypatch)

    def fake_retrieve(session_id):
        return {
            "id": session_id,
            "mode": "payment",
            "status": "complete",
            "payment_status": "paid",
            "customer": {"id": "cus_test"},
            "metadata": {
                "checkout_type": "course",
                "course_slug": "tarot-basics",
                "order_id": "order-123",
            },
        }

    monkeypatch.setattr("stripe.checkout.Session.retrieve", fake_retrieve)

    resp = await async_client.get(
        "/api/checkout/verify", params={"session_id": "cs_test_123"}
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["ok"] is True
    assert payload["session_id"] == "cs_test_123"
    assert payload["success"] is True
    assert payload["status"] == "success"
    assert payload["checkout_type"] == "course"
    assert payload["course_slug"] == "tarot-basics"
    assert payload["order_id"] == "order-123"


async def test_checkout_verify_canceled(async_client, monkeypatch):
    _set_stripe_env(monkeypatch)

    def fake_retrieve(session_id):
        return {
            "id": session_id,
            "mode": "payment",
            "status": "expired",
            "payment_status": "unpaid",
            "metadata": {"checkout_type": "service"},
        }

    monkeypatch.setattr("stripe.checkout.Session.retrieve", fake_retrieve)

    resp = await async_client.get(
        "/api/checkout/verify", params={"session_id": "cs_test_987"}
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["success"] is False
    assert payload["status"] == "canceled"
