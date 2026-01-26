import json
import uuid

import pytest

from app.config import settings
from app import db
from app.auth import hash_password
from app.repositories import auth as auth_repo
from app import repositories


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
    # Configure external integrations for deterministic behaviour
    _set_stripe_test_env(monkeypatch)
    settings.livekit_api_key = "lk_test_key"
    settings.livekit_api_secret = "lk_test_secret"
    settings.livekit_ws_url = "wss://livekit.example.com"

    email = f"smoke_{uuid.uuid4().hex[:6]}@wisdom.dev"
    password = "Secret123!"

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

    me_resp = await async_client.get("/auth/me", headers=auth_headers)
    assert me_resp.status_code == 200
    assert me_resp.json()["email"] == email

    refresh_resp = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refresh_resp.status_code == 200
    new_tokens = refresh_resp.json()
    assert new_tokens["access_token"]

    services_resp = await async_client.get("/services?status=active", headers=auth_headers)
    assert services_resp.status_code == 200
    services_payload = services_resp.json()
    # In a clean Supabase project the services list may be empty; just assert shape.
    assert "items" in services_payload
    if not services_payload["items"]:
        return
    first_service = services_payload["items"][0]
    assert all(
        isinstance(key, str)
        and key == key.lower()
        and not any(char.isupper() for char in key)
        for key in first_service.keys()
    ), first_service
    service_id = first_service["id"]

    order_resp = await async_client.post(
        "/orders",
        headers=auth_headers,
        json={"service_id": service_id},
    )
    assert order_resp.status_code == 201
    order_payload = order_resp.json()["order"]
    assert all(
        isinstance(key, str)
        and key == key.lower()
        and not any(char.isupper() for char in key)
        for key in order_payload.keys()
    ), order_payload
    order_id = order_payload["id"]

    def fake_construct_event(payload, sig_header, secret):
        body = json.loads(payload)
        return {
            "type": body.get("event_type", "checkout.session.completed"),
            "data": {"object": body},
        }

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)

    webhook_payload = {
        "event_type": "checkout.session.completed",
        "metadata": {"order_id": order_id},
        "payment_intent": "pi_test_smoke",
        "amount_total": order_payload["amount_cents"],
        "currency": order_payload["currency"],
    }
    webhook_resp = await async_client.post(
        "/webhooks/stripe",
        content=json.dumps(webhook_payload),
        headers={"stripe-signature": "signature"},
    )
    assert webhook_resp.status_code == 200

    order_after_webhook = await async_client.get(f"/orders/{order_id}", headers=auth_headers)
    assert order_after_webhook.status_code == 200
    assert order_after_webhook.json()["order"]["status"] == "paid"

    orders_list_resp = await async_client.get(
        "/orders",
        headers=auth_headers,
    )
    assert orders_list_resp.status_code == 200
    orders_payload = orders_list_resp.json()
    assert any(item["id"] == order_id for item in orders_payload["items"])

    feed_resp = await async_client.get("/feed", headers=auth_headers)
    assert feed_resp.status_code == 200
    assert isinstance(feed_resp.json()["items"], list)

    student_email = "student@wisdom.dev"
    student_password = "password123"
    hashed_student_password = hash_password(student_password)
    existing_student = await auth_repo.get_user_by_email(student_email)
    student_user_id = str(existing_student["id"]) if existing_student else None
    if not existing_student:
        try:
            created = await auth_repo.create_user(
                email=student_email,
                hashed_password=hashed_student_password,
                display_name="Student",
            )
            student_user_id = str(created["user"]["id"])
        except auth_repo.UniqueViolationError:
            async with db.pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    await cur.execute(
                        "UPDATE auth.users SET encrypted_password = %s WHERE email = %s",
                        (hashed_student_password, student_email),
                    )
                    await cur.execute(
                        """
                        INSERT INTO app.profiles (
                            user_id,
                            email,
                            display_name,
                            role,
                            role_v2,
                            is_admin,
                            created_at,
                            updated_at
                        )
                        SELECT id, email, %s, 'student', 'user', false, NOW(), NOW()
                        FROM auth.users WHERE email = %s
                        ON CONFLICT (user_id) DO NOTHING
                        """,
                        ("Student", student_email),
                    )
                    await conn.commit()
            refreshed = await auth_repo.get_user_by_email(student_email)
            student_user_id = str(refreshed["id"]) if refreshed else None
    else:
        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "UPDATE auth.users SET encrypted_password = %s WHERE email = %s",
                    (hashed_student_password, student_email),
                )
                await conn.commit()
    if not student_user_id:
        pytest.skip("student user missing; cannot validate SFU token")

    seminar = await repositories.create_seminar(
        host_id=student_user_id,
        title="QA Smoke Seminar",
        description="auto-seeded for smoke test",
        scheduled_at=None,
        duration_minutes=30,
    )
    seminar_id = str(seminar["id"])
    session = await repositories.create_seminar_session(
        seminar_id=seminar_id,
        status="live",
        scheduled_at=None,
        livekit_room=f"seminar-{seminar_id}",
        livekit_sid=None,
        metadata={"qa_smoke": True},
    )
    seminar_id = str(session["seminar_id"])

    student_login = await async_client.post(
        "/auth/login",
        json={"email": "student@wisdom.dev", "password": "password123"},
    )
    assert student_login.status_code == 200
    student_token = student_login.json()["access_token"]
    seminar_resp = await async_client.post(
        "/sfu/token",
        headers={"Authorization": f"Bearer {student_token}"},
        json={"seminar_id": seminar_id},
    )
    assert seminar_resp.status_code == 200
    assert seminar_resp.json()["ws_url"] == settings.livekit_ws_url


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

    try:
        async with db.pool.connection() as conn:  # type: ignore
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "UPDATE app.profiles SET role_v2 = 'teacher' WHERE user_id = %s",
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
                "description": "Paid course",
                "is_free_intro": False,
                "is_published": True,
                "price_amount_cents": 12900,
            },
        )
        assert course_resp.status_code == 200, course_resp.text
        course_id = course_resp.json()["id"]

        captured_session: dict[str, object] = {}

        def fake_product_create(**_):
            return {"id": "prod_test"}

        def fake_price_create(**_):
            return {"id": "price_test"}

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

        checkout_resp = await async_client.post(
            "/api/checkout/create",
            headers=student_headers,
            json={
                "type": "course",
                "slug": slug,
            },
        )
        assert checkout_resp.status_code == 201, checkout_resp.text
        checkout_payload = checkout_resp.json()
        order_id = checkout_payload["order_id"]
        assert checkout_payload["url"].startswith("https://stripe.test")

        webhook_payload = {
            "event_type": "checkout.session.completed",
            "metadata": {
                "order_id": order_id,
                "course_slug": slug,
                "user_id": str(student_id),
            },
            "payment_intent": "pi_test_course",
            "amount_total": 12900,
            "currency": "sek",
            "customer": "cus_test",
        }
        webhook_resp = await async_client.post(
            "/webhooks/stripe",
            content=json.dumps(webhook_payload),
            headers={"stripe-signature": "sig_course"},
        )
        assert webhook_resp.status_code == 200, webhook_resp.text

        order_after = await async_client.get(
            f"/orders/{order_id}", headers=student_headers
        )
        assert order_after.status_code == 200
        assert order_after.json()["order"]["status"] == "paid"

        enrollment_resp = await async_client.get(
            f"/courses/{course_id}/enrollment",
            headers=student_headers,
        )
        assert enrollment_resp.status_code == 200
        assert enrollment_resp.json()["enrolled"] is True

    finally:
        async with db.pool.connection() as conn:  # type: ignore
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute("DELETE FROM auth.users WHERE id = %s", (teacher_id,))
                await cur.execute("DELETE FROM auth.users WHERE id = %s", (student_id,))
                await conn.commit()
