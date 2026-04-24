from __future__ import annotations

import logging
from typing import Any, Mapping
from uuid import UUID

import sentry_sdk
import stripe
from fastapi import APIRouter, HTTPException, Request, status
from psycopg.rows import dict_row

from ..db import pool
from ..repositories import membership_support as membership_support_repo
from ..repositories import orders as orders_repo
from ..repositories import payments as payments_repo
from .. import stripe_mode
from ..services import (
    notification_service,
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


class CheckoutOrderResolutionError(RuntimeError):
    pass


class CheckoutOrderValidationError(RuntimeError):
    pass


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

    event_claim: membership_support_repo.PaymentEventClaim | None = None

    try:
        if isinstance(event_id, str) and event_id:
            event_claim = await membership_support_repo.claim_payment_event(event_id)
            if event_claim.completed:
                course_effect_checked = (
                    await _ensure_completed_course_checkout_effect_applied(event)
                )
                if course_effect_checked:
                    logger.info(
                        "Skipping completed Stripe event %s after confirming course checkout side effects",
                        event_id,
                    )
                    return {"status": "ok"}
                membership_effect_checked = (
                    await stripe_webhook_membership_service.ensure_completed_event_effect_applied(
                        event
                    )
                )
                if membership_effect_checked:
                    logger.info(
                        "Skipping completed Stripe event %s after confirming completed side effects",
                        event_id,
                    )
                else:
                    logger.info("Skipping completed Stripe event %s", event_id)
                return {"status": "ok"}
            if event_claim.processing:
                logger.info("Stripe event %s is already being processed", event_id)
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Webhook-bearbetning pågår",
                )

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
                await _handle_checkout_session_completion(
                    data_object,
                    str(event_type),
                    conn=(
                        getattr(event_claim, "_conn", None)
                        if event_claim is not None and event_claim.claimed
                        else None
                    ),
                )
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
                conn=(
                    getattr(event_claim, "_conn", None)
                    if event_claim is not None and event_claim.claimed
                    else None
                ),
            )
        elif event_type and event_type.startswith("account."):
            logger.info("Ignoring inactive Stripe Connect event %s", event_type)
        else:
            logger.info("Unhandled Stripe event %s", event_type)
        if event_claim is not None:
            await membership_support_repo.complete_payment_event(
                event_claim,
                dict(event),
            )
    except stripe_webhook_bundle_service.BundleFulfillmentError as exc:
        _capture_exception(
            str(event_type) if event_type else None,
            str(event_id) if event_id else None,
            exc,
        )
        logger.exception("Stripe bundle webhook fulfillment failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from exc
    except (CheckoutOrderResolutionError, CheckoutOrderValidationError) as exc:
        _capture_exception(
            str(event_type) if event_type else None,
            str(event_id) if event_id else None,
            exc,
        )
        logger.warning("Stripe checkout webhook validation failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - defensive logging
        _capture_exception(
            str(event_type) if event_type else None,
            str(event_id) if event_id else None,
            exc,
        )
        logger.exception("Stripe webhook processing failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Webhook-bearbetningen misslyckades",
        ) from exc
    finally:
        if event_claim is not None:
            await event_claim.release()

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
    *,
    conn: Any | None = None,
) -> None:
    order = await _resolve_checkout_order(session, event_type, conn=conn)

    if order.get("course_id"):
        await _fulfill_course_checkout_order(
            order=order,
            session=session,
            event_type=event_type,
            conn=conn,
        )
        return

    if str(order.get("order_type") or "").strip().lower() == "bundle":
        await _fulfill_bundle_checkout_order(
            order=order,
            session=session,
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
    *,
    conn: Any | None = None,
) -> dict[str, object]:
    metadata = (
        session.get("metadata") if isinstance(session.get("metadata"), dict) else {}
    )
    if not isinstance(metadata, dict):
        metadata = {}
    checkout_id = session.get("id") if isinstance(session.get("id"), str) else None

    if checkout_id:
        order = (
            await _get_checkout_order_by_checkout_id(conn, checkout_id)
            if conn is not None
            else await orders_repo.get_order_by_checkout_id(checkout_id)
        )
        if order:
            return order

    order_id = metadata.get("order_id") or session.get("client_reference_id")

    if not order_id:
        logger.warning(
            "Checkout session missing order_id; checkout=%s event=%s",
            checkout_id,
            event_type,
        )
        raise CheckoutOrderResolutionError("Checkout session saknar orderkoppling")

    try:
        normalized_order_id = str(UUID(str(order_id)))
    except ValueError as exc:
        logger.warning(
            "Checkout session had invalid order_id; checkout=%s event=%s",
            checkout_id,
            event_type,
        )
        raise CheckoutOrderResolutionError("Checkout-sessionens orderkoppling är ogiltig") from exc

    order = (
        await _get_checkout_order_by_id(conn, normalized_order_id)
        if conn is not None
        else await orders_repo.get_order(normalized_order_id)
    )
    if not order:
        logger.warning(
            "Checkout session could not resolve order; order_id=%s event=%s",
            normalized_order_id,
            event_type,
        )
        raise CheckoutOrderResolutionError("Checkout-sessionens order hittades inte")

    order_checkout_id = str(order.get("stripe_checkout_id") or "").strip()
    if checkout_id and order_checkout_id and order_checkout_id != checkout_id:
        logger.warning(
            "Checkout session correlation mismatch; order_id=%s checkout=%s event=%s",
            order_id,
            checkout_id,
            event_type,
        )
        raise CheckoutOrderResolutionError("Checkout-sessionens orderkoppling är ogiltig")
    return order


def _mapping(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _required_text(value: object, detail: str) -> str:
    if isinstance(value, str) and value.strip():
        return value.strip()
    raise CheckoutOrderValidationError(detail)


def _required_uuid_text(value: object, detail: str) -> str:
    if value is None:
        raise CheckoutOrderValidationError(detail)
    raw = str(value).strip()
    if not raw:
        raise CheckoutOrderValidationError(detail)
    try:
        return str(UUID(raw))
    except ValueError as exc:
        raise CheckoutOrderValidationError(detail) from exc


def _required_int(value: object, detail: str) -> int:
    if isinstance(value, bool) or value is None:
        raise CheckoutOrderValidationError(detail)
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise CheckoutOrderValidationError(detail) from exc


def _validate_course_checkout_session(
    *,
    order: Mapping[str, object],
    session: Mapping[str, object],
) -> dict[str, str | int | None]:
    metadata = _mapping(session.get("metadata"))
    order_metadata = _mapping(order.get("metadata"))

    order_id = _required_uuid_text(
        order.get("id"),
        "Checkout-sessionens orderkoppling är ogiltig",
    )
    session_order_id = _required_uuid_text(
        metadata.get("order_id") or session.get("client_reference_id"),
        "Checkout session saknar orderkoppling",
    )
    if session_order_id != order_id:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens orderkoppling matchar inte ordern"
        )

    checkout_id = _required_text(
        session.get("id"),
        "Checkout-session saknar id",
    )
    order_checkout_id = _required_text(
        order.get("stripe_checkout_id"),
        "Ordern saknar checkout-koppling",
    )
    if order_checkout_id != checkout_id:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens id matchar inte ordern"
        )

    order_type = str(order.get("order_type") or "").strip().lower()
    if order_type != "one_off":
        raise CheckoutOrderValidationError("Kursköpets ordertyp är ogiltig")

    if not str(order.get("course_id") or "").strip():
        raise CheckoutOrderValidationError("Ordern saknar kurskoppling")
    if not str(order.get("user_id") or "").strip():
        raise CheckoutOrderValidationError("Ordern saknar användarkoppling")

    checkout_type = _required_text(
        metadata.get("checkout_type"),
        "Checkout-session saknar kurstyp",
    )
    if checkout_type != "course":
        raise CheckoutOrderValidationError("Checkout-sessionens typ är ogiltig")

    session_user_id = _required_uuid_text(
        metadata.get("user_id"),
        "Checkout-session saknar användarkoppling",
    )
    order_user_id = _required_uuid_text(
        order.get("user_id"),
        "Ordern saknar användarkoppling",
    )
    if session_user_id != order_user_id:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens användare matchar inte ordern"
        )

    amount_cents = _required_int(
        session.get("amount_total"),
        "Checkout-session saknar betalbelopp",
    )
    order_amount = _required_int(
        order.get("amount_cents"),
        "Ordern saknar betalbelopp",
    )
    if amount_cents <= 0 or amount_cents != order_amount:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens belopp matchar inte ordern"
        )

    currency = _required_text(
        session.get("currency"),
        "Checkout-session saknar valuta",
    ).lower()
    order_currency = _required_text(
        order.get("currency"),
        "Ordern saknar valuta",
    ).lower()
    if currency != order_currency:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens valuta matchar inte ordern"
        )

    session_price_id = _required_text(
        metadata.get("price_id"),
        "Checkout-session saknar prisreferens",
    )
    order_price_id = _required_text(
        order_metadata.get("price_id"),
        "Ordern saknar prisreferens",
    )
    if session_price_id != order_price_id:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens pris matchar inte ordern"
        )

    payment_intent = _required_text(
        session.get("payment_intent"),
        "Checkout-session saknar betalningsreferens",
    )

    return {
        "order_id": order_id,
        "checkout_id": checkout_id,
        "payment_intent": payment_intent,
        "amount_cents": amount_cents,
        "currency": currency,
        "price_id": session_price_id,
    }


