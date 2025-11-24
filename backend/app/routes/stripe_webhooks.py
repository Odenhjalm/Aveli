from __future__ import annotations

import logging
from datetime import datetime, timezone

import stripe
from fastapi import APIRouter, HTTPException, Request, status
from starlette.concurrency import run_in_threadpool

from .. import repositories
from ..repositories import course_entitlements
from ..repositories import courses as courses_repo
from ..config import settings
from ..services import checkout_service, subscription_service, course_bundles_service

router = APIRouter(prefix="/webhooks", tags=["stripe-webhooks"])
logger = logging.getLogger(__name__)


@router.post("/stripe", status_code=status.HTTP_200_OK)
async def stripe_payment_element_webhook(request: Request):
    # /webhooks/stripe handles Payment Element & one-off purchases via STRIPE_WEBHOOK_SECRET.
    if not settings.stripe_webhook_secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Stripe webhook secret missing",
        )

    payload = await request.body()
    signature = request.headers.get("stripe-signature")
    if not signature:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Stripe signature",
        )

    try:
        event = stripe.Webhook.construct_event(
            payload=payload.decode("utf-8"),
            sig_header=signature,
            secret=settings.stripe_webhook_secret,
        )
    except ValueError as exc:
        logger.warning("Invalid Stripe payload: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid payload"
        ) from exc
    except stripe.error.SignatureVerificationError as exc:  # type: ignore[attr-defined]
        logger.warning("Invalid Stripe signature: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid signature"
        ) from exc

    event_type = event.get("type")
    data_object = event.get("data", {}).get("object", {})

    if event_type == "payment_intent.succeeded":
        await checkout_service.handle_payment_intent_succeeded(data_object)
        metadata = data_object.get("metadata") or {}
        if isinstance(metadata, dict):
            user_id = metadata.get("user_id")
            course_slug = metadata.get("course_slug")
            if user_id and course_slug:
                await course_entitlements.grant_course_entitlement(
                    user_id=str(user_id),
                    course_slug=str(course_slug),
                    stripe_customer_id=str(data_object.get("customer"))
                    if data_object.get("customer")
                    else None,
                    payment_intent_id=str(data_object.get("id"))
                    if data_object.get("id")
                    else None,
                )
    elif event_type in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}:
        await _handle_checkout_session(data_object, event_type)
    elif event_type.startswith("customer.subscription") or event_type.startswith("invoice.payment_"):
        try:
            await subscription_service.process_event(event)
        except Exception as exc:  # pragma: no cover - defensive logging
            logger.warning("Failed to process subscription event %s: %s", event_type, exc)
    elif event_type == "payment_intent.payment_failed":
        logger.info(
            "Payment failed for intent %s",
            data_object.get("id"),
        )
    elif event_type and event_type.startswith("account."):
        await _handle_connect_event(event_type, event, data_object)
    else:
        logger.info("Unhandled Stripe event %s", event_type)

    return {"status": "ok"}


async def _handle_checkout_session(session: dict[str, object], event_type: str) -> None:
    metadata = session.get("metadata") if isinstance(session.get("metadata"), dict) else {}
    if not isinstance(metadata, dict):
        metadata = {}
    order_id = metadata.get("order_id") or session.get("client_reference_id")
    payment_intent = session.get("payment_intent")
    checkout_id = session.get("id")
    amount_cents = int(session.get("amount_total") or 0)
    currency = (session.get("currency") or "sek").lower()
    stripe_customer_id = str(session.get("customer")) if session.get("customer") else None

    order = None
    if order_id:
        order = await repositories.get_order(order_id)
        await repositories.mark_order_paid(
            order_id,
            payment_intent=str(payment_intent) if payment_intent else None,
            checkout_id=checkout_id if isinstance(checkout_id, str) else None,
        )

    if order_id:
        await repositories.record_payment(
            order_id=order_id,
            provider="stripe",
            provider_reference=str(payment_intent) if payment_intent else None,
            status="paid",
            amount_cents=amount_cents or int((order or {}).get("amount_cents") or 0),
            currency=currency,
            metadata={"event": event_type},
            payload=session if isinstance(session, dict) else {},
        )

    user_id = metadata.get("user_id") or (order.get("user_id") if order else None)
    course_slug = metadata.get("course_slug")
    if user_id and course_slug:
        await course_entitlements.grant_course_entitlement(
            user_id=str(user_id),
            course_slug=str(course_slug),
            stripe_customer_id=stripe_customer_id,
            payment_intent_id=str(payment_intent) if payment_intent else None,
        )
        course_row = await courses_repo.get_course_by_slug(course_slug)
        if course_row and course_row.get("id"):
            await courses_repo.ensure_course_enrollment(
                str(user_id),
                str(course_row["id"]),
                source="purchase",
            )

    bundle_id = metadata.get("bundle_id")
    if user_id and bundle_id:
        try:
            await course_bundles_service.grant_bundle_entitlements(
                str(bundle_id),
                str(user_id),
                stripe_customer_id=stripe_customer_id,
                payment_intent_id=str(payment_intent) if payment_intent else None,
            )
        except Exception as exc:  # pragma: no cover - defensive logging
            logger.warning("Failed to grant bundle entitlements; bundle=%s error=%s", bundle_id, exc)

    service_slug = metadata.get("service_slug")
    if user_id and service_slug and not order and amount_cents > 0:
        created_order = await repositories.create_order(
            user_id=str(user_id),
            service_id=None,
            course_id=None,
            amount_cents=amount_cents or 0,
            currency=currency,
            order_type="one_off",
            metadata={"service_slug": service_slug, "price_id": metadata.get("price_id")},
            stripe_customer_id=str(session.get("customer")) if session.get("customer") else None,
            stripe_subscription_id=None,
            connected_account_id=None,
            session_id=None,
            session_slot_id=None,
        )
        await repositories.mark_order_paid(
            created_order["id"],
            payment_intent=str(payment_intent) if payment_intent else None,
            checkout_id=checkout_id if isinstance(checkout_id, str) else None,
        )


async def _handle_connect_event(
    event_type: str,
    event_payload: dict[str, object],
    data_object: dict[str, object],
) -> None:
    account_id = (
        data_object.get("id")
        if event_type == "account.updated"
        else event_payload.get("account") or data_object.get("account")
    )
    if not isinstance(account_id, str):
        logger.info("Stripe account event without account id: %s", event_type)
        return

    teacher = await repositories.get_teacher_by_account(account_id)
    if not teacher:
        logger.info("No teacher row for account %s", account_id)
        return

    if not settings.stripe_secret_key:
        logger.warning("Stripe secret key missing; cannot sync account")
        return

    stripe.api_key = settings.stripe_secret_key
    try:
        account = await run_in_threadpool(lambda: stripe.Account.retrieve(account_id))
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        logger.warning("Failed to fetch account %s: %s", account_id, exc)
        return

    charges_enabled = bool(account.get("charges_enabled"))
    payouts_enabled = bool(account.get("payouts_enabled"))
    requirements = account.get("requirements") or {}
    disabled_reason = requirements.get("disabled_reason")
    status_value = "onboarding"
    if charges_enabled and payouts_enabled:
        status_value = "verified"
    elif disabled_reason:
        status_value = "restricted"

    onboarded_at = teacher.get("onboarded_at")
    if charges_enabled and payouts_enabled and not onboarded_at:
        onboarded_at = datetime.now(timezone.utc)

    await repositories.update_teacher_status(
        teacher["profile_id"],
        charges_enabled=charges_enabled,
        payouts_enabled=payouts_enabled,
        requirements_due=requirements,
        status=status_value,
        onboarded_at=onboarded_at,
    )
