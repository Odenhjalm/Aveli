import pytest

from psycopg import errors

from app import db
from app import repositories
from app.config import settings

from .utils import register_user


@pytest.mark.anyio("asyncio")
async def test_create_subscription_session(async_client, monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_value")
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", "sk_test_value")
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    settings.stripe_secret_key = "sk_test_value"
    settings.stripe_test_secret_key = "sk_test_value"
    settings.stripe_test_membership_product_id = "prod_test"
    settings.stripe_test_membership_price_monthly = "price_month_test"
    settings.stripe_test_membership_price_id_yearly = "price_year_test"

    headers, user_id, _ = await register_user(async_client)

    def fake_customer_create(**kwargs):
        return {"id": "cus_test"}

    captured_session: dict[str, object] = {}

    def fake_session_create(**kwargs):
        captured_session.update(kwargs)
        return {"id": "cs_test", "url": "https://checkout.stripe.com/cs_test"}

    def fake_price_retrieve(price_id):
        return {
            "id": price_id,
            "unit_amount": 9900,
            "currency": "sek",
            "product": settings.stripe_test_membership_product_id,
            "livemode": False,
        }

    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)
    monkeypatch.setattr("stripe.Price.retrieve", fake_price_retrieve)

    resp = await async_client.post(
        "/api/checkout/create",
        headers=headers,
        json={"type": "subscription", "interval": "month"},
    )
    assert resp.status_code == 201, resp.text
    payload = resp.json()
    assert payload["url"] == "https://checkout.stripe.com/cs_test"
    assert captured_session.get("line_items")[0]["price"] == "price_month_test"
    assert captured_session.get("ui_mode") is None

    membership = await repositories.get_membership(str(user_id))
    assert membership is not None
    assert membership["plan_interval"] == "month"
    assert membership["status"] == "incomplete"

    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    SELECT command_type, status, stripe_checkout_session_id
                    FROM app.payment_commands
                    WHERE user_id = %s
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                    (str(user_id),),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return
            row = await cur.fetchone()

    assert row is not None
    assert row[0] == "membership_start"
    assert row[1] == "session_created"
    assert row[2] == "cs_test"