def _validate_bundle_checkout_session(
    *,
    order: Mapping[str, object],
    session: Mapping[str, object],
) -> dict[str, str | int]:
    order_id = _required_uuid_text(
        order.get("id"),
        "Checkout-sessionens orderkoppling är ogiltig",
    )

    checkout_id = _required_text(
        session.get("id"),
        "Checkout-session saknar id",
    )
    order_checkout_id = _required_text(
        order.get("stripe_checkout_id"),
        "Ordern saknar checkout-koppling",
    )
    if order_checkout_id != checkout_id:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens id matchar inte ordern"
        )

    order_type = str(order.get("order_type") or "").strip().lower()
    if order_type != "bundle":
        raise CheckoutOrderValidationError("Paketköpets ordertyp är ogiltig")

    if str(order.get("course_id") or "").strip():
        raise CheckoutOrderValidationError("Paketordern har fel produktkoppling")
    _required_uuid_text(
        order.get("bundle_id"),
        "Ordern saknar paketkoppling",
    )
    _required_uuid_text(
        order.get("user_id"),
        "Ordern saknar användarkoppling",
    )

    amount_cents = _required_int(
        session.get("amount_total"),
        "Checkout-session saknar betalbelopp",
    )
    order_amount = _required_int(
        order.get("amount_cents"),
        "Ordern saknar betalbelopp",
    )
    if amount_cents <= 0 or amount_cents != order_amount:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens belopp matchar inte ordern"
        )

    currency = _required_text(
        session.get("currency"),
        "Checkout-session saknar valuta",
    ).lower()
    order_currency = _required_text(
        order.get("currency"),
        "Ordern saknar valuta",
    ).lower()
    if currency != order_currency:
        raise CheckoutOrderValidationError(
            "Checkout-sessionens valuta matchar inte ordern"
        )

    payment_intent = _required_text(
        session.get("payment_intent"),
        "Checkout-session saknar betalningsreferens",
    )

    return {
        "order_id": order_id,
        "checkout_id": checkout_id,
        "payment_intent": payment_intent,
        "amount_cents": amount_cents,
        "currency": currency,
    }


