from __future__ import annotations

from typing import Any, Mapping

import stripe
from fastapi import HTTPException, status
from starlette.concurrency import run_in_threadpool

from .. import models, repositories, schemas
from .. import stripe_mode
from ..config import settings
from ..repositories import course_bundles as bundle_repo
from ..repositories import courses as courses_repo
from ..repositories import payments as payments_repo
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
        return False, "Användar-id saknas"

    course_step = str(course.get("step") or "").strip().lower()
    if course_step not in {"intro", "step1", "step2", "step3"}:
        return False, "Kurssteget saknas"
    if course_step == "intro":
        return False, "Introkurser kräver introinskrivning"
    if course_step in {"step1", "step2", "step3"}:
        return True, None
    return False, "Kurssteget stöds inte"


async def create_course_checkout(
    user: Mapping[str, Any],
    slug: str,
) -> schemas.CheckoutCreateResponse:
    _require_stripe()
    course = await courses_repo.get_course_by_slug(slug)
    if not course or not bool(course.get("sellable")):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Kursen hittades inte",
        )
    can_purchase, denial_reason = await can_purchase_course(user, course)
    if not can_purchase:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=denial_reason or "Kurskraven är inte uppfyllda",
        )

    amount_cents = int(course.get("price_amount_cents") or 0)
    if amount_cents <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursen saknar Stripe-pris",
        )
    currency = "sek"

    product_id = course.get("stripe_product_id")
    if not isinstance(product_id, str) or not product_id.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursen saknar Stripe-produkt",
        )

    price_id = course.get("active_stripe_price_id")
    if not isinstance(price_id, str) or not price_id.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursen saknar Stripe-pris",
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
            detail="Användar-id saknas",
        )
    user_id = str(user_id_value)
    course_id_value = course.get("id")
    if not course_id_value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursen saknar id",
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
            detail="Kunde inte skapa Stripe-betalningssession",
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
            detail="Stripe-session saknar betalningsadress",
        )

    return schemas.CheckoutCreateResponse(
        url=url,
        session_id=session.get("id"),
        order_id=str(order["id"]),
    )


async def apply_valid_one_off_withdrawal(
    user: Mapping[str, Any],
    *,
    order_id: str,
) -> dict[str, Any]:
    return await _apply_one_off_refund_resolution(
        user,
        order_id=order_id,
        resolution_kind="withdrawal",
    )


async def apply_one_off_remedy(
    user: Mapping[str, Any],
    *,
    order_id: str,
) -> dict[str, Any]:
    return await _apply_one_off_refund_resolution(
        user,
        order_id=order_id,
        resolution_kind="remedy",
    )


async def handle_payment_intent_succeeded(
    payload: dict[str, Any],
) -> dict[str, Any] | None:
    payment_intent_id = str(payload.get("id") or "").strip()
    order = None
    if payment_intent_id:
        order = await repositories.get_order_by_payment_intent(payment_intent_id)
    if order and str(order.get("stripe_checkout_id") or "").strip():
        # Checkout-session purchases must settle only from the checkout-session
        # webhook path, never from payment_intent.succeeded.
        return dict(order)

    metadata = payload.get("metadata") or {}
    if not isinstance(metadata, dict):
        metadata = {}
    order_id = metadata.get("order_id")
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


async def _apply_one_off_refund_resolution(
    user: Mapping[str, Any],
    *,
    order_id: str,
    resolution_kind: str,
) -> dict[str, Any]:
    _require_stripe()

    user_id = str(user.get("id") or "").strip()
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Användar-id saknas",
        )

    order = await repositories.get_user_order(order_id, user_id)
    if not order:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Beställningen hittades inte",
        )

    order_type = str(order.get("order_type") or "").strip().lower()
    if order_type not in {"one_off", "bundle"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Beställningen är inte en enstaka digital produkt",
        )

    order_status = str(order.get("status") or "").strip().lower()
    if order_status != "paid":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Beställningen är inte betalad och kan inte åtgärdsåterbetalas",
        )

    payment_intent_id = await _resolve_one_off_refund_payment_intent(order)
    affected_course_ids = await _resolve_one_off_course_ids(order)

    def _create_refund() -> dict[str, Any]:
        return stripe.Refund.create(
            payment_intent=payment_intent_id,
            metadata={
                "resolution_kind": resolution_kind,
                "order_id": str(order["id"]),
                "checkout_type": "one_off",
                "user_id": user_id,
            },
        )

    try:
        await run_in_threadpool(_create_refund)
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Stripe kunde inte skapa återbetalningen",
        ) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Stripe-fel vid återbetalning av digital produkt",
        ) from exc

    revoked_course_ids: list[str] = []
    retained_course_ids: list[str] = []
    for course_id in affected_course_ids:
        revoked = await courses_repo.revoke_course_enrollment(
            user_id,
            course_id,
            excluding_order_id=str(order["id"]),
        )
        if revoked:
            revoked_course_ids.append(course_id)
        else:
            retained_course_ids.append(course_id)

    return {
        "ok": True,
        "order_id": str(order["id"]),
        "resolution_kind": resolution_kind,
        "payment_intent_id": payment_intent_id,
        "revoked_course_ids": revoked_course_ids,
        "retained_course_ids": retained_course_ids,
    }


async def _resolve_one_off_refund_payment_intent(order: Mapping[str, Any]) -> str:
    payment_intent_id = str(order.get("stripe_payment_intent") or "").strip()
    if payment_intent_id:
        return payment_intent_id

    latest_payment = await payments_repo.get_latest_payment_for_order(
        str(order["id"]),
        status="paid",
    )
    provider_reference = str((latest_payment or {}).get("provider_reference") or "").strip()
    if provider_reference:
        return provider_reference

    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="Beställningen saknar betalningsreferens för återbetalning",
    )


async def _resolve_one_off_course_ids(order: Mapping[str, Any]) -> list[str]:
    direct_course_id = str(order.get("course_id") or "").strip()
    if direct_course_id:
        return [direct_course_id]

    metadata = order.get("metadata")
    if not isinstance(metadata, Mapping):
        metadata = {}
    bundle_id = str(metadata.get("bundle_id") or "").strip()
    if not bundle_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Beställningen saknar produktkoppling",
        )

    bundle_courses = await bundle_repo.list_bundle_checkout_courses(bundle_id)
    course_ids = [
        str(row.get("course_id") or "").strip()
        for row in bundle_courses
        if str(row.get("course_id") or "").strip()
    ]
    if not course_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Paketbeställningen saknar kurser att återkalla",
        )
    return course_ids
