from __future__ import annotations

import logging

import sentry_sdk
import stripe
from fastapi import APIRouter, HTTPException, Request, status

from ..repositories import membership_support as membership_support_repo
from ..repositories import orders as orders_repo
from ..repositories import payments as payments_repo
from .. import stripe_mode
from ..services import (
    stripe_webhook_bundle_service,
    stripe_webhook_course_service,
    stripe_webhook_membership_service,
    stripe_webhook_support_service,
)

router = APIRouter(prefix="/api/stripe", tags=["stripe-webhooks"])
logger = logging.getLogger(__name__)
CHECKOUT_SESSION_COMPLETION_EVENTS = {
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
}


def _sentry_enabled() -> bool:
    return sentry_sdk.Hub.current.client is not None


def _capture_message(
    *,
    status: str,
    event_type: str | None,
    event_id: str | None,
    message: str,
    level: str = "warning",
) -> None:
    if not _sentry_enabled():
        return
    with sentry_sdk.push_scope() as scope:
        scope.set_tag("webhook.provider", "stripe")
        scope.set_tag("webhook.status", status)
        if event_type:
            scope.set_tag("webhook.event_type", event_type)
        if event_id:
            scope.set_tag("webhook.event_id", event_id)
        if status == "failed":
            scope.set_tag("alert_kind", "webhook_failure")
        sentry_sdk.capture_message(message, level=level)


def _capture_exception(
    event_type: str | None,
    event_id: str | None,
    exc: Exception,
) -> None:
    if not _sentry_enabled():
        return
    with sentry_sdk.push_scope() as scope:
        scope.set_tag("webhook.provider", "stripe")
        scope.set_tag("webhook.status", "failed")
        scope.set_tag("alert_kind", "webhook_failure")
        if event_type:
            scope.set_tag("webhook.event_type", event_type)
        if event_id:
            scope.set_tag("webhook.event_id", event_id)
        sentry_sdk.capture_exception(exc)


