from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

import pytest

from app import db, repositories
from app.repositories import referrals as referrals_repo
from app.services import membership_expiry_warnings
from app.services.email_service import EmailDeliveryResult
from app.utils.membership_status import is_membership_row_active

pytestmark = pytest.mark.anyio("asyncio")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_user(
    client,
    *,
    email: str,
    password: str,
    display_name: str,
    referral_code: str | None = None,
) -> tuple[str, str]:
    payload = {
        "email": email,
        "password": password,
        "display_name": display_name,
    }

    register_resp = await client.post("/auth/register", json=payload)
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    if referral_code:
        redeem_resp = await client.post(
            "/referrals/redeem",
            headers=auth_header(tokens["access_token"]),
            json={"code": referral_code},
        )
        assert redeem_resp.status_code == 200, redeem_resp.text
        assert redeem_resp.json() == {"status": "redeemed"}
    me_resp = await client.get("/profiles/me", headers=auth_header(tokens["access_token"]))
    assert me_resp.status_code == 200, me_resp.text
    return tokens["access_token"], str(me_resp.json()["user_id"])


async def promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET role_v2 = 'teacher',
                       role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def update_referral_email(referral_id: str, email: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.referral_codes
                   SET email = %s
                 WHERE id = %s
                """,
                (email.lower(), referral_id),
            )
            await conn.commit()


async def fetch_billing_log_count(*, membership_id: str) -> int:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT count(*)::int
                  FROM app.billing_logs
                 WHERE step = 'membership_expiry_warning_sent'
                   AND info->>'membership_id' = %s
                """,
                (membership_id,),
            )
            row = await cur.fetchone()
    return int(row[0] if row else 0)


async def test_referral_signup_grants_membership_without_stripe(async_client, monkeypatch):
    sent_messages: list[tuple[str, str]] = []

    async def fake_send_email(*, to_email: str, subject: str, text_body: str, html_body=None):
        sent_messages.append((to_email, text_body))
        return EmailDeliveryResult(mode="sent")

    monkeypatch.setattr("app.services.email_service.send_email", fake_send_email)

    password = "Passw0rd!"
    teacher_id = None
    invited_user_id = None
    try:
        teacher_token, teacher_id = await register_user(
            async_client,
            email=f"teacher_referral_{uuid.uuid4().hex[:8]}@example.com",
            password=password,
            display_name="Teacher",
        )
        await promote_to_teacher(teacher_id)

        invited_email = f"invitee_{uuid.uuid4().hex[:8]}@example.com"
        create_resp = await async_client.post(
            "/studio/referrals/create",
            headers=auth_header(teacher_token),
            json={"email": invited_email, "free_days": 30},
        )
        assert create_resp.status_code == 201, create_resp.text
        payload = create_resp.json()
        referral = payload["referral"]
        assert payload["email_delivery"] == "sent"
        assert sent_messages and sent_messages[0][0] == invited_email

        _, invited_user_id = await register_user(
            async_client,
            email=invited_email,
            password=password,
            display_name="Referral User",
            referral_code=referral["code"],
        )

        membership = await repositories.get_membership(invited_user_id)
        assert membership is not None
        assert membership["status"] == "active"
        assert membership["price_id"] == "referral_grant"
        assert membership["plan_interval"] == "invite"
        assert membership["stripe_customer_id"] is None
        assert membership["stripe_subscription_id"] is None
        assert membership["end_date"] is not None

        redeemed_referral = await referrals_repo.get_referral_by_code(referral["code"])
        assert redeemed_referral is not None
        assert str(redeemed_referral["redeemed_by_user_id"]) == invited_user_id
        assert redeemed_referral["redeemed_at"] is not None
    finally:
        if invited_user_id:
            await cleanup_user(invited_user_id)
        if teacher_id:
            await cleanup_user(teacher_id)


async def test_membership_expiry_logic_requires_future_end_date(async_client):
    password = "Passw0rd!"
    user_id = None
    try:
        token, user_id = await register_user(
            async_client,
            email=f"expiry_logic_{uuid.uuid4().hex[:8]}@example.com",
            password=password,
            display_name="Expiry Logic",
        )

        await repositories.upsert_membership_record(
            user_id,
            plan_interval="invite",
            price_id="referral_grant",
            status="active",
            start_date=datetime.now(timezone.utc) - timedelta(days=2),
            end_date=datetime.now(timezone.utc) - timedelta(minutes=1),
        )

        expired_membership = await repositories.get_membership(user_id)
        assert expired_membership is not None
        assert is_membership_row_active(expired_membership) is False

        await repositories.upsert_membership_record(
            user_id,
            plan_interval="invite",
            price_id="referral_grant",
            status="trialing",
            start_date=datetime.now(timezone.utc) - timedelta(days=1),
            end_date=datetime.now(timezone.utc) + timedelta(days=2),
        )

        active_membership = await repositories.get_membership(user_id)
        assert active_membership is not None
        assert is_membership_row_active(active_membership) is True
        assert active_membership["status"] == "trialing"
    finally:
        if user_id:
            await cleanup_user(user_id)


