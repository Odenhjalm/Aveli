from __future__ import annotations

import secrets
from typing import Any

from ..config import settings
from ..repositories import referrals as referrals_repo
from ..utils.referrals import build_referral_duration_label
from . import email_service
from . import membership_grant_service

_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_CODE_LENGTH = 10
_MAX_CODE_ATTEMPTS = 8


def generate_referral_code(length: int = _CODE_LENGTH) -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(length))


def build_signup_url(code: str) -> str:
    base = (settings.frontend_base_url or "http://localhost:3000").rstrip("/")
    return f"{base}/signup?referral_code={code}"


async def create_referral_invitation(
    *,
    teacher_id: str,
    email: str,
    free_days: int | None = None,
    free_months: int | None = None,
) -> tuple[dict[str, object], email_service.EmailDeliveryResult]:
    last_error: Exception | None = None
    for _ in range(_MAX_CODE_ATTEMPTS):
        code = generate_referral_code()
        try:
            referral = await referrals_repo.create_referral_code(
                teacher_id=teacher_id,
                code=code,
                email=email,
                free_days=free_days,
                free_months=free_months,
            )
            break
        except referrals_repo.UniqueReferralCodeError as exc:
            last_error = exc
    else:  # pragma: no cover - practically unreachable, but defensive
        raise RuntimeError("Failed to generate a unique referral code") from last_error

    delivery = await email_service.send_email(
        to_email=email,
        subject="Din Aveli-inbjudan",
        text_body=_build_referral_email_text(
            code=str(referral["code"]),
            free_days=free_days,
            free_months=free_months,
        ),
    )
    return referral, delivery


async def redeem_referral(
    *,
    code: str,
    user_id: str,
    email: str,
) -> dict[str, Any]:
    redemption = await referrals_repo.redeem_referral_code(
        code=code,
        user_id=user_id,
        email=email,
    )
    await membership_grant_service.grant_non_purchase_membership(
        user_id=user_id,
        source="invite",
        effective_at=redemption.get("effective_at"),
        expires_at=redemption.get("expires_at"),
        audit_step="referral_membership_grant_applied",
        audit_info={
            "referral_id": str(redemption.get("id") or ""),
            "referral_code": str(redemption.get("code") or ""),
            "teacher_id": str(redemption.get("teacher_id") or ""),
        },
    )
    return redemption


def _build_referral_email_text(
    *,
    code: str,
    free_days: int | None = None,
    free_months: int | None = None,
) -> str:
    duration = build_referral_duration_label(
        free_days=free_days,
        free_months=free_months,
    )
    signup_url = build_signup_url(code)
    return (
        "Du har blivit inbjuden till Aveli.\n\n"
        f"Din kod ger {duration} medlemskap utan att starta någon Stripe-provperiod.\n"
        f"Registrera dig här: {signup_url}\n\n"
        f"Om länken inte fyller i koden automatiskt använder du: {code}\n"
    )


__all__ = [
    "build_referral_duration_label",
    "build_signup_url",
    "create_referral_invitation",
    "generate_referral_code",
    "redeem_referral",
]