async def _ensure_completed_course_checkout_effect_applied(event: Mapping[str, Any]) -> bool:
    event_type = event.get("type")
    if event_type not in CHECKOUT_SESSION_COMPLETION_EVENTS:
        return False

    data = event.get("data")
    data_object = data.get("object") if isinstance(data, Mapping) else None
    if not isinstance(data_object, dict):
        raise CheckoutOrderValidationError("Checkout-session saknas i webhook-event")

    if stripe_webhook_membership_service.is_membership_checkout_session(data_object):
        return False

    order = await _resolve_checkout_order(data_object, str(event_type))
    if not order.get("course_id"):
        return False

    await _assert_course_checkout_fulfillment_completed(
        order=order,
        session=data_object,
        repair_missing_enrollment=True,
        event_type=str(event_type),
    )
    return True


async def _assert_course_checkout_fulfillment_completed(
    *,
    order: Mapping[str, object],
    session: Mapping[str, object],
    conn: Any | None = None,
    repair_missing_enrollment: bool = False,
    event_type: str = "course_checkout_reconciliation",
) -> None:
    validated = _validate_course_checkout_session(order=order, session=session)
    if str(order.get("status") or "").strip().lower() != "paid":
        raise RuntimeError("Course checkout order is not paid")

    payment = await payments_repo.get_payment_for_order_by_reference(
        validated["order_id"],
        str(validated["payment_intent"]),
        status="paid",
        conn=conn,
    )
    if payment is None:
        raise RuntimeError("Course checkout payment record is missing")

    enrollment = await stripe_webhook_course_service.assert_purchase_enrollment_exists(
        order=order,
        conn=conn,
        repair_missing_enrollment=repair_missing_enrollment,
        event_type=event_type,
    )
    await _create_course_purchase_notification(
        order=order,
        session=session,
        enrollment=enrollment,
        event_type=event_type,
        conn=conn,
    )


