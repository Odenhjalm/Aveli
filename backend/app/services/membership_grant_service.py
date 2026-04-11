from __future__ import annotations

from datetime import datetime
from typing import Any

from ..repositories import membership_support as membership_support_repo
from ..repositories import memberships as memberships_repo
from .onboarding_state import sync_onboarding_state

_NON_PURCHASE_SOURCES = {"coupon", "invite"}


async def grant_non_purchase_membership(
    *,
    user_id: str,
    source: str,
    effective_at: datetime | None,
    expires_at: datetime | None,
    audit_step: str,
    audit_info: dict[str, Any] | None = None,
) -> dict[str, Any]:
    normalized_source = str(source or "").strip().lower()
    if normalized_source not in _NON_PURCHASE_SOURCES:
        raise ValueError("grant_non_purchase_membership requires canonical non-purchase source")
    if normalized_source == "invite" and expires_at is None:
        raise ValueError("invite membership grants require expires_at")

    membership = await memberships_repo.upsert_membership_record(
        user_id,
        status="active",
        effective_at=effective_at,
        expires_at=expires_at,
        canceled_at=None,
        ended_at=None,
        source=normalized_source,
    )
    await membership_support_repo.insert_billing_log(
        user_id=user_id,
        step=audit_step,
        info={
            "source": normalized_source,
            "membership_id": str(membership.get("membership_id") or ""),
            "effective_at": effective_at.isoformat() if isinstance(effective_at, datetime) else None,
            "expires_at": expires_at.isoformat() if isinstance(expires_at, datetime) else None,
            **(audit_info or {}),
        },
    )
    await sync_onboarding_state(user_id)
    return membership


__all__ = ["grant_non_purchase_membership"]
