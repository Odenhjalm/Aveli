import json
import uuid

import pytest

from psycopg import errors

from app import db
from app.config import settings
from app.repositories import course_entitlements

pytestmark = pytest.mark.anyio("asyncio")


def _set_stripe_test_env(monkeypatch, *, secret: str = "sk_test_value") -> None:
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_TEST_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = secret
    settings.stripe_test_secret_key = None
    settings.stripe_live_secret_key = None


async def _create_course(slug: str, price_amount_cents: int, *, created_by: str | None) -> str:
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
                        is_published,
                        created_by
                    )
                    VALUES (%s, %s, false, %s, 'sek', true, %s)
                    RETURNING id
                    """,
                    (slug, f"Course {slug}", price_amount_cents, created_by),
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
                        is_published,
                        created_by
                    )
                    VALUES (%s, %s, false, %s, 'sek', true, %s)
                    RETURNING id
                    """,
                    (slug, f"Course {slug}", price_amount_cents, created_by),
                )
            row = await cur.fetchone()
            await conn.commit()
    return str(row[0])


async def _cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.orders WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.course_entitlements WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.stripe_customers WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _cleanup_course(course_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute("DELETE FROM app.course_bundle_courses WHERE course_id = %s", (course_id,))
            except errors.UndefinedTable:
                await conn.rollback()
            await cur.execute("DELETE FROM app.courses WHERE id = %s", (course_id,))
            await conn.commit()


async def _cleanup_bundle(bundle_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute("DELETE FROM app.course_bundles WHERE id = %s", (bundle_id,))
                await conn.commit()
            except errors.UndefinedTable:
                await conn.rollback()


async def _promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _bundles_table_ready() -> bool:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("select to_regclass('app.course_bundles') as tbl limit 1")
            row = await cur.fetchone()
    return bool(row and row[0])


async def _register_user(client, email: str, password: str, display_name: str):
    register_resp = await client.post(
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
    me_resp = await client.get("/auth/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    user_id = me_resp.json()["user_id"]
    return tokens["access_token"], tokens["refresh_token"], user_id


async def test_create_bundle_and_checkout_flow(async_client, monkeypatch):
    if not await _bundles_table_ready():
        pytest.skip("course_bundles table missing; run migrations")
    _set_stripe_test_env(monkeypatch)
    teacher_token, _, teacher_id = await _register_user(
        async_client, f"teacher_{uuid.uuid4().hex[:6]}@example.com", "Passw0rd!", "Teacher"
    )
    await _promote_to_teacher(teacher_id)
    student_token, _, student_id = await _register_user(
        async_client, f"student_{uuid.uuid4().hex[:6]}@example.com", "Passw0rd!", "Student"
    )

    slug_one = f"bundle-course-{uuid.uuid4().hex[:6]}"
    slug_two = f"bundle-course-{uuid.uuid4().hex[6:12]}"
    course_one = await _create_course(slug_one, 1500, created_by=str(teacher_id))
    course_two = await _create_course(slug_two, 1200, created_by=str(teacher_id))
    bundle_id = None

    captured_session: dict[str, object] = {}

    def fake_product_create(**kwargs):
        return {"id": "prod_bundle_test"}

    def fake_price_create(**kwargs):
        return {"id": "price_bundle_test"}

    def fake_customer_create(**kwargs):
        return {"id": "cus_bundle_test"}

    def fake_session_create(**kwargs):
        captured_session.update(kwargs)
        return {
            "id": "cs_bundle_test",
            "url": "https://stripe.test/cs_bundle_test",
            "payment_intent": "pi_bundle_test",
        }

    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)
    monkeypatch.setattr(settings, "checkout_success_url", "https://checkout.test/success")
    monkeypatch.setattr(settings, "checkout_cancel_url", "https://checkout.test/cancel")

    try:
        create_resp = await async_client.post(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
            json={
                "title": "Paket A",
                "description": "Bundle Description",
                "price_amount_cents": 2490,
                "currency": "sek",
                "course_ids": [course_one],
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        bundle = create_resp.json()
        bundle_id = bundle["id"]
        assert bundle["title"] == "Paket A"
        assert len(bundle["courses"]) == 1
        assert bundle.get("payment_link")

        attach_resp = await async_client.post(
            f"/api/teachers/course-bundles/{bundle_id}/courses",
            headers=_auth(teacher_token),
            json={"course_id": course_two, "position": 1},
        )
        assert attach_resp.status_code == 200, attach_resp.text
        assert len(attach_resp.json()["courses"]) == 2

        checkout_resp = await async_client.post(
            f"/api/course-bundles/{bundle_id}/checkout-session",
            headers=_auth(student_token),
        )
        assert checkout_resp.status_code == 201, checkout_resp.text
        payload = checkout_resp.json()
        assert payload["url"] == "https://stripe.test/cs_bundle_test"
        assert payload["order_id"]
        assert captured_session.get("locale") == "sv"
        metadata = captured_session.get("metadata") or {}
        assert metadata.get("bundle_id") == bundle_id
        assert metadata.get("checkout_type") == "course_bundle"

        def fake_construct_event(payload, sig_header, secret):
            body = json.loads(payload)
            return {"type": body.get("event_type"), "data": {"object": body.get("object", body)}}

        monkeypatch.setattr(settings, "stripe_webhook_secret", "whsec_test")
        monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

        webhook_payload = {
            "event_type": "checkout.session.completed",
            "object": {
                "id": "cs_bundle_test",
                "mode": "payment",
                "metadata": {"bundle_id": bundle_id, "user_id": str(student_id)},
                "customer": "cus_bundle_test",
                "payment_intent": "pi_bundle_test",
                "amount_total": 2490,
                "currency": "sek",
            },
        }
        webhook_resp = await async_client.post(
            "/webhooks/stripe",
            content=json.dumps(webhook_payload),
            headers={"stripe-signature": "sig_test"},
        )
        assert webhook_resp.status_code == 200, webhook_resp.text

        entitlements = await course_entitlements.list_entitlements_for_user(student_id)
        assert slug_one in entitlements
        assert slug_two in entitlements
    finally:
        if bundle_id:
            await _cleanup_bundle(bundle_id)
        await _cleanup_course(course_one)
        await _cleanup_course(course_two)
        await _cleanup_user(str(teacher_id))
        await _cleanup_user(str(student_id))
