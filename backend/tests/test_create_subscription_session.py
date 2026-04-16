import pytest

from app import repositories
from app.config import settings

from .utils import register_user


pytestmark = pytest.mark.anyio("asyncio")


async def test_create_subscription_session(async_client, monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", "sk_test_value")
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = "sk_test_value"
    settings.stripe_test_secret_key = "sk_test_value"
    settings.stripe_test_membership_product_id = "prod_test"
    settings.stripe_test_membership_price_monthly = "price_month_test"
    settings.stripe_test_membership_price_id_yearly = "price_year_test"

    headers, user_id, _ = await register_user(async_client)

    def fake_customer_create(**kwargs):
        return {"id": "cus_test"}

    captured_session: dict[str, object] = {}

    def fake_session_create(**kwargs):
        captured_session.update(kwargs)
        return {"id": "cs_test", "client_secret": "cs_test_secret"}

    def fake_price_retrieve(price_id):
        return {
            "id": price_id,
            "unit_amount": 9900,
            "currency": "sek",
            "product": settings.stripe_test_membership_product_id,
            "livemode": False,
        }

    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)
    monkeypatch.setattr("stripe.Price.retrieve", fake_price_retrieve)

    resp = await async_client.post(
        "/api/billing/create-subscription",
        headers=headers,
        json={"interval": "month"},
    )
    assert resp.status_code == 201, resp.text
    payload = resp.json()
    assert set(payload) == {"client_secret", "session_id", "order_id"}
    assert payload["client_secret"] == "cs_test_secret"
    assert payload["session_id"] == "cs_test"
    assert payload["order_id"]
    assert captured_session.get("mode") == "subscription"
    assert captured_session.get("ui_mode") == "embedded"
    assert "success_url" not in captured_session
    assert "cancel_url" not in captured_session
    assert captured_session.get("return_url") == (
        "http://localhost:3000/checkout/return?session_id={CHECKOUT_SESSION_ID}"
    )
    assert captured_session.get("line_items")[0]["price"] == "price_month_test"
    assert captured_session.get("metadata")["checkout_type"] == "membership"
    assert captured_session.get("metadata")["source"] == "purchase"
    assert captured_session.get("metadata")["order_id"] == payload["order_id"]
    assert captured_session.get("payment_method_collection") == "always"
    subscription_data = captured_session.get("subscription_data")
    assert subscription_data["trial_period_days"] == 14
    assert subscription_data["trial_settings"] == {
        "end_behavior": {"missing_payment_method": "cancel"}
    }

    membership = await repositories.get_membership(str(user_id))
    assert membership is None

    order = await repositories.get_order(payload["order_id"])
    assert order is not None
    assert order["status"] == "pending"
    assert order["order_type"] == "subscription"
