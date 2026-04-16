import json
import uuid

import pytest

from psycopg import errors

from app import db, repositories
from app.config import settings
from app.repositories import courses as courses_repo
from app.repositories import payments as payments_repo

pytestmark = pytest.mark.anyio("asyncio")


def _set_stripe_test_env(monkeypatch, *, secret: str = "sk_test_value") -> None:
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_TEST_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    monkeypatch.setenv("STRIPE_SECRET_KEY", secret)
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", secret)
    settings.stripe_secret_key = secret
    settings.stripe_test_secret_key = secret


async def _create_course(client, token: str, slug: str, price_amount_cents: int) -> str:
    response = await client.post(
        "/studio/courses",
        headers=_auth(token),
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


async def _cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.orders WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.memberships WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.course_enrollments WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.stripe_customers WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _cleanup_course(course_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.course_enrollments WHERE course_id = %s",
                (course_id,),
            )
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
                await cur.execute(
                    "DELETE FROM app.course_bundle_courses WHERE bundle_id = %s",
                    (bundle_id,),
                )
                await cur.execute("DELETE FROM app.course_bundles WHERE id = %s", (bundle_id,))
                await conn.commit()
            except errors.UndefinedTable:
                await conn.rollback()


async def _promote_to_teacher(user_id: str):
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
                VALUES (%s, %s, 'active', now(), now() + interval '30 days', 'purchase', now(), now())
                ON CONFLICT (user_id) DO UPDATE
                SET status = 'active',
                    effective_at = COALESCE(app.memberships.effective_at, now()),
                    expires_at = now() + interval '30 days',
                    source = 'purchase',
                    updated_at = now()
                """,
                (str(uuid.uuid4()), user_id),
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


async def _register_user(client, email: str, password: str, _display_name: str):
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me_resp = await client.get("/profiles/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    user_id = me_resp.json()["user_id"]
    return tokens["access_token"], tokens["refresh_token"], user_id


async def _login_user(client, email: str, password: str) -> str:
    login_resp = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, login_resp.text
    return login_resp.json()["access_token"]


async def test_create_bundle_and_checkout_flow(async_client, monkeypatch):
    if not await _bundles_table_ready():
        pytest.skip("course_bundles table missing; run migrations")
    _set_stripe_test_env(monkeypatch)
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@example.com"
    teacher_token, _, teacher_id = await _register_user(
        async_client, teacher_email, "Passw0rd!", "Teacher"
    )
    await _promote_to_teacher(teacher_id)
    teacher_token = await _login_user(async_client, teacher_email, "Passw0rd!")
    student_token, _, student_id = await _register_user(
        async_client, f"student_{uuid.uuid4().hex[:6]}@example.com", "Passw0rd!", "Student"
    )

    slug_one = f"bundle-course-{uuid.uuid4().hex[:6]}"
    slug_two = f"bundle-course-{uuid.uuid4().hex[6:12]}"
    course_one = None
    course_two = None
    bundle_id = None

    captured_session: dict[str, object] = {}

    def fake_product_create(**kwargs):
        return {"id": f"prod_bundle_test_{uuid.uuid4().hex}"}

    def fake_price_create(**kwargs):
        return {"id": f"price_bundle_test_{uuid.uuid4().hex}"}

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
        course_one = await _create_course(async_client, teacher_token, slug_one, 1500)
        course_two = await _create_course(async_client, teacher_token, slug_two, 1200)

        create_resp = await async_client.post(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
            json={
                "title": "Paket A",
                "description": "Bundle Description",
                "price_amount_cents": 2490,
                "course_ids": [course_one],
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        bundle = create_resp.json()
        bundle_id = bundle["id"]
        assert bundle["title"] == "Paket A"
        assert bundle["price_amount_cents"] == 2490
        assert len(bundle["courses"]) == 1

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
        assert payload["session_id"] == "cs_bundle_test"
        assert payload["order_id"]
        assert captured_session.get("locale") == "sv"
        metadata = captured_session.get("metadata") or {}
        assert metadata.get("bundle_id") == bundle_id
        assert metadata.get("checkout_type") == "course_bundle"
        assert metadata.get("order_id") == payload["order_id"]

        def fake_construct_event(payload, sig_header, secret):
            body = json.loads(payload)
            return {"type": body.get("event_type"), "data": {"object": body.get("object", body)}}

        monkeypatch.setattr(settings, "stripe_test_webhook_secret", "whsec_test")
        monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

        webhook_payload = {
            "event_type": "checkout.session.completed",
            "object": {
                "id": "cs_bundle_test",
                "mode": "payment",
                "metadata": {"order_id": payload["order_id"]},
                "customer": "cus_bundle_test",
                "payment_intent": "pi_bundle_test",
                "amount_total": 2490,
                "currency": "sek",
            },
        }
        webhook_resp = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps(webhook_payload),
            headers={"stripe-signature": "sig_test"},
        )
        assert webhook_resp.status_code == 200, webhook_resp.text

        order = await repositories.get_order(payload["order_id"])
        assert order is not None
        assert order["status"] == "paid"
        assert order["order_type"] == "bundle"
        assert order["stripe_payment_intent"] == "pi_bundle_test"
        payment = await payments_repo.get_latest_payment_for_order(
            payload["order_id"],
            status="paid",
        )
        assert payment is not None
        assert payment["provider_reference"] == "pi_bundle_test"
        assert await repositories.get_membership(str(student_id)) is None

        enrollment_one = await courses_repo.get_course_enrollment(
            str(student_id),
            course_one,
        )
        enrollment_two = await courses_repo.get_course_enrollment(
            str(student_id),
            course_two,
        )
        assert enrollment_one is not None
        assert enrollment_two is not None
        assert enrollment_one["source"] == "purchase"
        assert enrollment_two["source"] == "purchase"
    finally:
        if bundle_id:
            await _cleanup_bundle(bundle_id)
        if course_one:
            await _cleanup_course(course_one)
        if course_two:
            await _cleanup_course(course_two)
        await _cleanup_user(str(teacher_id))
        await _cleanup_user(str(student_id))