async def _get_checkout_order_by_checkout_id(
    conn: Any,
    checkout_id: str,
) -> dict[str, object] | None:
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            SELECT id,
                   user_id,
                   course_id,
                   bundle_id,
                   order_type,
                   amount_cents,
                   currency,
                   status,
                   stripe_checkout_id,
                   stripe_payment_intent,
                   stripe_subscription_id,
                   stripe_customer_id,
                   metadata,
                   created_at,
                   updated_at
              FROM app.orders
             WHERE stripe_checkout_id = %s
             ORDER BY updated_at DESC
             LIMIT 1
            """,
            (checkout_id,),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def _get_checkout_order_by_id(
    conn: Any,
    order_id: str,
) -> dict[str, object] | None:
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            SELECT id,
                   user_id,
                   course_id,
                   bundle_id,
                   order_type,
                   amount_cents,
                   currency,
                   status,
                   stripe_checkout_id,
                   stripe_payment_intent,
                   stripe_subscription_id,
                   stripe_customer_id,
                   metadata,
                   created_at,
                   updated_at
              FROM app.orders
             WHERE id = %s
             LIMIT 1
            """,
            (order_id,),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def _get_course_checkout_order_for_update(
    conn: Any,
    order_id: str,
) -> dict[str, object]:
    async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            SELECT id,
                   user_id,
                   course_id,
                   bundle_id,
                   order_type,
                   amount_cents,
                   currency,
                   status,
                   stripe_checkout_id,
                   stripe_payment_intent,
                   stripe_subscription_id,
                   stripe_customer_id,
                   metadata,
                   created_at,
                   updated_at
              FROM app.orders
             WHERE id = %s
             FOR UPDATE
            """,
            (order_id,),
        )
        row = await cur.fetchone()
    if row is None:
        raise CheckoutOrderValidationError("Checkout-sessionens order hittades inte")
    return dict(row)


async def _fulfill_course_checkout_order(
    *,
    order: dict[str, object],
    session: dict[str, object],
    event_type: str,
    conn: Any | None = None,
) -> None:
    validated = _validate_course_checkout_session(order=order, session=session)

    async def _execute(active_conn: Any) -> None:
        try:
            locked_order = await _get_course_checkout_order_for_update(
                active_conn,
                str(validated["order_id"]),
            )
            locked_validated = _validate_course_checkout_session(
                order=locked_order,
                session=session,
            )

            if str(locked_order.get("status") or "").strip().lower() == "paid":
                await _assert_course_checkout_fulfillment_completed(
                    order=locked_order,
                    session=session,
                    conn=active_conn,
                    repair_missing_enrollment=True,
                    event_type=event_type,
                )
                await active_conn.commit()
                return

            existing_payment = await payments_repo.get_payment_for_order_by_reference(
                locked_validated["order_id"],
                str(locked_validated["payment_intent"]),
                status="paid",
                conn=active_conn,
            )
            if existing_payment is not None:
                raise RuntimeError("Course checkout has payment without full fulfillment")

            updated_order = await payments_repo.mark_order_paid(
                locked_validated["order_id"],
                payment_intent=str(locked_validated["payment_intent"]),
                checkout_id=str(locked_validated["checkout_id"]),
                subscription_id=(
                    str(session.get("subscription")) if session.get("subscription") else None
                ),
                customer_id=str(session.get("customer")) if session.get("customer") else None,
                conn=active_conn,
            )
            if updated_order is None:
                raise RuntimeError("Course checkout order was not marked paid")

            await payments_repo.record_payment(
                order_id=locked_validated["order_id"],
                provider="stripe",
                provider_reference=str(locked_validated["payment_intent"]),
                status="paid",
                amount_cents=int(locked_validated["amount_cents"]),
                currency=str(locked_validated["currency"]),
                metadata={
                    "event": event_type,
                    "checkout_id": locked_validated["checkout_id"],
                    "price_id": locked_validated["price_id"],
                },
                payload=session if isinstance(session, dict) else {},
                conn=active_conn,
            )

            enrollment = await stripe_webhook_course_service.handle_paid_checkout_order(
                order=updated_order,
                event_type=event_type,
                conn=active_conn,
            )
            await _create_course_purchase_notification(
                order=updated_order,
                session=session,
                enrollment=enrollment,
                event_type=event_type,
                conn=active_conn,
            )
            await active_conn.commit()
        except Exception:
            await active_conn.rollback()
            raise

    if conn is not None:
        await _execute(conn)
        return

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        await _execute(active_conn)


async def _create_course_purchase_notification(
    *,
    order: Mapping[str, object],
    session: Mapping[str, object],
    enrollment: Mapping[str, object],
    event_type: str,
    conn: Any | None = None,
) -> None:
    order_id = str(order.get("id") or "").strip()
    user_id = str(order.get("user_id") or "").strip()
    course_id = str(order.get("course_id") or "").strip()
    if not order_id or not user_id or not course_id:
        raise CheckoutOrderValidationError("Ordern saknar notifikationsunderlag")

    await notification_service.create_notification(
        user_id,
        "stripe_course_purchase_fulfilled",
        {
            "order_id": order_id,
            "course_id": course_id,
            "enrollment_id": str(enrollment.get("id") or ""),
            "checkout_id": str(session.get("id") or ""),
            "event_type": event_type,
        },
        f"stripe_course_purchase_fulfilled:{order_id}",
        conn=conn,
    )


async def _fulfill_bundle_checkout_order(
    *,
    order: dict[str, object],
    session: dict[str, object],
    event_type: str,
) -> None:
    validated = _validate_bundle_checkout_session(order=order, session=session)

    if str(order.get("status") or "").strip().lower() != "paid":
        settled_order = await _settle_checkout_order(
            order=order,
            session=session,
            event_type=event_type,
            validated=validated,
        )
        if settled_order:
            order = settled_order

    await stripe_webhook_bundle_service.handle_paid_checkout_order(
        order=order,
        event_type=event_type,
    )


async def _settle_checkout_order(
    *,
    order: dict[str, object],
    session: dict[str, object],
    event_type: str,
    validated: Mapping[str, str | int] | None = None,
) -> dict[str, object] | None:
    payment_intent = (
        validated.get("payment_intent")
        if validated is not None
        else session.get("payment_intent")
    )
    checkout_id = (
        validated.get("checkout_id")
        if validated is not None
        else session.get("id")
    )
    amount_cents = (
        int(validated.get("amount_cents"))
        if validated is not None
        else int(session.get("amount_total") or 0)
    )
    currency = (
        str(validated.get("currency"))
        if validated is not None
        else str(session.get("currency") or "sek").lower()
    )

    updated_order = await payments_repo.mark_order_paid(
        order["id"],
        payment_intent=str(payment_intent) if payment_intent else None,
        checkout_id=checkout_id if isinstance(checkout_id, str) else None,
        subscription_id=(
            str(session.get("subscription")) if session.get("subscription") else None
        ),
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

    return updated_order
