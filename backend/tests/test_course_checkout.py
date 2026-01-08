import json
import uuid

import pytest

from psycopg import errors

from app import db
from app.config import settings
from app.repositories import course_entitlements

from .utils import register_user

pytestmark = pytest.mark.anyio("asyncio")


def _set_stripe_test_env(monkeypatch, *, secret: str = "sk_test_value") -> None:
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_TEST_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = secret
    settings.stripe_test_secret_key = None
    settings.stripe_live_secret_key = None


async def _create_course(slug: str, price_amount_cents: int) -> str:
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
                        is_published
                    )
                    VALUES (%s, %s, false, %s, 'sek', true)
                    RETURNING id
                    """,
                    (slug, f"Course {slug}", price_amount_cents),
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
                    VALUES (%s, %s, false, %s, 'sek', true)
                    RETURNING id
                    """,
                    (slug, f"Course {slug}", price_amount_cents),
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


async def test_webhook_checkout_session_grants_entitlement(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    monkeypatch.setattr(settings, "stripe_webhook_secret", "whsec_test")
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
            "/webhooks/stripe",
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
    monkeypatch.setattr(settings, "stripe_webhook_secret", "whsec_test")
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
            "/webhooks/stripe",
            content=json.dumps(payload),
            headers={"stripe-signature": "sig_test"},
        )
        assert resp.status_code == 200, resp.text
        entitlements = await course_entitlements.list_entitlements_for_user(str(user_id))
        assert slug in entitlements
    finally:
        await _clear_entitlement(str(user_id), slug)
        await _cleanup_user(str(user_id))
