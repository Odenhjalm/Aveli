import json

import pytest

from app import repositories
from app.config import settings
from app.repositories import course_entitlements

from .utils import register_user


@pytest.mark.anyio("asyncio")
async def test_webhook_upserts_membership(async_client, monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", "sk_test_value")
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = "sk_test_value"
    settings.stripe_test_secret_key = "sk_test_value"
    settings.stripe_test_webhook_billing_secret = "whsec_test"
    settings.stripe_test_webhook_secret = "whsec_test"
    settings.stripe_test_membership_price_monthly = "price_month_test"
    settings.stripe_test_membership_price_id_yearly = "price_year_test"

    headers, user_id, _ = await register_user(async_client)

    created_event = {
        "id": "evt_sub_create",
        "type": "customer.subscription.created",
        "data": {
            "object": {
                "id": "sub_123",
                "customer": "cus_123",
                "status": "trialing",
                "metadata": {"user_id": str(user_id)},
                "items": {
                    "data": [
                        {
                            "price": {
                                "id": settings.stripe_test_membership_price_monthly,
                                "recurring": {"interval": "month"},
                            }
                        }
                    ]
                },
                "current_period_start": 1,
                "current_period_end": 2,
            }
        },
    }

    invoice_event = {
        "id": "evt_invoice",
        "type": "invoice.payment_succeeded",
        "data": {
            "object": {
                "id": "in_123",
                "subscription": "sub_123",
                "customer": "cus_123",
                "lines": {
                    "data": [
                        {
                            "price": {
                                "id": settings.stripe_test_membership_price_monthly,
                                "recurring": {"interval": "month"},
                            },
                            "period": {"start": 3, "end": 4},
                        }
                    ]
                },
            }
        },
    }

    events = [created_event, invoice_event]

    def fake_construct_event(payload, sig_header, secret):
        assert secret == "whsec_test"
        assert sig_header == "sig"
        return events.pop(0)

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    create_resp = await async_client.post(
        "/api/stripe/webhook",
        data=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert create_resp.status_code == 200, create_resp.text

    invoice_resp = await async_client.post(
        "/api/stripe/webhook",
        data=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert invoice_resp.status_code == 200

    membership = await repositories.get_membership(str(user_id))
    assert membership is not None
    assert membership["status"] == "active"
    assert membership["stripe_subscription_id"] == "sub_123"

    me_membership = await async_client.get("/api/me/membership", headers=headers)
    assert me_membership.status_code == 200
    body = me_membership.json()
    assert body["membership"]["status"] == "active"


@pytest.mark.anyio("asyncio")
async def test_unified_webhook_processes_subscription_and_checkout(async_client, monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", "sk_test_value")
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = "sk_test_value"
    settings.stripe_test_secret_key = "sk_test_value"
    settings.stripe_test_webhook_secret = "whsec_test"

    headers, user_id, _ = await register_user(async_client)
    course_slug = "integration-webhook-course"

    events = [
        {
            "id": "evt_sub_create_canonical",
            "type": "customer.subscription.created",
            "data": {
                "object": {
                    "id": "sub_canonical",
                    "customer": "cus_canonical",
                    "status": "active",
                    "metadata": {"user_id": str(user_id)},
                    "items": {
                        "data": [
                            {
                                "price": {
                                    "id": "price_month_test",
                                    "recurring": {"interval": "month"},
                                }
                            }
                        ]
                    },
                    "current_period_start": 1,
                    "current_period_end": 2,
                }
            },
        },
        {
            "id": "evt_checkout_complete_canonical",
            "type": "checkout.session.completed",
            "data": {
                "object": {
                    "id": "cs_canonical",
                    "mode": "payment",
                    "metadata": {
                        "user_id": str(user_id),
                        "course_slug": course_slug,
                    },
                    "customer": "cus_canonical",
                    "payment_intent": "pi_canonical",
                    "amount_total": 1500,
                    "currency": "sek",
                }
            },
        },
    ]

    def fake_construct_event(payload, sig_header, secret):
        assert sig_header == "sig"
        assert secret == "whsec_test"
        return events.pop(0)

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    subscription_resp = await async_client.post(
        "/api/stripe/webhook",
        data=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert subscription_resp.status_code == 200, subscription_resp.text

    checkout_resp = await async_client.post(
        "/api/stripe/webhook",
        data=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert checkout_resp.status_code == 200, checkout_resp.text

    membership = await repositories.get_membership(str(user_id))
    assert membership is not None
    assert membership["status"] == "active"
    assert membership["stripe_subscription_id"] == "sub_canonical"

    entitlements = await course_entitlements.list_entitlements_for_user(str(user_id))
    assert course_slug in entitlements
