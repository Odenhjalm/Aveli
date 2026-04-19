import json
import uuid

import pytest

from app import db, repositories
from app.config import settings
from app.repositories import courses as courses_repo
from app.repositories import payments as payments_repo
from app.services import checkout_service

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


async def _promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET onboarding_state = 'completed',

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


async def _create_course(
    async_client,
    headers: dict[str, str],
    slug: str,
    price_amount_cents: int | None,
    *,
    group_position: int = 1,
    checkout_ready: bool = False,
) -> str:
    response = await async_client.post(
        "/studio/courses",
        headers=headers,
        json={
            "title": f"Course {slug}",
            "slug": slug,
            "course_group_id": str(uuid.uuid4()),
            "group_position": group_position,
            "price_amount_cents": price_amount_cents,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
    )
    assert response.status_code == 200, response.text
    course_id = str(response.json()["id"])
    if checkout_ready:
        await _mark_course_checkout_ready(course_id)
    return course_id


async def _mark_course_checkout_ready(course_id: str) -> None:
    product_id = f"prod_checkout_ready_{uuid.uuid4().hex}"
    price_id = f"price_checkout_ready_{uuid.uuid4().hex}"
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.courses
                   SET visibility = 'public'::app.course_visibility,
                       content_ready = true,
                       stripe_product_id = %s,
                       active_stripe_price_id = %s,
                       sellable = true
                 WHERE id = %s
                """,
                (product_id, price_id, course_id),
            )
            await conn.commit()


def _install_course_stripe_fakes(
    monkeypatch,
    *,
    checkout_id: str,
    payment_intent: str,
) -> dict[str, object]:
    captured_session: dict[str, object] = {}

    def fail_stripe_entity_create(**kwargs):
        raise AssertionError("course create/update must not create Stripe entities")

    def fake_customer_create(**kwargs):
        return {"id": f"cus_checkout_test_{uuid.uuid4().hex}"}

    def fake_session_create(**kwargs):
        captured_session.update(kwargs)
        return {
            "id": checkout_id,
            "url": f"https://stripe.test/{checkout_id}",
            "payment_intent": payment_intent,
        }

    monkeypatch.setattr("stripe.Product.create", fail_stripe_entity_create)
    monkeypatch.setattr("stripe.Price.create", fail_stripe_entity_create)
    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)
    monkeypatch.setattr(settings, "checkout_success_url", "https://checkout.test/success")
    monkeypatch.setattr(settings, "checkout_cancel_url", "https://checkout.test/cancel")
    return captured_session


async def _register_teacher(async_client) -> tuple[dict[str, str], str]:
    _, user_id, email = await register_user(async_client)
    await _promote_to_teacher(str(user_id))
    login_resp = await async_client.post(
        "/auth/login",
        json={"email": email, "password": "Secret123!"},
    )
    assert login_resp.status_code == 200, login_resp.text
    return {"Authorization": f"Bearer {login_resp.json()['access_token']}"}, str(user_id)


async def test_course_checkout_unknown_slug(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    headers, user_id, _ = await register_user(async_client)
    try:
        response = await async_client.post(
            "/api/checkout/create",
            headers=headers,
            json={"slug": "missing-course"},
        )
        assert response.status_code == 404
        assert response.json()["detail"] == "Kursen hittades inte"
    finally:
        await _cleanup_user(str(user_id))


async def test_course_checkout_rejects_non_canonical_body(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    headers, user_id, _ = await register_user(async_client)
    try:
        extra_keys = await async_client.post(
            "/api/checkout/create",
            headers=headers,
            json={"type": "course", "slug": "demo"},
        )
        assert extra_keys.status_code == 400, extra_keys.text
        assert extra_keys.json()["detail"] == (
            "Kursbetalning accepterar bara fältet slug som text"
        )

        empty_slug = await async_client.post(
            "/api/checkout/create",
            headers=headers,
            json={"slug": ""},
        )
        assert empty_slug.status_code == 400, empty_slug.text
        assert empty_slug.json()["detail"] == "Kursbetalning kräver en ifylld slug"
    finally:
        await _cleanup_user(str(user_id))


async def test_course_pricing_requires_exact_slug(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    _install_course_stripe_fakes(
        monkeypatch,
        checkout_id="cs_pricing_contract",
        payment_intent="pi_pricing_contract",
    )

    teacher_headers, teacher_id = await _register_teacher(async_client)
    course_id = None
    try:
        slug = f"pricing-{uuid.uuid4().hex[:8]}"
        course_id = await _create_course(
            async_client,
            teacher_headers,
            slug,
            2750,
            group_position=1,
        )

        exact = await async_client.get(f"/api/courses/{slug}/pricing")
        assert exact.status_code == 200, exact.text
        assert exact.json() == {"amount_cents": 2750, "currency": "sek"}

        variant = await async_client.get(f"/api/courses/{slug}-random/pricing")
        assert variant.status_code == 404, variant.text
    finally:
        if course_id:
            await _cleanup_course(course_id)
        await _cleanup_user(teacher_id)


async def test_course_checkout_success(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    captured_session = _install_course_stripe_fakes(
        monkeypatch,
        checkout_id="cs_checkout_success",
        payment_intent="pi_checkout_success",
    )

    teacher_headers, teacher_id = await _register_teacher(async_client)
    student_headers, student_id, _ = await register_user(async_client)
    course_id = None
    try:
        slug = f"premium-{uuid.uuid4().hex[:8]}"
        course_id = await _create_course(
            async_client,
            teacher_headers,
            slug,
            1500,
            group_position=1,
            checkout_ready=True,
        )

        response = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={"slug": slug},
        )
        assert response.status_code == 201, response.text
        payload = response.json()
        assert payload["url"] == "https://stripe.test/cs_checkout_success"
        assert payload["session_id"] == "cs_checkout_success"
        assert payload["order_id"]

        metadata = captured_session.get("metadata") or {}
        assert metadata["course_slug"] == slug
        assert metadata["checkout_type"] == "course"
        assert metadata["order_id"] == payload["order_id"]
        assert captured_session["success_url"] == "https://checkout.test/success"
        assert captured_session["cancel_url"] == "https://checkout.test/cancel"
        assert captured_session["locale"] == "sv"
        order = await repositories.get_order(payload["order_id"])
        assert order is not None
        assert order["status"] == "pending"
        assert await repositories.get_membership(str(student_id)) is None
    finally:
        if course_id:
            await _cleanup_course(course_id)
        await _cleanup_user(teacher_id)
        await _cleanup_user(str(student_id))


async def test_step2_course_checkout_uses_canonical_sellable_flow(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    _install_course_stripe_fakes(
        monkeypatch,
        checkout_id="cs_step2_checkout",
        payment_intent="pi_step2_checkout",
    )

    teacher_headers, teacher_id = await _register_teacher(async_client)
    student_headers, student_id, _ = await register_user(async_client)
    course_id = None
    try:
        slug = f"step2-{uuid.uuid4().hex[:8]}"
        course_id = await _create_course(
            async_client,
            teacher_headers,
            slug,
            1900,
            group_position=2,
            checkout_ready=True,
        )

        response = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={"slug": slug},
        )
        assert response.status_code == 201, response.text
        assert response.json()["order_id"]
    finally:
        if course_id:
            await _cleanup_course(course_id)
        await _cleanup_user(teacher_id)
        await _cleanup_user(str(student_id))


async def test_webhook_checkout_session_grants_entitlement(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    settings.stripe_test_webhook_secret = "whsec_test"
    _install_course_stripe_fakes(
        monkeypatch,
        checkout_id="cs_checkout_webhook",
        payment_intent="pi_checkout_webhook",
    )

    teacher_headers, teacher_id = await _register_teacher(async_client)
    student_headers, student_id, _ = await register_user(async_client)
    course_id = None
    try:
        slug = f"checkout-webhook-{uuid.uuid4().hex[:8]}"
        course_id = await _create_course(
            async_client,
            teacher_headers,
            slug,
            1500,
            group_position=1,
            checkout_ready=True,
        )

        checkout_response = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={"slug": slug},
        )
        assert checkout_response.status_code == 201, checkout_response.text
        checkout_payload = checkout_response.json()

        def fake_construct_event(payload, sig_header, secret):
            assert sig_header == "sig_test"
            assert secret == "whsec_test"
            body = json.loads(payload)
            return {"type": body["event_type"], "data": {"object": body["object"]}}

        monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

        webhook_response = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps(
                {
                    "event_type": "checkout.session.completed",
                    "object": {
                        "id": "cs_checkout_webhook",
                        "mode": "payment",
                        "metadata": {"order_id": checkout_payload["order_id"]},
                        "customer": "cus_checkout_webhook",
                        "payment_intent": "pi_checkout_webhook",
                        "amount_total": 1500,
                        "currency": "sek",
                    },
                }
            ),
            headers={"stripe-signature": "sig_test"},
        )
        assert webhook_response.status_code == 200, webhook_response.text

        order = await repositories.get_order(checkout_payload["order_id"])
        assert order is not None
        assert order["status"] == "paid"
        assert order["stripe_payment_intent"] == "pi_checkout_webhook"
        payment = await payments_repo.get_latest_payment_for_order(
            checkout_payload["order_id"],
            status="paid",
        )
        assert payment is not None
        assert payment["provider"] == "stripe"
        assert payment["provider_reference"] == "pi_checkout_webhook"
        assert await repositories.get_membership(str(student_id)) is None

        enrollment = await courses_repo.get_course_enrollment(
            str(student_id),
            course_id,
        )
        assert enrollment is not None
        assert enrollment["source"] == "purchase"
    finally:
        if course_id:
            await _cleanup_course(course_id)
        await _cleanup_user(teacher_id)
        await _cleanup_user(str(student_id))


async def test_payment_intent_webhook_does_not_settle_checkout_backed_purchase(
    async_client,
    monkeypatch,
):
    _set_stripe_test_env(monkeypatch)
    settings.stripe_test_webhook_secret = "whsec_test"
    _install_course_stripe_fakes(
        monkeypatch,
        checkout_id="cs_checkout_guard",
        payment_intent="pi_checkout_guard",
    )

    teacher_headers, teacher_id = await _register_teacher(async_client)
    student_headers, student_id, _ = await register_user(async_client)
    course_id = None
    try:
        slug = f"checkout-guard-{uuid.uuid4().hex[:8]}"
        course_id = await _create_course(
            async_client,
            teacher_headers,
            slug,
            1500,
            group_position=1,
            checkout_ready=True,
        )

        checkout_response = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={"slug": slug},
        )
        assert checkout_response.status_code == 201, checkout_response.text
        checkout_payload = checkout_response.json()

        def fake_construct_event(payload, sig_header, secret):
            assert sig_header == "sig_test"
            assert secret == "whsec_test"
            return {
                "type": "payment_intent.succeeded",
                "data": {
                    "object": {
                        "id": "pi_checkout_guard",
                        "metadata": {"order_id": checkout_payload["order_id"]},
                    }
                },
            }

        monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

        webhook_response = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig_test"},
        )
        assert webhook_response.status_code == 200, webhook_response.text

        order = await repositories.get_order(checkout_payload["order_id"])
        assert order is not None
        assert order["status"] == "pending"

        assert (
            await courses_repo.get_course_enrollment(str(student_id), course_id)
            is None
        )
    finally:
        if course_id:
            await _cleanup_course(course_id)
        await _cleanup_user(teacher_id)
        await _cleanup_user(str(student_id))


async def test_refunded_paid_course_order_revokes_enrollment(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    settings.stripe_test_webhook_secret = "whsec_test"
    _install_course_stripe_fakes(
        monkeypatch,
        checkout_id="cs_refund_checkout",
        payment_intent="pi_refund_checkout",
    )

    teacher_headers, teacher_id = await _register_teacher(async_client)
    student_headers, student_id, _ = await register_user(async_client)
    course_id = None
    try:
        slug = f"refund-course-{uuid.uuid4().hex[:8]}"
        course_id = await _create_course(
            async_client,
            teacher_headers,
            slug,
            1500,
            group_position=1,
            checkout_ready=True,
        )

        checkout_response = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={"slug": slug},
        )
        assert checkout_response.status_code == 201, checkout_response.text
        checkout_payload = checkout_response.json()

        events = [
            {
                "id": f"evt_checkout_refund_purchase_{uuid.uuid4().hex}",
                "type": "checkout.session.completed",
                "data": {
                    "object": {
                        "id": "cs_refund_checkout",
                        "mode": "payment",
                        "metadata": {"order_id": checkout_payload["order_id"]},
                        "customer": "cus_refund_checkout",
                        "payment_intent": "pi_refund_checkout",
                        "amount_total": 1500,
                        "currency": "sek",
                    }
                },
            },
            {
                "id": f"evt_checkout_refund_charge_{uuid.uuid4().hex}",
                "type": "charge.refunded",
                "data": {
                    "object": {
                        "id": "ch_refund_checkout",
                        "payment_intent": "pi_refund_checkout",
                    }
                },
            },
        ]

        def fake_construct_event(payload, sig_header, secret):
            assert sig_header == "sig_test"
            assert secret == "whsec_test"
            return events.pop(0)

        monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

        purchase_response = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig_test"},
        )
        assert purchase_response.status_code == 200, purchase_response.text

        before_refund = await courses_repo.get_course_enrollment(
            str(student_id),
            course_id,
        )
        assert before_refund is not None
        assert before_refund["source"] == "purchase"

        captured_refund: dict[str, object] = {}

        def fake_refund_create(**kwargs):
            captured_refund.update(kwargs)
            return {"id": "re_refund_checkout"}

        monkeypatch.setattr("stripe.Refund.create", fake_refund_create)

        resolution = await checkout_service.apply_valid_one_off_withdrawal(
            {"id": str(student_id)},
            order_id=checkout_payload["order_id"],
        )
        assert resolution["ok"] is True
        assert resolution["resolution_kind"] == "withdrawal"
        assert resolution["payment_intent_id"] == "pi_refund_checkout"
        assert captured_refund["payment_intent"] == "pi_refund_checkout"

        assert (
            await courses_repo.get_course_enrollment(str(student_id), course_id)
            is None
        )

        refund_response = await async_client.post(
            "/api/stripe/webhook",
            content=json.dumps({}),
            headers={"stripe-signature": "sig_test"},
        )
        assert refund_response.status_code == 200, refund_response.text

        order = await repositories.get_order(checkout_payload["order_id"])
        assert order is not None
        assert order["status"] == "refunded"

        assert (
            await courses_repo.get_course_enrollment(str(student_id), course_id)
            is None
        )
    finally:
        if course_id:
            await _cleanup_course(course_id)
        await _cleanup_user(teacher_id)
        await _cleanup_user(str(student_id))


async def test_webhook_returns_500_when_subscription_processing_fails(async_client, monkeypatch):
    _set_stripe_test_env(monkeypatch)
    settings.stripe_test_webhook_secret = "whsec_test"

    def fake_construct_event(payload, sig_header, secret):
        assert secret == "whsec_test"
        return {
            "id": f"evt_subscription_fail_{uuid.uuid4().hex}",
            "type": "customer.subscription.updated",
            "data": {"object": {"id": "sub_test"}},
        }

    async def fail_process_event(event):
        raise RuntimeError("processing failed")

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)
    monkeypatch.setattr(
        "app.routes.stripe_webhooks.stripe_webhook_membership_service.handle_event",
        fail_process_event,
    )

    response = await async_client.post(
        "/api/stripe/webhook",
        content=json.dumps({}),
        headers={"stripe-signature": "sig_test"},
    )
    assert response.status_code == 500, response.text
    assert response.json()["detail"] == "Webhook-bearbetningen misslyckades"
