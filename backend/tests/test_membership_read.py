import pytest

from app import repositories

from .utils import register_user


@pytest.mark.anyio("asyncio")
async def test_membership_read_endpoint(async_client):
    headers, user_id, _ = await register_user(async_client)

    await repositories.upsert_membership_record(
        str(user_id),
        plan_interval="month",
        price_id="price_month_test",
        status="active",
    )

    resp = await async_client.get("/api/me/membership", headers=headers)
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["membership"]["plan_interval"] == "month"
    assert payload["membership"]["status"] == "active"


@pytest.mark.anyio("asyncio")
async def test_entitlements_incomplete_membership_is_not_active(async_client):
    headers, user_id, _ = await register_user(async_client)

    await repositories.upsert_membership_record(
        str(user_id),
        plan_interval="month",
        price_id="price_month_test",
        status="incomplete",
    )

    resp = await async_client.get("/api/me/entitlements", headers=headers)
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["membership"]["status"] == "incomplete"
    assert payload["membership"]["is_active"] is False
