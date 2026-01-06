import pytest
import stripe

from app.config import settings

pytestmark = pytest.mark.anyio("asyncio")


def set_stripe_env(monkeypatch):
    for key in ("STRIPE_SECRET_KEY", "STRIPE_TEST_SECRET_KEY", "STRIPE_LIVE_SECRET_KEY"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setattr(settings, "stripe_secret_key", "sk_test_value", raising=False)
    monkeypatch.setattr(settings, "stripe_test_secret_key", None, raising=False)
    monkeypatch.setattr(settings, "stripe_live_secret_key", None, raising=False)


async def test_session_status_invalid_id(async_client):
    resp = await async_client.get("/api/billing/session-status", params={"session_id": "bad"})
    assert resp.status_code == 400


async def test_session_status_not_found(async_client, monkeypatch):
    set_stripe_env(monkeypatch)

    def fake_retrieve(session_id, expand=None):
        raise stripe.error.InvalidRequestError(
            "missing", param="id", code="resource_missing"  # type: ignore[arg-type]
        )

    monkeypatch.setattr("stripe.checkout.Session.retrieve", fake_retrieve)

    resp = await async_client.get("/api/billing/session-status", params={"session_id": "cs_missing"})
    assert resp.status_code == 404


async def test_session_status_happy(async_client, monkeypatch):
    set_stripe_env(monkeypatch)

    def fake_retrieve(session_id, expand=None):
        return {
            "id": session_id,
            "mode": "subscription",
            "payment_status": "paid",
            "subscription": {"status": "active"},
            "customer": {"id": "cus_test"},
        }

    async def fake_get_membership_by_customer(customer_id):
        assert customer_id == "cus_test"
        return {"status": "active", "updated_at": "2026-01-06T00:00:00Z"}

    monkeypatch.setattr("stripe.checkout.Session.retrieve", fake_retrieve)
    monkeypatch.setattr("app.repositories.memberships.get_membership_by_stripe_reference", fake_get_membership_by_customer)

    resp = await async_client.get(
        "/api/billing/session-status", params={"session_id": "cs_test_123"}
    )
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["ok"] is True
    assert payload["session_id"] == "cs_test_123"
    assert payload["payment_status"] == "paid"
    assert payload["subscription_status"] == "active"
    assert payload["membership_status"] == "active"
    assert payload["poll_after_ms"] == 2000
