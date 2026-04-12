from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import AsyncMock

import pytest

from app.services import membership_grant_service, referral_service

pytestmark = pytest.mark.anyio("asyncio")


async def test_redeem_referral_routes_membership_grant_through_canonical_service(monkeypatch):
    effective_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    expires_at = datetime(2026, 2, 1, tzinfo=timezone.utc)

    redeem_mock = AsyncMock(
        return_value={
            "id": "ref_1",
            "code": "REFCODE1",
            "teacher_id": "teacher_1",
            "effective_at": effective_at,
            "expires_at": expires_at,
        }
    )
    grant_mock = AsyncMock(return_value={"membership_id": "membership_1"})

    monkeypatch.setattr(referral_service.referrals_repo, "redeem_referral_code", redeem_mock)
    monkeypatch.setattr(
        referral_service.membership_grant_service,
        "grant_non_purchase_membership",
        grant_mock,
    )

    await referral_service.redeem_referral(
        code="REFCODE1",
        user_id="user_1",
        email="user@example.com",
    )

    redeem_mock.assert_awaited_once_with(
        code="REFCODE1",
        user_id="user_1",
        email="user@example.com",
    )
    grant_mock.assert_awaited_once_with(
        user_id="user_1",
        source="invite",
        effective_at=effective_at,
        expires_at=expires_at,
        audit_step="referral_membership_grant_applied",
        audit_info={
            "referral_id": "ref_1",
            "referral_code": "REFCODE1",
            "teacher_id": "teacher_1",
        },
    )


async def test_grant_non_purchase_membership_writes_once_and_logs_once(monkeypatch):
    effective_at = datetime(2026, 3, 1, tzinfo=timezone.utc)
    expires_at = datetime(2026, 4, 1, tzinfo=timezone.utc)
    membership_row = {
        "membership_id": "membership_1",
        "user_id": "user_1",
        "status": "active",
        "effective_at": effective_at,
        "expires_at": expires_at,
        "canceled_at": None,
        "ended_at": None,
        "source": "invite",
        "created_at": effective_at,
        "updated_at": effective_at,
    }

    upsert_mock = AsyncMock(return_value=membership_row)
    log_mock = AsyncMock()
    sync_mock = AsyncMock()

    monkeypatch.setattr(
        membership_grant_service.memberships_repo,
        "upsert_membership_record",
        upsert_mock,
    )
    monkeypatch.setattr(
        membership_grant_service.membership_support_repo,
        "insert_billing_log",
        log_mock,
    )
    monkeypatch.setattr(membership_grant_service, "sync_onboarding_state", sync_mock)

    result = await membership_grant_service.grant_non_purchase_membership(
        user_id="user_1",
        source="invite",
        effective_at=effective_at,
        expires_at=expires_at,
        audit_step="referral_membership_grant_applied",
        audit_info={"referral_id": "ref_1"},
    )

    assert result == membership_row
    upsert_mock.assert_awaited_once_with(
        "user_1",
        status="active",
        effective_at=effective_at,
        expires_at=expires_at,
        canceled_at=None,
        ended_at=None,
        source="invite",
    )
    log_mock.assert_awaited_once()
    sync_mock.assert_awaited_once_with("user_1")


async def test_invite_membership_grant_requires_expires_at() -> None:
    with pytest.raises(ValueError, match="invite membership grants require expires_at"):
        await membership_grant_service.grant_non_purchase_membership(
            user_id="user_1",
            source="invite",
            effective_at=datetime(2026, 3, 1, tzinfo=timezone.utc),
            expires_at=None,
            audit_step="invite_membership_grant_applied",
        )


def test_referral_link_does_not_target_register_parameter() -> None:
    link = referral_service.build_signup_url("REFCODE1")

    assert link.endswith("/login")
    assert "/signup?referral_code=" not in link
    assert "referral_code=" not in link
