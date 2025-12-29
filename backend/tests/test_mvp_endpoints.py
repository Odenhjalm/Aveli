import json
import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import settings
from app.mvp.main import app as mvp_app


@pytest.mark.anyio("asyncio")
async def test_mvp_health_endpoint():
    transport = ASGITransport(app=mvp_app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        resp = await client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


@pytest.mark.anyio("asyncio")
async def test_checkout_session_sets_custom_ui_mode(async_client, monkeypatch):
    settings.stripe_secret_key = "sk_test_dummy"
    settings.stripe_webhook_secret = "whsec_dummy"
    settings.stripe_price_monthly = "price_monthly_test"

    email = f"mvp_{uuid.uuid4().hex[:6]}@aveli.local"
    password = "Secret123!"

    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "MVP"},
    )
    assert register_resp.status_code == 201
    token = register_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    captured_kwargs = {}

    def fake_checkout_create(**kwargs):
        captured_kwargs.update(kwargs)
        return {"id": "cs_test", "url": "https://stripe.test/cs_test", "payment_intent": "pi_test"}

    def fake_construct_event(payload, sig_header, secret):
        body = json.loads(payload)
        return {"type": body.get("event_type", "checkout.session.completed"), "data": {"object": body}}

    def fake_price_retrieve(price_id):
        return {"id": price_id, "unit_amount": 13000, "currency": "sek"}

    monkeypatch.setattr("stripe.checkout.Session.create", fake_checkout_create)
    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)
    monkeypatch.setattr("stripe.Price.retrieve", fake_price_retrieve)
    monkeypatch.setattr("stripe.Customer.create", lambda **_: {"id": "cus_123"})

    session_resp = await async_client.post(
        "/api/checkout/create",
        headers=headers,
        json={"type": "subscription", "interval": "month"},
    )
    assert session_resp.status_code == 201, session_resp.text
    assert captured_kwargs.get("ui_mode") == (settings.stripe_checkout_ui_mode or "custom")
