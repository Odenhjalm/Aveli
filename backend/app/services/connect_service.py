from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import stripe
from fastapi import HTTPException, status
from starlette.concurrency import run_in_threadpool

from .. import repositories
from ..config import settings

logger = logging.getLogger(__name__)


def _ensure_connect_configuration() -> None:
    if not settings.stripe_secret_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Stripe secret key saknas",
        )
    if not settings.stripe_connect_client_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Stripe Connect Client ID saknas",
        )
    stripe.api_key = settings.stripe_secret_key


def _coalesce_url(explicit: str | None, fallback: str | None) -> str:
    value = explicit or fallback
    if not value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ange return_url/refresh_url eller konfigurera standardvärden",
        )
    return value


def _unwrap_stripe_error(exc: Exception) -> HTTPException:
    detail = "Stripe API error"
    status_code = status.HTTP_502_BAD_GATEWAY
    if isinstance(exc, stripe.error.InvalidRequestError):  # type: ignore[attr-defined]
        detail = exc.user_message or exc.user_message or str(exc)
        status_code = status.HTTP_400_BAD_REQUEST
    elif isinstance(exc, stripe.error.StripeError):  # type: ignore[attr-defined]
        detail = exc.user_message or str(exc)
    logger.warning("Stripe Connect error: %s", detail)
    return HTTPException(status_code=status_code, detail=detail)


def _map_account_status(account: dict[str, Any] | None) -> tuple[str, dict[str, Any]]:
    if not account:
        return "pending", {}
    requirements = account.get("requirements") or {}
    charges_enabled = bool(account.get("charges_enabled"))
    payouts_enabled = bool(account.get("payouts_enabled"))
    disabled_reason = requirements.get("disabled_reason")
    if charges_enabled and payouts_enabled:
        return "verified", requirements
    if disabled_reason:
        return "restricted", requirements
    return "onboarding", requirements


async def create_onboarding_link(
    *,
    teacher_id: str,
    refresh_url: str | None,
    return_url: str | None,
) -> dict[str, Any]:
    _ensure_connect_configuration()

    teacher_row = await repositories.get_teacher(teacher_id)
    account_id = teacher_row.get("stripe_connect_account_id") if teacher_row else None

    if not account_id:
        profile = await repositories.get_profile(teacher_id)
        email = (profile or {}).get("email")
        display_name = (profile or {}).get("display_name")

        try:
            account = await run_in_threadpool(
                lambda: stripe.Account.create(
                    type="express",
                    country="SE",
                    email=email,
                    business_type="individual",
                    capabilities={
                        "card_payments": {"requested": True},
                        "transfers": {"requested": True},
                    },
                    business_profile={
                        "product_description": "Aveli lärarstudioplattform",
                        "name": display_name or "Aveli Teacher",
                    },
                    metadata={"teacher_id": teacher_id},
                )
            )
        except Exception as exc:  # pragma: no cover - Stripe errors
            raise _unwrap_stripe_error(exc) from exc
        account_id = account.get("id")
        if not account_id:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Stripe returnerade inget konto-id",
            )
        await repositories.upsert_teacher(
            teacher_id,
            stripe_connect_account_id=account_id,
            status="onboarding",
        )

    refresh = _coalesce_url(refresh_url, settings.stripe_connect_refresh_url)
    return_dest = _coalesce_url(return_url, settings.stripe_connect_return_url)

    try:
        account_link = await run_in_threadpool(
            lambda: stripe.AccountLink.create(
                account=account_id,
                refresh_url=refresh,
                return_url=return_dest,
                type="account_onboarding",
            )
        )
    except Exception as exc:  # pragma: no cover
        raise _unwrap_stripe_error(exc) from exc

    onboarding_url = account_link.get("url")
    if not onboarding_url:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Stripe returnerade ingen onboarding-länk",
        )

    return {
        "account_id": account_id,
        "onboarding_url": onboarding_url,
    }


async def get_connect_status(teacher_id: str) -> dict[str, Any]:
    _ensure_connect_configuration()

    teacher_row = await repositories.get_teacher(teacher_id)
    if not teacher_row:
        return {
            "account_id": None,
            "status": "pending",
            "charges_enabled": False,
            "payouts_enabled": False,
            "requirements_due": {},
            "onboarded_at": None,
        }

    account_id = teacher_row.get("stripe_connect_account_id")
    charges_enabled = bool(teacher_row.get("charges_enabled"))
    payouts_enabled = bool(teacher_row.get("payouts_enabled"))
    requirements = teacher_row.get("requirements_due") or {}
    status_value = teacher_row.get("status") or "pending"
    onboarded_at = teacher_row.get("onboarded_at")

    account = None
    if account_id:
        try:
            account = await run_in_threadpool(
                lambda: stripe.Account.retrieve(account_id)
            )
        except stripe.error.InvalidRequestError:  # type: ignore[attr-defined]
            account = None
        except Exception as exc:  # pragma: no cover
            raise _unwrap_stripe_error(exc) from exc

    if account:
        charges_enabled = bool(account.get("charges_enabled"))
        payouts_enabled = bool(account.get("payouts_enabled"))
        status_value, requirements = _map_account_status(account)
        if charges_enabled and payouts_enabled and not onboarded_at:
            onboarded_at = datetime.now(timezone.utc)
        await repositories.update_teacher_status(
            teacher_id,
            charges_enabled=charges_enabled,
            payouts_enabled=payouts_enabled,
            requirements_due=requirements,
            status=status_value,
            onboarded_at=onboarded_at,
        )

    return {
        "account_id": account_id,
        "status": status_value,
        "charges_enabled": charges_enabled,
        "payouts_enabled": payouts_enabled,
        "requirements_due": requirements,
        "onboarded_at": onboarded_at,
    }
