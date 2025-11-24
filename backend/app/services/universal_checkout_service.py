from __future__ import annotations

import os
import re
import logging
from dataclasses import dataclass
from typing import Any, Mapping

import stripe
from fastapi import status
from starlette.concurrency import run_in_threadpool

from .. import repositories, schemas
from ..config import settings
from ..repositories import memberships as memberships_repo
from . import stripe_customers as stripe_customers_service

logger = logging.getLogger(__name__)


class CheckoutError(Exception):
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, detail: str, *, status_code: int | None = None) -> None:
        super().__init__(detail)
        if status_code:
            self.status_code = status_code
        self.detail = detail


class CheckoutConfigError(CheckoutError):
    def __init__(self, detail: str) -> None:
        super().__init__(detail, status_code=status.HTTP_503_SERVICE_UNAVAILABLE)


@dataclass
class PriceInfo:
    price_id: str
    amount_cents: int
    currency: str
    course_id: str | None = None
    service_id: str | None = None


def _require_stripe() -> None:
    if not settings.stripe_secret_key:
        raise CheckoutConfigError("Stripe secret key is missing")
    stripe.api_key = settings.stripe_secret_key


def _slug_to_env_key(slug: str, *, prefix: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9]", "_", slug)
    return f"{prefix}_{normalized}".upper()


def _price_for_subscription(interval: schemas.SubscriptionInterval) -> str | None:
    if interval is schemas.SubscriptionInterval.month:
        return settings.stripe_price_monthly
    if interval is schemas.SubscriptionInterval.year:
        return settings.stripe_price_yearly
    return None


def _price_for_service(slug: str) -> str | None:
    return os.getenv(_slug_to_env_key(slug, prefix="STRIPE_PRICE_SERVICE"))


async def _get_or_create_customer(user: Mapping[str, Any]) -> str:
    try:
        return await stripe_customers_service.ensure_customer_id(user)
    except RuntimeError as exc:
        raise CheckoutError(str(exc), status_code=status.HTTP_502_BAD_GATEWAY) from exc


async def _resolve_price(
    payload: schemas.CheckoutCreateRequest,
) -> PriceInfo:
    if payload.type is schemas.CheckoutType.subscription:
        if not payload.interval:
            raise CheckoutError("Subscription interval is required")
        price_id = _price_for_subscription(payload.interval)
        if not price_id:
            raise CheckoutConfigError("Stripe price for subscription interval is missing")
        price = await _retrieve_price(price_id)
        return PriceInfo(
            price_id=price_id,
            amount_cents=price["amount_cents"],
            currency=price["currency"],
        )

    if not payload.slug:
        raise CheckoutError("slug is required for course and service checkouts")

    if payload.type is schemas.CheckoutType.course:
        raise CheckoutError("Course checkout is not supported via this endpoint")

    price_id = _price_for_service(payload.slug)
    if not price_id:
        raise CheckoutConfigError(f"Stripe price for service {payload.slug} is missing")
    price_info = await _retrieve_price(price_id)
    return PriceInfo(
        price_id=price_id,
        amount_cents=price_info["amount_cents"],
        currency=price_info["currency"],
    )


async def _retrieve_price(price_id: str) -> dict[str, Any]:
    try:
        price = await run_in_threadpool(lambda: stripe.Price.retrieve(price_id))
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise CheckoutError(f"Failed to retrieve Stripe price {price_id}") from exc

    amount_cents = int(price.get("unit_amount") or 0)
    currency = (price.get("currency") or "sek").lower()
    if amount_cents <= 0:
        raise CheckoutError("Stripe price is missing amount", status_code=400)
    return {"amount_cents": amount_cents, "currency": currency}


