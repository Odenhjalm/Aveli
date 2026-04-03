import json
import uuid

import pytest

from app import db, repositories
from app.config import settings
from app.repositories import courses as courses_repo

from .utils import register_user


async def _create_course(slug: str, price_amount_cents: int) -> str:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.courses (
                    slug,
                    title,
                    course_group_id,
                    step,
                    price_amount_cents,
                    drip_enabled,
                    drip_interval_days,
                    is_published
                )
                VALUES (%s, %s, gen_random_uuid(), 'step1', %s, false, null, true)
                RETURNING id
                """,
                (slug, f"Course {slug}", price_amount_cents),
            )
            row = await cur.fetchone()
            await conn.commit()
    return str(row[0])


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

    _, user_id, _ = await register_user(async_client)

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


@pytest.mark.anyio("asyncio")
async def test_unified_webhook_processes_subscription_and_checkout(async_client, monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", "sk_test_value")
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = "sk_test_value"
    settings.stripe_test_secret_key = "sk_test_value"
    settings.stripe_test_webhook_secret = "whsec_test"

    _, user_id, _ = await register_user(async_client)
    course_slug = f"integration-webhook-course-{uuid.uuid4().hex[:8]}"
    course_id = await _create_course(course_slug, 1500)

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

    assert await courses_repo.is_enrolled(str(user_id), course_id) is True


@pytest.mark.anyio("asyncio")
async def test_subscription_webhook_is_idempotent(async_client, monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", "sk_test_value")
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = "sk_test_value"
    settings.stripe_test_secret_key = "sk_test_value"
    settings.stripe_test_webhook_billing_secret = "whsec_test"
    settings.stripe_test_webhook_secret = "whsec_test"
    settings.stripe_test_membership_price_monthly = "price_month_test"

    _, user_id, _ = await register_user(async_client)

    event = {
        "id": "evt_duplicate_subscription",
        "type": "customer.subscription.created",
        "data": {
            "object": {
                "id": "sub_duplicate",
                "customer": "cus_duplicate",
                "status": "active",
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

    def fake_construct_event(payload, sig_header, secret):
        assert sig_header == "sig"
        assert secret == "whsec_test"
        return event

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    first_response = await async_client.post(
        "/api/stripe/webhook",
        data=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert first_response.status_code == 200, first_response.text

    second_response = await async_client.post(
        "/api/stripe/webhook",
        data=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert second_response.status_code == 200, second_response.text

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT count(*)::int
                  FROM app.payment_events
                 WHERE event_id = %s
                """,
                (event["id"],),
            )
            row = await cur.fetchone()

    assert int(row[0]) == 1
