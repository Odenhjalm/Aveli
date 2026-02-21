import json
import uuid
from datetime import datetime, timezone

import pytest

from psycopg import errors

from app import db, repositories
from app.config import settings
from app.repositories import course_entitlements
from app.repositories import courses as courses_repo
from app.services import subscription_service

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


async def _create_course(
    slug: str,
    price_amount_cents: int,
    *,
    step_level: str = "step1",
    course_family: str | None = None,
    is_free_intro: bool = False,
) -> str:
    family_value = course_family or slug
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.courses (
                        slug,
                        title,
                        is_free_intro,
                        price_amount_cents,
                        currency,
                        step_level,
                        course_family,
                        is_published
                    )
                    VALUES (%s, %s, %s, %s, 'sek', %s, %s, true)
                    RETURNING id
                    """,
                    (
                        slug,
                        f"Course {slug}",
                        is_free_intro,
                        price_amount_cents,
                        step_level,
                        family_value,
                    ),
                )
            except errors.UndefinedColumn:
                await conn.rollback()
                await cur.execute(
                    """
                    INSERT INTO app.courses (
                        slug,
                        title,
                        is_free_intro,
                        price_cents,
                        currency,
                        is_published
                    )
                    VALUES (%s, %s, %s, %s, 'sek', true)
                    RETURNING id
                    """,
                    (slug, f"Course {slug}", is_free_intro, price_amount_cents),
                )
            row = await cur.fetchone()
            await conn.commit()
    return str(row[0])


async def _cleanup_course(course_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.courses WHERE id = %s", (course_id,))
            await conn.commit()


async def _cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.orders WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.course_entitlements WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.stripe_customers WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _clear_entitlement(user_id: str, slug: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.course_entitlements WHERE user_id = %s AND course_slug = %s",
                (user_id, slug),
            )
            await conn.commit()


async def _upsert_active_membership(user_id: str) -> None:
    await repositories.upsert_membership_record(
        user_id,
        plan_interval="month",
        price_id="price_monthly_intro",
        status="active",
        stripe_customer_id=f"cus_{uuid.uuid4().hex[:8]}",
        stripe_subscription_id=f"sub_{uuid.uuid4().hex[:8]}",
    )


async def _intro_usage_count(user_id: str, at: datetime | None = None) -> int:
    usage_time = at.astimezone(timezone.utc) if at else datetime.now(timezone.utc)
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT count
                FROM app.intro_usage
                WHERE user_id = %s
                  AND year = %s
                  AND month = %s
                """,
                (user_id, usage_time.year, usage_time.month),
            )
            row = await cur.fetchone()
    return int(row[0]) if row else 0


