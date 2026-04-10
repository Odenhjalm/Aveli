from __future__ import annotations

from typing import Any, Mapping

import stripe
from fastapi import HTTPException, status
from starlette.concurrency import run_in_threadpool

from .. import models, repositories, schemas
from ..config import settings
from .. import stripe_mode
from ..repositories import courses as courses_repo
from . import stripe_customers as stripe_customers_service

RETURN_PATH = "checkout/return?session_id={CHECKOUT_SESSION_ID}"
CANCEL_PATH = "checkout/cancel"
RETURN_DEEP_LINK = f"aveliapp://{RETURN_PATH}"
CANCEL_DEEP_LINK = "aveliapp://checkout/cancel"
def _default_checkout_urls() -> tuple[str, str]:
    base = (settings.frontend_base_url or "").rstrip("/")
    success_http = f"{base}/{RETURN_PATH}" if base else None
    cancel_http = f"{base}/{CANCEL_PATH}" if base else None
    success_url = settings.checkout_success_url or success_http or RETURN_DEEP_LINK
    cancel_url = settings.checkout_cancel_url or cancel_http or CANCEL_DEEP_LINK
    return success_url, cancel_url


def _require_stripe() -> None:
    try:
        context = stripe_mode.resolve_stripe_context()
    except stripe_mode.StripeConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    stripe.api_key = context.secret_key


async def can_purchase_course(
    user: Mapping[str, Any],
    course: Mapping[str, Any],
) -> tuple[bool, str | None]:
    user_id = str(user.get("id") or "").strip()
    if not user_id:
        return False, "user id missing"

    course_step = str(course.get("step") or "").strip().lower()
    if course_step not in {"intro", "step1", "step2", "step3"}:
        return False, "course step missing"
    if course_step == "intro":
        return False, "intro courses require intro enrollment"
    if course_step in {"step1", "step2", "step3"}:
        return True, None
    return False, "course step unsupported"


async def create_course_checkout(
    user: Mapping[str, Any],
    slug: str,
) -> schemas.CheckoutCreateResponse:
    _require_stripe()
    course = await courses_repo.get_course_by_slug(slug)
    if not course or not bool(course.get("sellable")):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="course not found")
    can_purchase, denial_reason = await can_purchase_course(user, course)
    if not can_purchase:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=denial_reason or "course prerequisites are not satisfied",
        )

    amount_cents = int(course.get("price_amount_cents") or 0)
    if amount_cents <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="course has no Stripe price configured",
        )
    currency = "sek"

    product_id = course.get("stripe_product_id")
    if not isinstance(product_id, str) or not product_id.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="course has no Stripe product configured",
        )

    price_id = course.get("active_stripe_price_id")
    if not isinstance(price_id, str) or not price_id.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="course has no Stripe price configured",
        )

    try:
        customer_id = await stripe_customers_service.ensure_customer_id(user)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    user_id_value = user.get("id")
    if not user_id_value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="user id missing",
        )
    user_id = str(user_id_value)
    course_id_value = course.get("id")
    if not course_id_value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="course is missing id",
        )
    course_slug = str(course.get("slug") or slug)
    metadata: dict[str, Any] = {
        "user_id": user_id,
        "course_slug": course_slug,
        "price_id": price_id,
        "checkout_type": "course",
    }

    order = await repositories.create_order(
        user_id=user_id,
        service_id=None,
        course_id=str(course_id_value),
        amount_cents=amount_cents,
        currency=currency,
        order_type="one_off",
        metadata=metadata,
        stripe_customer_id=customer_id,
        stripe_subscription_id=None,
        connected_account_id=None,
        session_id=None,
        session_slot_id=None,
    )
    metadata["order_id"] = str(order["id"])

    success_url, cancel_url = _default_checkout_urls()
    line_items = [{"price": price_id, "quantity": 1}]

    checkout_kwargs: dict[str, Any] = {
        "mode": "payment",
        "customer": customer_id,
        "line_items": line_items,
        "success_url": success_url,
        "cancel_url": cancel_url,
        "metadata": metadata,
        "locale": "sv",
    }
    checkout_kwargs["ui_mode"] = settings.stripe_checkout_ui_mode or "custom"

    try:
        session = await run_in_threadpool(lambda: stripe.checkout.Session.create(**checkout_kwargs))
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to create Stripe checkout session",
        ) from exc

    await repositories.set_order_checkout_reference(
        order_id=order["id"],
        checkout_id=session.get("id"),
        payment_intent=session.get("payment_intent"),
    )

    url = session.get("url")
    if not isinstance(url, str) or not url:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Stripe session missing checkout url",
        )

    return schemas.CheckoutCreateResponse(
        url=url,
        session_id=session.get("id"),
        order_id=str(order["id"]),
    )


async def handle_payment_intent_succeeded(
    payload: dict[str, Any],
) -> dict[str, Any] | None:
    metadata = payload.get("metadata") or {}
    if not isinstance(metadata, dict):
        metadata = {}
    order_id = metadata.get("order_id")
    payment_intent_id = payload.get("id")
    if not order_id:
        return None

    order = await repositories.get_order(order_id)
    if not order:
        return None
    if order.get("status") == "paid":
        return order

    updated_order = await models.mark_order_paid(
        order_id,
        payment_intent=payment_intent_id,
        checkout_id=None,
    )
    return updated_order