async def create_checkout_session(
    user: Mapping[str, Any],
    payload: schemas.CheckoutCreateRequest,
) -> schemas.CheckoutCreateResponse:
    _require_stripe()

    user_id = str(user["id"])
    price_info = await _resolve_price(payload)
    customer_id = await _get_or_create_customer(user)

    metadata: dict[str, Any] = {
        "user_id": user_id,
        "price_id": price_info.price_id,
        "checkout_type": payload.type.value,
    }

    if payload.type is schemas.CheckoutType.course and payload.slug:
        metadata["course_slug"] = payload.slug
    if payload.type is schemas.CheckoutType.service and payload.slug:
        metadata["service_slug"] = payload.slug
    if payload.type is schemas.CheckoutType.subscription and payload.interval:
        metadata.update(
            {
                "subscription": "aveli_premium",
                "interval": payload.interval.value,
            }
        )

    order = await repositories.create_order(
        user_id=user_id,
        service_id=price_info.service_id,
        course_id=price_info.course_id,
        amount_cents=price_info.amount_cents,
        currency=price_info.currency,
        order_type="subscription" if payload.type is schemas.CheckoutType.subscription else "one_off",
        metadata=metadata,
        stripe_customer_id=customer_id,
        stripe_subscription_id=None,
        connected_account_id=None,
        session_id=None,
        session_slot_id=None,
    )
    metadata["order_id"] = str(order["id"])

    frontend_base = (settings.frontend_base_url or "").rstrip("/")
    success_url = (
        settings.checkout_success_url
        or (f"{frontend_base}/checkout/success" if frontend_base else None)
        or "aveliapp://checkout_success"
    )
    cancel_url = (
        settings.checkout_cancel_url
        or (f"{frontend_base}/checkout/cancel" if frontend_base else None)
        or "aveliapp://checkout_cancel"
    )
    checkout_mode = "subscription" if payload.type is schemas.CheckoutType.subscription else "payment"
    checkout_kwargs: dict[str, Any] = {
        "mode": checkout_mode,
        "customer": customer_id,
        "line_items": [{"price": price_info.price_id, "quantity": 1}],
        "success_url": success_url,
        "cancel_url": cancel_url,
        "metadata": metadata,
        "locale": "sv",
    }
    if payload.type is schemas.CheckoutType.subscription:
        checkout_kwargs["subscription_data"] = {
            "trial_period_days": 14,
            "metadata": metadata,
        }
    ui_mode = settings.stripe_checkout_ui_mode or "custom"
    checkout_kwargs["ui_mode"] = ui_mode
    checkout_type = payload.type.value if payload.type else "unknown"
    logger.info(
        "Creating Stripe checkout session price_id=%s type=%s mode=%s ui_mode=%s",
        price_info.price_id,
        checkout_type,
        checkout_mode,
        ui_mode,
    )

    try:
        session = await run_in_threadpool(
            lambda: stripe.checkout.Session.create(**checkout_kwargs)
        )
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise CheckoutError("Failed to create Stripe checkout session", status_code=502) from exc

    await repositories.set_order_checkout_reference(
        order_id=order["id"],
        checkout_id=session.get("id"),
        payment_intent=session.get("payment_intent"),
    )

    url = session.get("url")
    url_present = bool(isinstance(url, str) and url)
    logger.info(
        "Stripe checkout session created price_id=%s mode=%s ui_mode=%s url_present=%s",
        price_info.price_id,
        checkout_mode,
        ui_mode,
        url_present,
    )
    if not isinstance(url, str) or not url:
        logger.error(
            "Stripe session missing checkout url for price_id=%s mode=%s ui_mode=%s",
            price_info.price_id,
            checkout_mode,
            ui_mode,
        )
        raise CheckoutError("Stripe session missing checkout url", status_code=502)

    if payload.type is schemas.CheckoutType.subscription and payload.interval:
        await memberships_repo.upsert_membership_record(
            user_id,
            plan_interval=payload.interval.value,
            price_id=price_info.price_id,
            status="incomplete",
            stripe_customer_id=customer_id,
            stripe_subscription_id=None,
        )
        await memberships_repo.insert_billing_log(
            user_id=user_id,
            step="create_unified_checkout",
            info={
                "interval": payload.interval.value,
                "order_id": str(order["id"]),
                "session_id": session.get("id"),
            },
        )

    return schemas.CheckoutCreateResponse(
        url=url,
        session_id=session.get("id"),
        order_id=str(order["id"]),
    )


__all__ = ["create_checkout_session", "CheckoutError", "CheckoutConfigError"]
