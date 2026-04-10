import json
import uuid

import pytest

from app.config import settings
from app import db


def _set_stripe_test_env(
    monkeypatch,
    *,
    secret: str = "sk_test_dummy",
    webhook: str = "whsec_dummy",
) -> None:
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_TEST_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    monkeypatch.setenv("STRIPE_SECRET_KEY", secret)
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", secret)
    settings.stripe_secret_key = secret
    settings.stripe_test_secret_key = secret
    settings.stripe_webhook_secret = webhook
    settings.stripe_test_webhook_secret = webhook


@pytest.mark.anyio("asyncio")
async def test_backend_api_smoke(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)

    email = f"smoke_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Secret123!"

    health_resp = await async_client.get("/healthz")
    assert health_resp.status_code == 200, health_resp.text
    assert health_resp.json()["surface"] == "canonical-runtime"

    ready_resp = await async_client.get("/readyz")
    assert ready_resp.status_code == 200, ready_resp.text

    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": "Smoke Tester",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    assert "access_token" in tokens and "refresh_token" in tokens

    auth_headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    me_resp = await async_client.get("/profiles/me", headers=auth_headers)
    assert me_resp.status_code == 200
    assert me_resp.json()["email"] == email

    refresh_resp = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refresh_resp.status_code == 200
    new_tokens = refresh_resp.json()
    assert new_tokens["access_token"]

    onboarding_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_headers,
    )
    assert onboarding_resp.status_code == 200, onboarding_resp.text
    assert onboarding_resp.json() == {
        "status": "completed",
        "onboarding_state": "completed",
        "token_refresh_required": True,
    }

    refreshed_me = await async_client.get(
        "/profiles/me",
        headers={"Authorization": f"Bearer {new_tokens['access_token']}"},
    )
    assert refreshed_me.status_code == 200, refreshed_me.text
    assert refreshed_me.json()["email"] == email

    public_courses_resp = await async_client.get("/courses")
    assert public_courses_resp.status_code == 200, public_courses_resp.text
    assert "items" in public_courses_resp.json()


@pytest.mark.anyio("asyncio")
async def test_course_purchase_enrolls_student(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)

    async def _register_user(email: str, display_name: str, password: str):
        register_resp = await async_client.post(
            "/auth/register",
            json={
                "email": email,
                "password": password,
                "display_name": display_name,
            },
        )
        assert register_resp.status_code == 201, register_resp.text
        tokens = register_resp.json()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        profile_resp = await async_client.get("/profiles/me", headers=headers)
        assert profile_resp.status_code == 200, profile_resp.text
        return tokens, headers, profile_resp.json()["user_id"]

    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@wisdom.dev"
    student_email = f"student_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Passw0rd!"

    _, teacher_headers, teacher_id = await _register_user(
        teacher_email, "Teacher", password
    )
    _, student_headers, student_id = await _register_user(
        student_email, "Student", password
    )

    captured_session: dict[str, object] = {}

    def fake_product_create(**_):
        return {"id": f"prod_test_{uuid.uuid4().hex}"}

    def fake_price_create(**_):
        return {"id": f"price_test_{uuid.uuid4().hex}"}

    def fake_customer_create(**_):
        return {"id": "cus_test"}

    def fake_checkout_create(**kwargs):
        captured_session.update(kwargs)
        return {
            "id": "cs_test_course",
            "url": "https://stripe.test/cs_test_course",
            "payment_intent": "pi_test_course",
        }

    def fake_construct_event(payload, sig_header, secret):
        body = json.loads(payload)
        return {
            "type": body.get("event_type", "checkout.session.completed"),
            "data": {"object": body},
        }

    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_checkout_create)
    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    try:
        async with db.pool.connection() as conn:  # type: ignore
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    UPDATE app.auth_subjects
                       SET role_v2 = 'teacher',
                           role = 'teacher'
                     WHERE user_id = %s
                    """,
                    (teacher_id,),
                )
                await conn.commit()

        slug = f"premium-{uuid.uuid4().hex[:6]}"
        course_resp = await async_client.post(
            "/studio/courses",
            headers=teacher_headers,
            json={
                "title": "Premium Course",
                "slug": slug,
                "course_group_id": str(uuid.uuid4()),
                "step": "step1",
                "price_amount_cents": 12900,
                "drip_enabled": False,
                "drip_interval_days": None,
            },
        )
        assert course_resp.status_code == 200, course_resp.text
        course_id = course_resp.json()["id"]

        checkout_resp = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={"slug": slug},
        )
        assert checkout_resp.status_code == 201, checkout_resp.text
        checkout_payload = checkout_resp.json()
        order_id = checkout_payload["order_id"]
        assert checkout_payload["url"].startswith("https://stripe.test")

        webhook_payload = {
            "event_type": "checkout.session.completed",
            "metadata": {"order_id": order_id},
            "payment_intent": "pi_test_course",
            "amount_total": 12900,
            "currency": "sek",
            "customer": "cus_test",
        }
        webhook_resp = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps(webhook_payload),
            headers={"stripe-signature": "sig_course"},
        )
        assert webhook_resp.status_code == 200, webhook_resp.text
        assert captured_session.get("metadata", {}).get("order_id") == order_id

        enrollment_resp = await async_client.get(
            f"/courses/{course_id}/enrollment",
            headers=student_headers,
        )
        assert enrollment_resp.status_code == 200
        assert enrollment_resp.json()["enrollment"] is not None

    finally:
        async with db.pool.connection() as conn:  # type: ignore
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute("DELETE FROM auth.users WHERE id = %s", (teacher_id,))
                await cur.execute("DELETE FROM auth.users WHERE id = %s", (student_id,))
                await conn.commit()