async def test_course_checkout_unknown_slug(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    headers, user_id, _ = await register_user(async_client)
    try:
        resp = await async_client.post(
            "/api/checkout/create",
            headers=headers,
            json={"type": "course", "slug": "missing-course"},
        )
        assert resp.status_code == 404
    finally:
        await _cleanup_user(str(user_id))


async def test_course_checkout_missing_price(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    slug = f"course-{uuid.uuid4().hex[:6]}"
    course_id = await _create_course(slug, price_amount_cents=0)
    headers, user_id, _ = await register_user(async_client)
    try:
        resp = await async_client.post(
            "/api/checkout/create",
            headers=headers,
            json={"type": "course", "slug": slug},
        )
        assert resp.status_code == 400
        assert "no Stripe price" in resp.text
    finally:
        await _cleanup_user(str(user_id))
        await _cleanup_course(course_id)


async def test_course_pricing_resolves_slug_variants(async_client):
    slug_base = f"pricing{uuid.uuid4().hex[:6]}"
    course_id = await _create_course(slug_base, price_amount_cents=2750)
    try:
        resp = await async_client.get(f"/api/courses/{slug_base}-random/pricing")
        assert resp.status_code == 200, resp.text
        payload = resp.json()
        assert payload["amount_cents"] == 2750
        assert payload["currency"] == "sek"
    finally:
        await _cleanup_course(course_id)


async def test_course_checkout_success(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    base_slug = f"premium{uuid.uuid4().hex[:6]}"
    course_id = await _create_course(base_slug, price_amount_cents=1500)
    headers, user_id, _ = await register_user(async_client)

    captured_session: dict[str, object] = {}

    def fake_product_create(**kwargs):
        return {"id": "prod_test"}

    def fake_price_create(**kwargs):
        return {"id": "price_test"}

    def fake_customer_create(**kwargs):
        return {"id": "cus_test"}

    def fake_session_create(**kwargs):
        captured_session.update(kwargs)
        return {"id": "cs_test", "url": "https://stripe.test/cs_test", "payment_intent": "pi_test"}

    monkeypatch.setattr(settings, "checkout_success_url", "https://checkout.test/success")
    monkeypatch.setattr(settings, "checkout_cancel_url", "https://checkout.test/cancel")
    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)

    try:
        resp = await async_client.post(
            "/api/checkout/create",
            headers=headers,
            json={"type": "course", "slug": f"{base_slug}-rand"},
        )
        assert resp.status_code == 201, resp.text
        payload = resp.json()
        assert payload["url"] == "https://stripe.test/cs_test"
        assert payload["order_id"]
        metadata = captured_session.get("metadata") or {}
        assert metadata.get("course_slug") == base_slug
        assert metadata.get("checkout_type") == "course"
        assert captured_session.get("success_url") == "https://checkout.test/success"
        assert captured_session.get("cancel_url") == "https://checkout.test/cancel"
    finally:
        await _cleanup_user(str(user_id))
        await _cleanup_course(course_id)


async def test_step2_checkout_requires_step1_ownership(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    family = f"family-{uuid.uuid4().hex[:8]}"
    step2_slug = f"step2-{uuid.uuid4().hex[:8]}"
    course_id = await _create_course(
        step2_slug,
        price_amount_cents=1500,
        step_level="step2",
        course_family=family,
    )
    headers, user_id, _ = await register_user(async_client)

    def unexpected_checkout(**kwargs):
        raise AssertionError("Stripe checkout should not be called when prerequisites fail")

    monkeypatch.setattr("stripe.checkout.Session.create", unexpected_checkout)

    try:
        resp = await async_client.post(
            "/api/checkout/create",
            headers=headers,
            json={"type": "course", "slug": step2_slug},
        )
        assert resp.status_code == 403, resp.text
        assert "step1" in resp.text.lower()
    finally:
        await _cleanup_user(str(user_id))
        await _cleanup_course(course_id)


async def test_webhook_checkout_session_grants_entitlement(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    monkeypatch.setattr(settings, "stripe_test_webhook_secret", "whsec_test")
    slug = f"web-{uuid.uuid4().hex[:6]}"
    headers, user_id, _ = await register_user(async_client)

    def fake_construct_event(payload, sig_header, secret):
        body = json.loads(payload)
        return {"type": body.get("event_type"), "data": {"object": body.get("object", body)}}

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    payload = {
        "event_type": "checkout.session.completed",
        "object": {
            "id": "cs_test",
            "mode": "payment",
            "metadata": {"course_slug": slug, "user_id": str(user_id)},
            "customer": "cus_test",
            "payment_intent": "pi_test",
            "amount_total": 1500,
            "currency": "sek",
        },
    }

    try:
        resp = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps(payload),
            headers={"stripe-signature": "sig_test"},
        )
        assert resp.status_code == 200, resp.text
        entitlements = await course_entitlements.list_entitlements_for_user(str(user_id))
        assert slug in entitlements
    finally:
        await _clear_entitlement(str(user_id), slug)
        await _cleanup_user(str(user_id))


async def test_webhook_payment_intent_grants_entitlement(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    monkeypatch.setattr(settings, "stripe_test_webhook_secret", "whsec_test")
    slug = f"intent-{uuid.uuid4().hex[:6]}"
    headers, user_id, _ = await register_user(async_client)

    def fake_construct_event(payload, sig_header, secret):
        body = json.loads(payload)
        return {"type": body.get("event_type"), "data": {"object": body.get("object", body)}}

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    payload = {
        "event_type": "payment_intent.succeeded",
        "object": {
            "id": "pi_test",
            "metadata": {"course_slug": slug, "user_id": str(user_id)},
            "customer": "cus_test",
        },
    }

    try:
        resp = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps(payload),
            headers={"stripe-signature": "sig_test"},
        )
        assert resp.status_code == 200, resp.text
        entitlements = await course_entitlements.list_entitlements_for_user(str(user_id))
        assert slug in entitlements
    finally:
        await _clear_entitlement(str(user_id), slug)
        await _cleanup_user(str(user_id))


async def test_refunded_step1_order_revokes_entitlement_and_enrollment(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    monkeypatch.setattr(settings, "stripe_test_webhook_secret", "whsec_test")
    slug = f"refund-step1-{uuid.uuid4().hex[:6]}"
    course_id = await _create_course(
        slug,
        price_amount_cents=1500,
        step_level="step1",
        course_family=f"family-{uuid.uuid4().hex[:6]}",
    )
    headers, user_id, _ = await register_user(async_client)

    order = await repositories.create_order(
        user_id=str(user_id),
        service_id=None,
        course_id=course_id,
        amount_cents=1500,
        currency="sek",
        order_type="one_off",
        metadata={"course_slug": slug},
        stripe_customer_id="cus_refund_step1",
        stripe_subscription_id=None,
        connected_account_id=None,
        session_id=None,
        session_slot_id=None,
    )
    await repositories.mark_order_paid(
        order["id"],
        payment_intent="pi_refund_step1",
        checkout_id="cs_refund_step1",
    )
    await course_entitlements.grant_course_entitlement(
        user_id=str(user_id),
        course_slug=slug,
        stripe_customer_id="cus_refund_step1",
        payment_intent_id="pi_refund_step1",
    )
    await courses_repo.ensure_course_enrollment(str(user_id), course_id, source="purchase")

    def fake_construct_event(payload, sig_header, secret):
        assert secret == "whsec_test"
        return {
            "id": "evt_charge_refunded_step1",
            "type": "charge.refunded",
            "data": {"object": {"id": "ch_refund_step1", "payment_intent": "pi_refund_step1"}},
        }

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    try:
        webhook_resp = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig_refund_step1"},
        )
        assert webhook_resp.status_code == 200, webhook_resp.text

        updated_order = await repositories.get_order(order["id"])
        assert updated_order is not None
        assert updated_order["status"] == "refunded"

        entitlements = await course_entitlements.list_entitlements_for_user(str(user_id))
        assert slug not in entitlements

        assert await courses_repo.is_enrolled(str(user_id), course_id) is False

        course_detail = await async_client.get(f"/courses/{course_id}", headers=headers)
        assert course_detail.status_code == 403, course_detail.text
    finally:
        await _cleanup_user(str(user_id))
        await _cleanup_course(course_id)


async def test_refunded_intro_order_decrements_intro_usage_once(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    monkeypatch.setattr(settings, "stripe_test_webhook_secret", "whsec_test")
    slug = f"refund-intro-{uuid.uuid4().hex[:6]}"
    course_id = await _create_course(
        slug,
        price_amount_cents=0,
        step_level="intro",
        course_family=f"family-{uuid.uuid4().hex[:6]}",
        is_free_intro=True,
    )
    headers, user_id, _ = await register_user(async_client)
    user_id_str = str(user_id)

    await _upsert_active_membership(user_id_str)

    enroll_resp = await async_client.post(f"/courses/{course_id}/enroll", headers=headers)
    assert enroll_resp.status_code == 200, enroll_resp.text
    assert await _intro_usage_count(user_id_str) == 1

    order = await repositories.create_order(
        user_id=user_id_str,
        service_id=None,
        course_id=course_id,
        amount_cents=1000,
        currency="sek",
        order_type="one_off",
        metadata={"course_slug": slug},
        stripe_customer_id="cus_refund_intro",
        stripe_subscription_id=None,
        connected_account_id=None,
        session_id=None,
        session_slot_id=None,
    )
    await repositories.mark_order_paid(
        order["id"],
        payment_intent="pi_refund_intro",
        checkout_id="cs_refund_intro",
    )

    def fake_construct_event(payload, sig_header, secret):
        assert secret == "whsec_test"
        return {
            "id": "evt_payment_intent_canceled_intro",
            "type": "payment_intent.canceled",
            "data": {"object": {"id": "pi_refund_intro"}},
        }

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    try:
        first_refund = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig_refund_intro"},
        )
        assert first_refund.status_code == 200, first_refund.text
        assert await _intro_usage_count(user_id_str) == 0

        second_refund = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig_refund_intro"},
        )
        assert second_refund.status_code == 200, second_refund.text
        assert await _intro_usage_count(user_id_str) == 0

        updated_order = await repositories.get_order(order["id"])
        assert updated_order is not None
        assert updated_order["status"] == "refunded"

        assert await courses_repo.is_enrolled(user_id_str, course_id) is False
    finally:
        await _cleanup_user(user_id_str)
        await _cleanup_course(course_id)


async def test_webhook_returns_500_when_subscription_processing_fails(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    monkeypatch.setattr(settings, "stripe_test_webhook_secret", "whsec_test")

    def fake_construct_event(payload, sig_header, secret):
        assert secret == "whsec_test"
        return {
            "id": "evt_subscription_fail",
            "type": "customer.subscription.updated",
            "data": {"object": {"id": "sub_test"}},
        }

    async def fail_process_event(event):
        raise RuntimeError("processing failed")

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)
    monkeypatch.setattr(subscription_service, "process_event", fail_process_event)

    resp = await async_client.post(
        "/api/stripe/webhook",
        content=json.dumps({}),
        headers={"stripe-signature": "sig_test"},
    )
    assert resp.status_code == 500, resp.text
    assert "webhook processing failed" in resp.json()["detail"].lower()
