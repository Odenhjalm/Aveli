import json
import uuid

import pytest

from app import db, repositories
from app.config import settings
from app.repositories import courses as courses_repo

from .utils import register_user


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET onboarding_state = 'completed',
                       role_v2 = 'teacher',
                       role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await cur.execute(
                """
                INSERT INTO app.memberships (
                    membership_id,
                    user_id,
                    status,
                    effective_at,
                    expires_at,
                    source,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, 'active', now(), now() + interval '30 days', 'invite', now(), now())
                ON CONFLICT (user_id) DO UPDATE
                SET status = 'active',
                    effective_at = COALESCE(app.memberships.effective_at, now()),
                    expires_at = now() + interval '30 days',
                    source = 'invite',
                    updated_at = now()
                """,
                (str(uuid.uuid4()), user_id),
            )
            await conn.commit()


async def _cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.orders WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.memberships WHERE user_id = %s", (user_id,))
            await cur.execute(
                "DELETE FROM app.course_enrollments WHERE user_id = %s",
                (user_id,),
            )
            await cur.execute(
                "DELETE FROM app.stripe_customers WHERE user_id = %s",
                (user_id,),
            )
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _cleanup_course(course_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.course_enrollments WHERE course_id = %s",
                (course_id,),
            )
            await cur.execute("DELETE FROM app.orders WHERE course_id = %s", (course_id,))
            await cur.execute("DELETE FROM app.courses WHERE id = %s", (course_id,))
            await conn.commit()


async def _create_course(async_client, headers: dict[str, str], slug: str, price_amount_cents: int) -> str:
    response = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": f"Course {slug}",
            "slug": slug,
            "course_group_id": str(uuid.uuid4()),
            "step": "step1",
            "price_amount_cents": price_amount_cents,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
    )
    assert response.status_code == 200, response.text
    return str(response.json()["id"])