@router.post("/webhook", status_code=status.HTTP_200_OK)
async def stripe_payment_element_webhook(request: Request):
    # /api/stripe/webhook is the canonical Stripe webhook endpoint.
    try:
        context = stripe_mode.resolve_stripe_context()
        secret, _ = stripe_mode.resolve_webhook_secret("default", context)
    except stripe_mode.StripeConfigurationError as exc:
        _capture_exception(None, None, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc

    payload = await request.body()
    signature = request.headers.get("stripe-signature")
    if not signature:
        _capture_message(
            status="rejected",
            event_type=None,
            event_id=None,
            message="Stripe webhook rejected: missing signature",
            level="warning",
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Stripe-signatur saknas",
        )

    try:
        event = stripe.Webhook.construct_event(
            payload=payload.decode("utf-8"),
            sig_header=signature,
            secret=secret,
        )
    except ValueError as exc:
        logger.warning("Invalid Stripe payload: %s", exc)
        _capture_message(
            status="rejected",
            event_type=None,
            event_id=None,
            message="Stripe webhook rejected: invalid payload",
            level="warning",
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Ogiltig payload"
        ) from exc
    except stripe.error.SignatureVerificationError as exc:  # type: ignore[attr-defined]
        logger.warning("Invalid Stripe signature: %s", exc)
        _capture_message(
            status="rejected",
            event_type=None,
            event_id=None,
            message="Stripe webhook rejected: invalid signature",
            level="warning",
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Ogiltig signatur"
        ) from exc

    event_type = event.get("type")
    event_id = event.get("id")
    data_object = event.get("data", {}).get("object", {})

    if isinstance(event_id, str) and event_id:
        inserted = await membership_support_repo.insert_payment_event(event_id, dict(event))
        if not inserted:
            logger.info("Skipping duplicate Stripe event %s", event_id)
            return {"status": "ok"}

    try:
        if event_type == "payment_intent.succeeded":
            await stripe_webhook_support_service.handle_payment_intent_succeeded(
                data_object,
            )
        elif event_type in CHECKOUT_SESSION_COMPLETION_EVENTS:
            if stripe_webhook_membership_service.is_membership_checkout_session(
                data_object,
            ):
                await stripe_webhook_membership_service.handle_event(event)
            else:
                await _handle_checkout_session_completion(data_object, str(event_type))
        elif stripe_webhook_membership_service.is_membership_event_type(
            str(event_type) if event_type else None,
        ):
            await stripe_webhook_membership_service.handle_event(event)
        elif event_type == "payment_intent.payment_failed":
            logger.info(
                "Payment failed for intent %s",
                data_object.get("id"),
            )
        elif event_type in {"charge.refunded", "payment_intent.canceled"}:
            await stripe_webhook_support_service.handle_refund_event(
                str(event_type),
                data_object,
            )
        elif event_type and event_type.startswith("account."):
            logger.info("Ignoring inactive Stripe Connect event %s", event_type)
        else:
            logger.info("Unhandled Stripe event %s", event_type)
    except Exception as exc:  # pragma: no cover - defensive logging
        _capture_exception(str(event_type) if event_type else None, str(event_id) if event_id else None, exc)
        logger.exception("Stripe webhook processing failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Webhook-bearbetningen misslyckades",
        ) from exc

    _capture_message(
        status="success",
        event_type=str(event_type) if event_type else None,
        event_id=str(event_id) if event_id else None,
        message="Stripe webhook processed",
        level="info",
    )

    return {"status": "ok"}


async def _handle_checkout_session_completion(
    session: dict[str, object],
    event_type: str,
) -> None:
    order = await _resolve_checkout_order(session, event_type)
    if not order:
        return

    await _settle_checkout_order(order=order, session=session, event_type=event_type)

    order_metadata = order.get("metadata")
    if not isinstance(order_metadata, dict):
        order_metadata = {}

    if order.get("course_id"):
        await stripe_webhook_course_service.handle_paid_checkout_order(
            order=order,
            event_type=event_type,
        )
        return

    if order_metadata.get("bundle_id"):
        payment_intent = session.get("payment_intent")
        stripe_customer_id = (
            str(session.get("customer")) if session.get("customer") else None
        )
        await stripe_webhook_bundle_service.handle_paid_checkout_order(
            order=order,
            stripe_customer_id=stripe_customer_id,
            payment_intent_id=str(payment_intent) if payment_intent else None,
            event_type=event_type,
        )
        return

    logger.info(
        "Checkout session had no course or bundle authority; order_id=%s event=%s",
        order.get("id"),
        event_type,
    )


async def _resolve_checkout_order(
    session: dict[str, object],
    event_type: str,
) -> dict[str, object] | None:
    metadata = session.get("metadata") if isinstance(session.get("metadata"), dict) else {}
    if not isinstance(metadata, dict):
        metadata = {}
    order_id = metadata.get("order_id") or session.get("client_reference_id")
    checkout_id = session.get("id")

    if not order_id:
        logger.warning("Checkout session missing order_id; checkout=%s event=%s", checkout_id, event_type)
        return None

    order = await orders_repo.get_order(order_id)
    if not order:
        logger.warning("Checkout session could not resolve order; order_id=%s event=%s", order_id, event_type)
        return None
    if order.get("status") == "paid":
        logger.info("Skipping already paid checkout session; order_id=%s event=%s", order_id, event_type)
        return None
    return order


async def _settle_checkout_order(
    *,
    order: dict[str, object],
    session: dict[str, object],
    event_type: str,
) -> None:
    payment_intent = session.get("payment_intent")
    checkout_id = session.get("id")
    amount_cents = int(session.get("amount_total") or 0)
    currency = (session.get("currency") or "sek").lower()

    await payments_repo.mark_order_paid(
        order["id"],
        payment_intent=str(payment_intent) if payment_intent else None,
        checkout_id=checkout_id if isinstance(checkout_id, str) else None,
        subscription_id=str(session.get("subscription")) if session.get("subscription") else None,
        customer_id=str(session.get("customer")) if session.get("customer") else None,
    )

    await payments_repo.record_payment(
        order_id=order["id"],
        provider="stripe",
        provider_reference=str(payment_intent) if payment_intent else None,
        status="paid",
        amount_cents=amount_cents or int(order.get("amount_cents") or 0),
        currency=currency,
        metadata={"event": event_type},
        payload=session if isinstance(session, dict) else {},
    )
