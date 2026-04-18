import pytest

from app import repositories
from app.config import settings

from .utils import register_user

pytestmark = pytest.mark.anyio("asyncio")


def _set_stripe_test_env(monkeypatch, *, secret: str = "sk_test_value") -> None:
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_TEST_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    monkeypatch.setenv("STRIPE_SECRET_KEY", secret)
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", secret)
    settings.stripe_secret_key = secret
    settings.stripe_test_secret_key = secret


async def test_cancel_subscription_requires_membership(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    headers, user_id, _ = await register_user(async_client)

    resp = await async_client.post(
        "/api/billing/cancel-subscription-intent",
        headers=headers,
        json={"subscription_id": "sub_missing"},
    )
    assert resp.status_code == 404
    payload = resp.json()
    assert "ingen aktiv prenumeration" in payload["detail"].lower()


async def test_cancel_subscription_submits_intent_without_mutating_membership(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    headers, user_id, _ = await register_user(async_client)

    await repositories.upsert_membership_record(
        str(user_id),
        status="active",
        source="purchase",
    )
    await repositories.create_order(
        user_id=str(user_id),
        course_id=None,
        amount_cents=1000,
        currency="sek",
        metadata={"checkout_type": "membership", "source": "purchase"},
        order_type="subscription",
        stripe_subscription_id="sub_test",
        stripe_customer_id="cus_test",
    )

    captured_payload: dict[str, object] = {}

    def fake_modify(sub_id, **kwargs):
        captured_payload.update({"sub_id": sub_id, "kwargs": kwargs})
        return {
            "id": sub_id,
            "status": "canceled",
            "cancel_at_period_end": True,
            "current_period_end": 1735689600,
        }

    monkeypatch.setattr("stripe.Subscription.modify", fake_modify)

    resp = await async_client.post(
        "/api/billing/cancel-subscription-intent",
        headers=headers,
        json={"subscription_id": "sub_test"},
    )
    assert resp.status_code == 202, resp.text
    payload = resp.json()
    assert payload["ok"] is True
    assert payload["cancel_at_period_end"] is True
    assert captured_payload["sub_id"] == "sub_test"
    assert captured_payload["kwargs"]["cancel_at_period_end"] is True

    membership = await repositories.get_membership(str(user_id))
    assert membership is not None
    assert membership["status"] == "active"


async def test_cancel_subscription_rejects_mismatched_subscription_id(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    headers, user_id, _ = await register_user(async_client)

    await repositories.upsert_membership_record(
        str(user_id),
        status="active",
        source="purchase",
    )
    await repositories.create_order(
        user_id=str(user_id),
        course_id=None,
        amount_cents=1000,
        currency="sek",
        metadata={"checkout_type": "membership", "source": "purchase"},
        order_type="subscription",
        stripe_subscription_id="sub_real",
        stripe_customer_id="cus_test",
    )

    stripe_called = False

    def fake_modify(sub_id, **kwargs):
        nonlocal stripe_called
        stripe_called = True
        return {"id": sub_id}

    monkeypatch.setattr("stripe.Subscription.modify", fake_modify)

    resp = await async_client.post(
        "/api/billing/cancel-subscription-intent",
        headers=headers,
        json={"subscription_id": "sub_other_user"},
    )
    assert resp.status_code == 403, resp.text
    assert "matchar inte ditt konto" in resp.json()["detail"].lower()
    assert stripe_called is False