async def test_referral_code_is_single_use(async_client, monkeypatch):
    async def fake_send_email(*, to_email: str, subject: str, text_body: str, html_body=None):
        return EmailDeliveryResult(mode="sent")

    monkeypatch.setattr("app.services.email_service.send_email", fake_send_email)

    password = "Passw0rd!"
    teacher_id = None
    first_user_id = None
    second_user_id = None
    try:
        teacher_token, teacher_id = await register_user(
            async_client,
            email=f"teacher_single_{uuid.uuid4().hex[:8]}@example.com",
            password=password,
            display_name="Teacher",
        )
        await promote_to_teacher(teacher_id)

        first_email = f"single_use_first_{uuid.uuid4().hex[:8]}@example.com"
        create_resp = await async_client.post(
            "/studio/referrals/create",
            headers=auth_header(teacher_token),
            json={"email": first_email, "free_days": 14},
        )
        assert create_resp.status_code == 201, create_resp.text
        referral = create_resp.json()["referral"]

        _, first_user_id = await register_user(
            async_client,
            email=first_email,
            password=password,
            display_name="First User",
            referral_code=referral["code"],
        )

        second_email = f"single_use_second_{uuid.uuid4().hex[:8]}@example.com"
        await update_referral_email(referral["id"], second_email)

        second_token, second_user_id = await register_user(
            async_client,
            email=second_email,
            password=password,
            display_name="Second User",
        )
        second_resp = await async_client.post(
            "/referrals/redeem",
            headers=auth_header(second_token),
            json={"code": referral["code"]},
        )
        assert second_resp.status_code == 400, second_resp.text
        assert second_resp.json() == {"detail": "invalid_referral_code"}
    finally:
        if second_user_id:
            await cleanup_user(second_user_id)
        if first_user_id:
            await cleanup_user(first_user_id)
        if teacher_id:
            await cleanup_user(teacher_id)


async def test_referral_membership_expires_correctly(async_client, monkeypatch):
    async def fake_send_email(*, to_email: str, subject: str, text_body: str, html_body=None):
        return EmailDeliveryResult(mode="sent")

    monkeypatch.setattr("app.services.email_service.send_email", fake_send_email)

    password = "Passw0rd!"
    teacher_id = None
    invited_user_id = None
    try:
        teacher_token, teacher_id = await register_user(
            async_client,
            email=f"teacher_duration_{uuid.uuid4().hex[:8]}@example.com",
            password=password,
            display_name="Teacher",
        )
        await promote_to_teacher(teacher_id)

        invited_email = f"duration_{uuid.uuid4().hex[:8]}@example.com"
        create_resp = await async_client.post(
            "/studio/referrals/create",
            headers=auth_header(teacher_token),
            json={"email": invited_email, "free_days": 7},
        )
        assert create_resp.status_code == 201, create_resp.text
        referral_code = create_resp.json()["referral"]["code"]

        _, invited_user_id = await register_user(
            async_client,
            email=invited_email,
            password=password,
            display_name="Duration User",
            referral_code=referral_code,
        )

        membership = await repositories.get_membership(invited_user_id)
        assert membership is not None
        start_date = membership["start_date"]
        end_date = membership["end_date"]
        assert start_date is not None
        assert end_date is not None

        expected_seconds = 7 * 24 * 60 * 60
        actual_seconds = int((end_date - start_date).total_seconds())
        assert abs(actual_seconds - expected_seconds) <= 5
    finally:
        if invited_user_id:
            await cleanup_user(invited_user_id)
        if teacher_id:
            await cleanup_user(teacher_id)


async def test_membership_expiry_warning_job_sends_once(async_client, monkeypatch):
    sent_to: list[str] = []

    async def fake_send_email(*, to_email: str, subject: str, text_body: str, html_body=None):
        sent_to.append(to_email)
        return EmailDeliveryResult(mode="sent")

    monkeypatch.setattr("app.services.email_service.send_email", fake_send_email)

    password = "Passw0rd!"
    user_id = None
    email = f"warning_{uuid.uuid4().hex[:8]}@example.com"
    try:
        _, user_id = await register_user(
            async_client,
            email=email,
            password=password,
            display_name="Warning User",
        )

        now = datetime.now(timezone.utc)
        membership = await repositories.upsert_membership_record(
            user_id,
            plan_interval="invite",
            price_id="referral_grant",
            status="active",
            start_date=now - timedelta(days=1),
            end_date=now + timedelta(days=7, hours=12),
        )

        first_run = await membership_expiry_warnings.run_once(now=now)
        second_run = await membership_expiry_warnings.run_once(now=now)

        assert first_run == 1
        assert second_run == 0
        assert sent_to == [email]
        assert await fetch_billing_log_count(membership_id=str(membership["membership_id"])) == 1
    finally:
        if user_id:
            await cleanup_user(user_id)