async def _login_user(async_client, email: str, password: str) -> dict[str, str]:
    login_resp = await async_client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, login_resp.text
    return {"Authorization": f"Bearer {login_resp.json()['access_token']}"}


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
    order = await repositories.create_order(
        user_id=str(user_id),
        service_id=None,
        course_id=None,
        amount_cents=9900,
        currency="sek",
        metadata={"checkout_type": "membership", "source": "purchase"},
        order_type="subscription",
        session_id=None,
        session_slot_id=None,
        stripe_subscription_id=None,
        stripe_customer_id="cus_123",
        connected_account_id=None,
    )

    created_event = {
        "id": "evt_sub_create",
        "type": "customer.subscription.created",
        "data": {
            "object": {
                "id": "sub_123",
                "customer": "cus_123",
                "status": "trialing",
                "metadata": {"user_id": str(user_id), "order_id": str(order["id"])},
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
        content=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert create_resp.status_code == 200, create_resp.text

    invoice_resp = await async_client.post(
        "/api/stripe/webhook",
        content=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert invoice_resp.status_code == 200

    membership = await repositories.get_membership(str(user_id))
    assert membership is not None
    assert membership["status"] == "active"
    assert membership["source"] == "purchase"
    refreshed_order = await repositories.get_order(str(order["id"]))
    assert refreshed_order is not None
    assert refreshed_order["stripe_subscription_id"] == "sub_123"


@pytest.mark.anyio("asyncio")
async def test_unified_webhook_processes_subscription_and_checkout(async_client, monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", "sk_test_value")
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = "sk_test_value"
    settings.stripe_test_secret_key = "sk_test_value"
    settings.stripe_test_webhook_secret = "whsec_test"
    settings.stripe_test_membership_price_monthly = "price_month_test"

    teacher_headers, teacher_id, teacher_email = await register_user(async_client)
    await _promote_to_teacher(str(teacher_id))
    teacher_headers = await _login_user(async_client, teacher_email, "Secret123!")
    student_headers, student_id, _ = await register_user(async_client)

    course_id = None
    captured_session: dict[str, object] = {}

    def fake_product_create(**kwargs):
        return {"id": f"prod_webhook_test_{uuid.uuid4().hex}"}

    def fake_price_create(**kwargs):
        return {"id": f"price_webhook_test_{uuid.uuid4().hex}"}

    def fake_customer_create(**kwargs):
        return {"id": "cus_canonical"}

    def fake_checkout_create(**kwargs):
        captured_session.update(kwargs)
        return {
            "id": "cs_canonical",
            "url": "https://stripe.test/cs_canonical",
            "payment_intent": "pi_canonical",
        }

    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_checkout_create)

    try:
        membership_order = await repositories.create_order(
            user_id=str(student_id),
            service_id=None,
            course_id=None,
            amount_cents=9900,
            currency="sek",
            metadata={"checkout_type": "membership", "source": "purchase"},
            order_type="subscription",
            session_id=None,
            session_slot_id=None,
            stripe_subscription_id=None,
            stripe_customer_id="cus_canonical",
            connected_account_id=None,
        )
        course_slug = f"integration-webhook-course-{uuid.uuid4().hex[:8]}"
        course_id = await _create_course(async_client, teacher_headers, course_slug, 1500)
        checkout_create_resp = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={"slug": course_slug},
        )
        assert checkout_create_resp.status_code == 201, checkout_create_resp.text
        checkout_payload = checkout_create_resp.json()
        assert checkout_payload["order_id"]

        events = [
            {
                "id": "evt_sub_create_canonical",
                "type": "customer.subscription.created",
                "data": {
                    "object": {
                        "id": "sub_canonical",
                        "customer": "cus_canonical",
                        "status": "active",
                        "metadata": {"user_id": str(student_id), "order_id": str(membership_order["id"])},
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
                "id": "evt_invoice_canonical",
                "type": "invoice.payment_succeeded",
                "data": {
                    "object": {
                        "id": "in_canonical",
                        "subscription": "sub_canonical",
                        "customer": "cus_canonical",
                        "payment_intent": "pi_invoice_canonical",
                        "lines": {
                            "data": [
                                {
                                    "price": {
                                        "id": "price_month_test",
                                        "recurring": {"interval": "month"},
                                    },
                                    "period": {"start": 3, "end": 4},
                                }
                            ]
                        },
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
                        "metadata": {"order_id": checkout_payload["order_id"]},
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
            content=json.dumps({}),
            headers={"stripe-signature": "sig"},
        )
        assert subscription_resp.status_code == 200, subscription_resp.text

        invoice_resp = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig"},
        )
        assert invoice_resp.status_code == 200, invoice_resp.text

        checkout_resp = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig"},
        )
        assert checkout_resp.status_code == 200, checkout_resp.text

        membership = await repositories.get_membership(str(student_id))
        assert membership is not None
        assert membership["status"] == "active"
        assert membership["source"] == "purchase"
        refreshed_order = await repositories.get_order(str(membership_order["id"]))
        assert refreshed_order is not None
        assert refreshed_order["stripe_subscription_id"] == "sub_canonical"

        assert captured_session.get("metadata", {}).get("order_id") == checkout_payload["order_id"]
        enrollment = await courses_repo.get_course_enrollment(
            str(student_id),
            course_id,
        )
        assert enrollment is not None
        assert enrollment["source"] == "purchase"
    finally:
        if course_id:
            await _cleanup_course(course_id)
        await _cleanup_user(str(teacher_id))
        await _cleanup_user(str(student_id))


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

    event = {
        "id": "evt_duplicate_subscription",
        "type": "customer.subscription.created",
        "data": {
            "object": {
                "id": "sub_duplicate",
                "customer": "cus_duplicate",
                "status": "active",
                "metadata": {"user_id": str(uuid.uuid4()), "order_id": str(uuid.uuid4())},
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

    inserted_event_ids: list[str] = []
    handled_event_ids: list[str] = []

    async def fake_insert_payment_event(event_id: str, payload: dict[str, object]) -> bool:
        inserted_event_ids.append(event_id)
        return len(inserted_event_ids) == 1

    async def fake_handle_event(event_payload: dict[str, object]) -> None:
        handled_event_ids.append(str(event_payload["id"]))

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)
    monkeypatch.setattr(
        "app.routes.stripe_webhooks.membership_support_repo.insert_payment_event",
        fake_insert_payment_event,
    )
    monkeypatch.setattr(
        "app.routes.stripe_webhooks.stripe_webhook_membership_service.handle_event",
        fake_handle_event,
    )

    first_response = await async_client.post(
        "/api/stripe/webhook",
        content=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert first_response.status_code == 200, first_response.text

    second_response = await async_client.post(
        "/api/stripe/webhook",
        content=json.dumps({}),
        headers={"stripe-signature": "sig"},
    )
    assert second_response.status_code == 200, second_response.text

    assert inserted_event_ids == [event["id"], event["id"]]
    assert handled_event_ids == [event["id"]]
