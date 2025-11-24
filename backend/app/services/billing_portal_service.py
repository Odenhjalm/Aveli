from __future__ import annotations

import logging
from typing import Any, Mapping

import stripe
from starlette.concurrency import run_in_threadpool

from ..config import settings
from ..db import get_conn
from ..repositories import memberships as memberships_repo
from ..repositories import stripe_customers as stripe_customers_repo

logger = logging.getLogger(__name__)

_PORTAL_ALLOWED_STATUSES = {"active", "trialing"}


class BillingPortalError(Exception):
    status_code = 400

    def __init__(self, detail: str, status_code: int | None = None) -> None:
        super().__init__(detail)
        if status_code is not None:
            self.status_code = status_code
        self.detail = detail


class BillingPortalConfigError(BillingPortalError):
    def __init__(self, detail: str) -> None:
        super().__init__(detail, status_code=503)


async def create_billing_portal_session(user: Mapping[str, Any]) -> str:
    secret = settings.stripe_secret_key
    if not secret:
        raise BillingPortalConfigError("Stripe secret key is missing")

    user_id = str(user["id"])
    membership = await memberships_repo.get_membership(user_id)
    if not _has_active_membership(membership):
        raise BillingPortalError("Ingen aktiv prenumeration hittades", status_code=400)

    customer_id = await ensure_customer_id(user, membership=membership)

    stripe.api_key = secret
    return_url = _build_return_url()

    def _create_session() -> dict[str, Any]:
        return stripe.billing_portal.Session.create(
            customer=customer_id,
            return_url=return_url,
        )

    session = await run_in_threadpool(_create_session)
    url = session.get("url")
    if not isinstance(url, str) or not url:
        raise BillingPortalError("Stripe portal-URL saknas", status_code=502)

    try:
        await memberships_repo.insert_billing_log(
            user_id=user_id,
            step="create_billing_portal",
            info={"session_id": session.get("id"), "customer_id": customer_id},
        )
    except Exception:  # pragma: no cover - logging only
        logger.debug("Failed to insert billing log for portal session", exc_info=True)

    return url


def _has_active_membership(membership: Mapping[str, Any] | None) -> bool:
    if not membership:
        return False
    status_value = (membership.get("status") or "").lower()
    return status_value in _PORTAL_ALLOWED_STATUSES


async def ensure_customer_id(
    user: Mapping[str, Any],
    *,
    membership: Mapping[str, Any] | None = None,
) -> str:
    secret = settings.stripe_secret_key
    if not secret:
        raise BillingPortalConfigError("Stripe secret key is missing")

    user_id = str(user["id"])
    membership_row = membership or await memberships_repo.get_membership(user_id)
    customer_id = membership_row.get("stripe_customer_id") if membership_row else None
    if not customer_id:
        customer_id = await _get_profile_customer_id(user_id)
    if not customer_id:
        customer_id = await stripe_customers_repo.get_customer_id_for_user(user_id)
    if customer_id:
        await _persist_customer_id(user_id, customer_id, membership_row)
        return customer_id

    stripe.api_key = secret

    def _create_customer() -> dict[str, Any]:
        return stripe.Customer.create(
            email=user.get("email"),
            name=user.get("display_name"),
            metadata={"user_id": user_id},
        )

    customer = await run_in_threadpool(_create_customer)
    created_id = customer.get("id")
    if not isinstance(created_id, str) or not created_id:
        raise BillingPortalError("Stripe kunde kunde inte skapas", status_code=502)
    await _persist_customer_id(user_id, created_id, membership_row)
    return created_id


async def _get_profile_customer_id(user_id: str) -> str | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT stripe_customer_id
              FROM app.profiles
             WHERE user_id = %s
             LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
    return row["stripe_customer_id"] if row and row.get("stripe_customer_id") else None


async def _set_profile_customer_id(user_id: str, customer_id: str) -> None:
    async with get_conn() as cur:
        await cur.execute(
            """
            UPDATE app.profiles
               SET stripe_customer_id = %s,
                   updated_at = now()
             WHERE user_id = %s
            """,
            (customer_id, user_id),
        )


async def _persist_customer_id(
    user_id: str,
    customer_id: str,
    membership: Mapping[str, Any] | None,
) -> None:
    try:
        await stripe_customers_repo.upsert_customer(user_id, customer_id)
    except Exception:  # pragma: no cover - best effort
        logger.debug("Failed to store stripe customer in legacy table", exc_info=True)
    if membership and not membership.get("stripe_customer_id"):
        try:
            await memberships_repo.set_customer_id(user_id, customer_id)
        except Exception:  # pragma: no cover - best effort
            logger.debug("Failed to persist customer id on membership", exc_info=True)
    try:
        await _set_profile_customer_id(user_id, customer_id)
    except Exception:  # pragma: no cover - best effort
        logger.debug("Failed to persist customer id on profile", exc_info=True)


def _build_return_url() -> str:
    if settings.checkout_success_url:
        return settings.checkout_success_url
    base = settings.frontend_base_url or "http://localhost:3000"
    base = base.rstrip("/")
    return f"{base}/profile/subscription"


__all__ = [
    "BillingPortalError",
    "BillingPortalConfigError",
    "create_billing_portal_session",
    "ensure_customer_id",
]
