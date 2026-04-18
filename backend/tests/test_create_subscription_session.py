from uuid import uuid4

import pytest

from app import repositories
from app.config import settings
from app.repositories import orders as orders_repo
from app.services import subscription_service

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
    fake_customer_id = f"cus_{str(user_id).replace('-', '')}"

    def fake_customer_create(**kwargs):
        return {"id": fake_customer_id}

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
    assert captured_session.get("customer") == fake_customer_id
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
    assert order["course_id"] is None
    assert order["bundle_id"] is None
    assert order["stripe_customer_id"] == fake_customer_id


async def test_create_order_validation_stops_before_sql(monkeypatch):
    def fail_connection():
        raise AssertionError("validation should stop before SQL")

    monkeypatch.setattr(orders_repo.pool, "connection", fail_connection)

    with pytest.raises(ValueError, match="subscription orders cannot target"):
        await orders_repo.create_order(
            user_id=uuid4(),
            course_id=uuid4(),
            bundle_id=None,
            amount_cents=9900,
            currency="sek",
            order_type="subscription",
        )


async def test_create_subscription_validation_error_returns_400(
    async_client,
    monkeypatch,
):
    headers, _, _ = await register_user(async_client)

    async def fail_checkout(user, interval):
        raise ValueError("subscription orders cannot target course or bundle")

    monkeypatch.setattr(
        subscription_service,
        "create_subscription_checkout",
        fail_checkout,
    )

    resp = await async_client.post(
        "/api/billing/create-subscription",
        headers=headers,
        json={"interval": "month"},
    )

    assert resp.status_code == 400, resp.text
    assert resp.json()["detail"] == "subscription orders cannot target course or bundle"


async def test_mark_order_paid_returns_v2_order_shape(async_client):
    _, user_id, _ = await register_user(async_client)
    fake_customer_id = f"cus_paid_{str(user_id).replace('-', '')}"
    order = await repositories.create_order(
        user_id=str(user_id),
        course_id=None,
        bundle_id=None,
        amount_cents=9900,
        currency="sek",
        metadata={"checkout_type": "membership", "source": "purchase"},
        order_type="subscription",
        stripe_customer_id=fake_customer_id,
        stripe_subscription_id=None,
    )

    updated = await repositories.mark_order_paid(
        order["id"],
        payment_intent="pi_paid_test",
        checkout_id="cs_paid_test",
        subscription_id="sub_paid_test",
        customer_id=fake_customer_id,
    )

    assert updated is not None
    assert "service_id" not in updated
    assert updated["status"] == "paid"
    assert updated["order_type"] == "subscription"
    assert updated["course_id"] is None
    assert updated["bundle_id"] is None
    assert updated["stripe_customer_id"] == fake_customer_id
