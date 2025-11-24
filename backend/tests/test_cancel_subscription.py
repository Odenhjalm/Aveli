import pytest

from app import repositories
from app.config import settings

from .utils import register_user

pytestmark = pytest.mark.anyio("asyncio")


async def test_cancel_subscription_requires_membership(async_client, monkeypatch):
    settings.stripe_secret_key = "sk_test_value"
    headers, user_id, _ = await register_user(async_client)

    resp = await async_client.post(
        "/api/billing/cancel-subscription",
        headers=headers,
        json={"subscription_id": "sub_missing"},
    )
    assert resp.status_code == 404
    payload = resp.json()
    assert "ingen aktiv prenumeration" in payload["detail"].lower()


async def test_cancel_subscription_marks_membership(async_client, monkeypatch):
    settings.stripe_secret_key = "sk_test_value"
    headers, user_id, _ = await register_user(async_client)

    await repositories.upsert_membership_record(
        str(user_id),
        plan_interval="month",
        price_id="price_test",
        status="active",
        stripe_customer_id="cus_test",
        stripe_subscription_id="sub_test",
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
        "/api/billing/cancel-subscription",
        headers=headers,
        json={"subscription_id": "sub_test"},
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["status"] == "canceled"
    assert payload["cancel_at_period_end"] is True
    assert captured_payload["sub_id"] == "sub_test"
    assert captured_payload["kwargs"]["cancel_at_period_end"] is True

    membership = await repositories.get_membership(str(user_id))
    assert membership is not None
    assert membership["status"] == "canceled"
