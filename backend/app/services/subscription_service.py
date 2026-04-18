from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Mapping

import stripe
from starlette.concurrency import run_in_threadpool

from .. import stripe_mode
from ..config import settings
from ..db import pool
from ..repositories import memberships as memberships_repo
from ..repositories import membership_support as membership_support_repo
from ..repositories import orders as orders_repo
from ..repositories import payments as payments_repo
from ..repositories import stripe_customers as stripe_customers_repo
from ..schemas.billing import SubscriptionCheckoutResponse, SubscriptionInterval
from ..services.onboarding_state import sync_onboarding_state
from ..utils import membership_status

logger = logging.getLogger(__name__)

RETURN_PATH = "checkout/return?session_id={CHECKOUT_SESSION_ID}"
ORDINARY_MEMBERSHIP_TRIAL_DAYS = 14


class SubscriptionError(Exception):
    status_code = 400

    def __init__(self, detail: str, status_code: int | None = None) -> None:
        super().__init__(detail)
        if status_code is not None:
            self.status_code = status_code
        self.detail = detail


class SubscriptionConfigError(SubscriptionError):
    def __init__(self, detail: str) -> None:
        super().__init__(detail, status_code=503)


def is_membership_checkout_session(payload: Mapping[str, Any]) -> bool:
    metadata = payload.get("metadata")
    checkout_type = None
    if isinstance(metadata, Mapping):
        checkout_type = metadata.get("checkout_type")
    return str(checkout_type or "").strip().lower() == "membership" or str(
        payload.get("mode") or ""
    ).strip().lower() == "subscription"


def is_membership_event_type(event_type: str | None) -> bool:
    return str(event_type or "") in {
        "checkout.session.completed",
        "checkout.session.async_payment_succeeded",
        "customer.subscription.created",
        "customer.subscription.updated",
        "customer.subscription.deleted",
        "invoice.payment_succeeded",
        "invoice.payment_failed",
    }


async def create_subscription_checkout(
    user: Mapping[str, Any],
    interval: SubscriptionInterval,
) -> SubscriptionCheckoutResponse:
    try:
        stripe_context = stripe_mode.resolve_stripe_context()
        price_config = stripe_mode.resolve_membership_price(interval, stripe_context)
        price = await stripe_mode.ensure_price_accessible(price_config, stripe_context)
    except stripe_mode.StripeConfigurationError as exc:
        raise SubscriptionConfigError(str(exc)) from exc

    stripe.api_key = stripe_context.secret_key
    user_id = str(user["id"])
    customer_id = await _get_or_create_customer(user)
    amount_cents, currency = _extract_amount_and_currency(price)

    metadata: dict[str, Any] = {
        "checkout_type": "membership",
        "source": "purchase",
        "user_id": user_id,
        "interval": interval.value,
        "price_id": price_config.price_id,
    }
    order = await orders_repo.create_order(
        user_id=user_id,
        course_id=None,
        bundle_id=None,
        amount_cents=amount_cents,
        currency=currency,
        order_type="subscription",
        metadata=metadata,
        stripe_customer_id=customer_id,
        stripe_subscription_id=None,
    )
    metadata["order_id"] = str(order["id"])

    return_url = _build_frontend_url(RETURN_PATH)

    def _create_session() -> dict[str, Any]:
        return stripe.checkout.Session.create(
            mode="subscription",
            customer=customer_id,
            line_items=[{"price": price_config.price_id, "quantity": 1}],
            ui_mode="embedded",
            return_url=return_url,
            locale="sv",
            metadata=metadata,
            payment_method_collection="always",
            subscription_data={
                "metadata": metadata,
                "trial_period_days": ORDINARY_MEMBERSHIP_TRIAL_DAYS,
                "trial_settings": {
                    "end_behavior": {"missing_payment_method": "cancel"},
                },
            },
        )

    try:
        session = await run_in_threadpool(_create_session)
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        if getattr(exc, "code", "") == "resource_missing":
            raise SubscriptionConfigError(
                _price_missing_message(price_config, stripe_context)
            ) from exc
        raise SubscriptionError(_format_invalid_request(exc), status_code=502) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError("Stripe-fel vid prenumerationssession", status_code=502) from exc

    client_secret = session.get("client_secret")
    session_id = session.get("id")
    if not isinstance(client_secret, str) or not client_secret:
        raise SubscriptionError("Stripe-session saknar klienthemlighet", status_code=502)
    if not isinstance(session_id, str) or not session_id:
        raise SubscriptionError("Stripe-session saknar id", status_code=502)

    await orders_repo.set_order_checkout_reference(
        order_id=order["id"],
        checkout_id=session_id,
        payment_intent=_as_string(session.get("payment_intent")),
        subscription_id=_as_string(session.get("subscription")),
        customer_id=customer_id,
    )
    await membership_support_repo.insert_billing_log(
        user_id=user_id,
        step="create_subscription_session",
        info={
            "interval": interval.value,
            "price_id": price_config.price_id,
            "session_id": session_id,
            "order_id": str(order["id"]),
        },
    )

    return SubscriptionCheckoutResponse(
        client_secret=client_secret,
        session_id=session_id,
        order_id=str(order["id"]),
    )


async def cancel_subscription_intent(
    user: Mapping[str, Any],
    *,
    subscription_id: str | None = None,
) -> dict[str, Any]:
    try:
        stripe_context = stripe_mode.resolve_stripe_context()
    except stripe_mode.StripeConfigurationError as exc:
        raise SubscriptionConfigError(str(exc)) from exc

    user_id = str(user["id"])
    resolved_subscription_id = await _resolve_membership_subscription_id(
        user_id,
        requested_subscription_id=subscription_id,
    )
    stripe.api_key = stripe_context.secret_key

    def _submit_cancel_intent() -> dict[str, Any]:
        return stripe.Subscription.modify(  # type: ignore[attr-defined]
            resolved_subscription_id,
            cancel_at_period_end=True,
        )

    try:
        updated = await run_in_threadpool(_submit_cancel_intent)
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError(
            "Stripe kunde inte registrera avsiktsavbokningen",
            status_code=400,
        ) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError("Stripe-fel vid avbokningsintention", status_code=502) from exc

    current_period_end = _to_datetime(updated.get("current_period_end"))
    cancel_at_period_end = bool(updated.get("cancel_at_period_end"))
    await membership_support_repo.insert_billing_log(
        user_id=user_id,
        step="cancel_subscription_intent_submitted",
        info={
            "subscription_id": resolved_subscription_id,
            "cancel_at_period_end": cancel_at_period_end,
            "current_period_end": current_period_end.isoformat()
            if current_period_end
            else None,
        },
    )
    return {
        "ok": True,
        "subscription_id": resolved_subscription_id,
        "cancel_at_period_end": cancel_at_period_end,
        "message": "Avsiktsavbokningen är skickad. Medlemskapsstatus ändras först efter betalningsbekräftelse.",
    }


async def apply_valid_membership_withdrawal(
    user: Mapping[str, Any],
    *,
    subscription_id: str | None = None,
    payment_intent_id: str | None = None,
) -> dict[str, Any]:
    return await _apply_membership_refund_resolution(
        user,
        resolution_kind="withdrawal",
        subscription_id=subscription_id,
        payment_intent_id=payment_intent_id,
    )


async def apply_membership_remedy(
    user: Mapping[str, Any],
    *,
    subscription_id: str | None = None,
    payment_intent_id: str | None = None,
) -> dict[str, Any]:
    return await _apply_membership_refund_resolution(
        user,
        resolution_kind="remedy",
        subscription_id=subscription_id,
        payment_intent_id=payment_intent_id,
    )


async def _apply_membership_refund_resolution(
    user: Mapping[str, Any],
    *,
    resolution_kind: str,
    subscription_id: str | None,
    payment_intent_id: str | None,
) -> dict[str, Any]:
    try:
        stripe_context = stripe_mode.resolve_stripe_context()
    except stripe_mode.StripeConfigurationError as exc:
        raise SubscriptionConfigError(str(exc)) from exc

    user_id = str(user["id"])
    order = await _resolve_membership_purchase_order_for_resolution(
        user_id,
        requested_subscription_id=subscription_id,
    )
    resolved_subscription_id = _as_string(order.get("stripe_subscription_id"))
    if not resolved_subscription_id:
        raise SubscriptionError(
            "Prenumerationen saknar prenumerations-id i köpunderlaget",
            status_code=400,
        )
    resolved_payment_intent = await _resolve_membership_refund_payment_intent(
        order,
        requested_payment_intent=payment_intent_id,
    )
    stripe.api_key = stripe_context.secret_key

    def _cancel_now() -> dict[str, Any]:
        return stripe.Subscription.cancel(  # type: ignore[attr-defined]
            resolved_subscription_id
        )

    def _create_refund() -> dict[str, Any]:
        return stripe.Refund.create(
            payment_intent=resolved_payment_intent,
            metadata={
                "resolution_kind": resolution_kind,
                "order_id": str(order["id"]),
                "checkout_type": "membership",
                "user_id": user_id,
            },
        )

    try:
        await run_in_threadpool(_cancel_now)
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError(
            "Stripe kunde inte stoppa framtida dragningar för medlemskapet",
            status_code=400,
        ) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError(
            "Stripe-fel vid stopp av framtida medlemskapsdragningar",
            status_code=502,
        ) from exc

    try:
        await run_in_threadpool(_create_refund)
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError(
            "Stripe kunde inte skapa medlemskapsåterbetalningen",
            status_code=400,
        ) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError(
            "Stripe-fel vid medlemskapsåterbetalning",
            status_code=502,
        ) from exc

    now = datetime.now(timezone.utc)
    membership, _ = await _write_payment_membership_state(
        user_id,
        status="expired",
        effective_at=None,
        expires_at=now,
        canceled_at=now,
        ended_at=now,
    )
    log_info = {
        "order_id": str(order["id"]),
        "subscription_id": resolved_subscription_id,
        "payment_intent_id": resolved_payment_intent,
    }
    await membership_support_repo.insert_billing_log(
        user_id=user_id,
        step=f"membership_{resolution_kind}_applied",
        info=log_info,
    )
    await sync_onboarding_state(user_id)
    return {
        "ok": True,
        "membership": membership,
        "order_id": str(order["id"]),
        "subscription_id": resolved_subscription_id,
        "payment_intent_id": resolved_payment_intent,
        "resolution_kind": resolution_kind,
    }


async def handle_webhook(payload: bytes, signature: str | None) -> None:
    try:
        stripe_context = stripe_mode.resolve_stripe_context()
        secret, _ = stripe_mode.resolve_webhook_secret("billing", stripe_context)
    except stripe_mode.StripeConfigurationError as exc:
        raise SubscriptionConfigError(str(exc)) from exc
    if not signature:
        raise SubscriptionError("Stripe-signatur saknas")

    try:
        event = stripe.Webhook.construct_event(
            payload=payload.decode("utf-8"),
            sig_header=signature,
            secret=secret,
        )
    except ValueError as exc:
        raise SubscriptionError("Ogiltig Stripe-payload") from exc
    except stripe.error.SignatureVerificationError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError("Ogiltig Stripe-signatur") from exc

    await process_event(event)


async def process_event(event: Mapping[str, Any]) -> None:
    event_type = str(event.get("type") or "")
    data_object = event.get("data", {}).get("object", {})
    if not isinstance(data_object, Mapping):
        logger.debug("Stripe membership event missing object payload: %s", event_type)
        return

    if event_type in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}:
        await _handle_membership_checkout_session(data_object)
    elif event_type == "customer.subscription.created":
        await _handle_subscription_created(data_object)
    elif event_type == "customer.subscription.updated":
        await _handle_subscription_updated(data_object)
    elif event_type == "customer.subscription.deleted":
        await _handle_subscription_deleted(data_object)
    elif event_type == "invoice.payment_succeeded":
        await _handle_invoice_payment_succeeded(data_object)
    elif event_type == "invoice.payment_failed":
        await _handle_invoice_payment_failed(data_object)
    else:
        logger.debug("Unhandled membership event: %s", event_type)


async def ensure_completed_event_effect_applied(event: Mapping[str, Any]) -> bool:
    event_type = str(event.get("type") or "")
    data_object = event.get("data", {}).get("object", {})
    if not isinstance(data_object, Mapping):
        return False

    if event_type in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}:
        if is_membership_checkout_session(data_object):
            await _ensure_membership_checkout_session_applied(data_object)
            return True
    return False


async def _handle_membership_checkout_session(payload: Mapping[str, Any]) -> None:
    metadata = _metadata_dict(payload)
    order = await _resolve_membership_order(
        metadata=metadata,
        checkout_id=_as_string(payload.get("id")),
        payment_intent_id=_as_string(payload.get("payment_intent")),
    )
    _validate_membership_session_user(metadata=metadata, order=order)
    settlement = await _settle_membership_checkout_session(order=order, payload=payload)
    logger.info(
        "membership checkout settlement applied for user %s from checkout session %s",
        order["user_id"],
        _as_string(payload.get("id")),
        extra={"settlement": settlement},
    )


async def _ensure_membership_checkout_session_applied(
    payload: Mapping[str, Any],
) -> None:
    metadata = _metadata_dict(payload)
    order = await _resolve_membership_order(
        metadata=metadata,
        checkout_id=_as_string(payload.get("id")),
        payment_intent_id=_as_string(payload.get("payment_intent")),
    )
    _validate_membership_session_user(metadata=metadata, order=order)

    settlement = await _settle_membership_checkout_session(order=order, payload=payload)
    if (
        not settlement["order_marked_paid"]
        and not settlement["payment_recorded"]
        and not settlement["membership_activated"]
    ):
        logger.info(
            "membership checkout settlement already complete for user %s",
            order["user_id"],
        )
        return

    logger.warning(
        "Completed Stripe membership checkout event was missing canonical side effects; "
        "repaired settlement for user %s",
        order["user_id"],
    )


async def _settle_membership_checkout_session(
    *,
    order: Mapping[str, Any],
    payload: Mapping[str, Any],
) -> dict[str, bool]:
    checkout_id = _as_string(payload.get("id"))
    if not checkout_id:
        raise SubscriptionError(
            "Medlemskapsbekräftelsen saknar checkout-session",
            status_code=500,
        )

    payment_intent_id = _as_string(payload.get("payment_intent"))
    subscription_id = _as_string(payload.get("subscription"))
    customer_id = _as_string(payload.get("customer"))
    payment_reference = payment_intent_id or checkout_id
    user_id = str(order["user_id"])
    order_id = str(order["id"])
    effective_at = _to_datetime(payload.get("created")) or datetime.now(timezone.utc)

    order_marked_paid = False
    payment_recorded = False
    membership_activated = False

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.transaction():
            referenced_order = dict(order)
            if _order_checkout_reference_update_required(
                referenced_order,
                checkout_id=checkout_id,
                payment_intent_id=payment_intent_id,
                subscription_id=subscription_id,
                customer_id=customer_id,
            ):
                updated_order = await orders_repo.set_order_checkout_reference(
                    order_id=order_id,
                    checkout_id=checkout_id,
                    payment_intent=payment_intent_id,
                    subscription_id=subscription_id,
                    customer_id=customer_id,
                    conn=conn,
                )
                if updated_order is None:
                    raise SubscriptionError(
                        "Medlemskapsbekräftelsen kunde inte uppdatera beställningen",
                        status_code=500,
                    )
                referenced_order = updated_order

            settled_order = referenced_order
            if str(referenced_order.get("status") or "").lower() != "paid":
                settled_order = await payments_repo.mark_order_paid(
                    order_id,
                    payment_intent=payment_intent_id,
                    checkout_id=checkout_id,
                    subscription_id=subscription_id,
                    customer_id=customer_id,
                    conn=conn,
                )
                if settled_order is None:
                    raise SubscriptionError(
                        "Medlemskapsbekräftelsen kunde inte markera beställningen som betald",
                        status_code=500,
                    )
                order_marked_paid = True

            existing_payment = await payments_repo.get_payment_for_order_by_reference(
                order_id,
                payment_reference,
                status="paid",
                conn=conn,
            )
            if existing_payment is None:
                await payments_repo.record_payment(
                    order_id=order_id,
                    provider="stripe",
                    provider_reference=payment_reference,
                    status="paid",
                    amount_cents=int(
                        payload.get("amount_total")
                        or settled_order.get("amount_cents")
                        or 0
                    ),
                    currency=str(
                        payload.get("currency")
                        or settled_order.get("currency")
                        or "sek"
                    ).lower(),
                    metadata={
                        "event": "checkout.session.completed",
                        "checkout_id": checkout_id,
                    },
                    payload=dict(payload),
                    conn=conn,
                )
                payment_recorded = True

            existing_membership = await memberships_repo.get_membership(
                user_id,
                conn=conn,
            )
            if not membership_status.is_membership_row_active(existing_membership):
                await memberships_repo.upsert_membership_record(
                    user_id,
                    status="active",
                    effective_at=effective_at,
                    expires_at=None,
                    canceled_at=None,
                    ended_at=None,
                    source="purchase",
                    conn=conn,
                )
                membership_activated = True

            if order_marked_paid or payment_recorded or membership_activated:
                await membership_support_repo.insert_billing_log(
                    user_id=user_id,
                    step="membership_checkout_completed",
                    info={
                        "order_id": order_id,
                        "session_id": checkout_id,
                        "subscription_id": subscription_id,
                        "order_marked_paid": order_marked_paid,
                        "payment_recorded": payment_recorded,
                        "membership_activated": membership_activated,
                    },
                    conn=conn,
                )

    if order_marked_paid or payment_recorded or membership_activated:
        await sync_onboarding_state(user_id)

    return {
        "order_marked_paid": order_marked_paid,
        "payment_recorded": payment_recorded,
        "membership_activated": membership_activated,
    }


def _order_checkout_reference_update_required(
    order: Mapping[str, Any],
    *,
    checkout_id: str,
    payment_intent_id: str | None,
    subscription_id: str | None,
    customer_id: str | None,
) -> bool:
    expected = {
        "stripe_checkout_id": checkout_id,
        "stripe_payment_intent": payment_intent_id,
        "stripe_subscription_id": subscription_id,
        "stripe_customer_id": customer_id,
    }
    for field, value in expected.items():
        if value is not None and _as_string(order.get(field)) != value:
            return True
    return False


async def _handle_subscription_created(payload: Mapping[str, Any]) -> None:
    order = await _sync_membership_order_references(payload)
    await membership_support_repo.insert_billing_log(
        user_id=str(order["user_id"]),
        step="membership_subscription_created",
        info={
            "order_id": str(order["id"]),
            "subscription_id": _as_string(payload.get("id")),
        },
    )
    if _subscription_is_trialing(payload):
        await _apply_membership_state(
            order,
            status="active",
            effective_at=_to_datetime(payload.get("trial_start"))
            or _to_datetime(payload.get("current_period_start")),
            expires_at=_subscription_expires_at(payload),
            canceled_at=None,
            ended_at=None,
            step="membership_subscription_trial_started",
            info={
                "order_id": str(order["id"]),
                "subscription_id": _as_string(payload.get("id")),
                "trial_end": _to_datetime(payload.get("trial_end")).isoformat()
                if _to_datetime(payload.get("trial_end"))
                else None,
            },
        )


async def _handle_subscription_updated(payload: Mapping[str, Any]) -> None:
    order = await _sync_membership_order_references(payload)
    canonical_status = _canonical_status_from_subscription_payload(payload)
    if (
        canonical_status == "active"
        and str(order.get("status") or "").lower() != "paid"
        and not _subscription_is_trialing(payload)
    ):
        return

    now = datetime.now(timezone.utc)
    expires_at = _subscription_expires_at(payload)
    canceled_at = _subscription_canceled_at(payload)
    ended_at = _subscription_ended_at(payload)

    await _apply_membership_state(
        order,
        status=canonical_status,
        effective_at=_to_datetime(payload.get("current_period_start")),
        expires_at=expires_at,
        canceled_at=canceled_at if canonical_status == "canceled" else None,
        ended_at=ended_at if canonical_status == "expired" else None,
        step="membership_subscription_updated",
        info={
            "order_id": str(order["id"]),
            "subscription_id": _as_string(payload.get("id")),
            "canonical_status": canonical_status,
            "observed_at": now.isoformat(),
        },
    )


async def _handle_subscription_deleted(payload: Mapping[str, Any]) -> None:
    order = await _sync_membership_order_references(payload)
    now = datetime.now(timezone.utc)
    await _apply_membership_state(
        order,
        status="expired",
        effective_at=_to_datetime(payload.get("current_period_start")),
        expires_at=_subscription_expires_at(payload) or now,
        canceled_at=_subscription_canceled_at(payload) or now,
        ended_at=_subscription_ended_at(payload) or now,
        step="membership_subscription_deleted",
        info={
            "order_id": str(order["id"]),
            "subscription_id": _as_string(payload.get("id")),
            "canonical_status": "expired",
        },
    )


async def _handle_invoice_payment_succeeded(payload: Mapping[str, Any]) -> None:
    order = await _resolve_membership_order_from_invoice(payload)
    subscription_id = _as_string(payload.get("subscription"))
    customer_id = _as_string(payload.get("customer"))
    payment_intent_id = _as_string(payload.get("payment_intent"))

    await orders_repo.set_order_checkout_reference(
        order_id=order["id"],
        checkout_id=None,
        payment_intent=payment_intent_id,
        subscription_id=subscription_id,
        customer_id=customer_id,
    )
    settled_order = await payments_repo.mark_order_paid(
        order["id"],
        payment_intent=payment_intent_id,
        checkout_id=None,
        subscription_id=subscription_id,
        customer_id=customer_id,
    )
    settled_order = settled_order or order

    await payments_repo.record_payment(
        order_id=order["id"],
        provider="stripe",
        provider_reference=payment_intent_id or _as_string(payload.get("id")),
        status="paid",
        amount_cents=int(payload.get("amount_paid") or payload.get("amount_due") or settled_order.get("amount_cents") or 0),
        currency=str(payload.get("currency") or settled_order.get("currency") or "sek").lower(),
        metadata={
            "event": "invoice.payment_succeeded",
            "invoice_id": _as_string(payload.get("id")),
        },
        payload=dict(payload),
    )

    period = _extract_period(payload)
    await _apply_membership_state(
        settled_order,
        status="active",
        effective_at=period.get("start"),
        expires_at=period.get("end"),
        canceled_at=None,
        ended_at=None,
        step="membership_invoice_payment_succeeded",
        info={
            "order_id": str(order["id"]),
            "invoice_id": _as_string(payload.get("id")),
            "payment_intent": payment_intent_id,
        },
    )


async def _handle_invoice_payment_failed(payload: Mapping[str, Any]) -> None:
    order = await _resolve_membership_order_from_invoice(payload)
    subscription_id = _as_string(payload.get("subscription"))
    customer_id = _as_string(payload.get("customer"))
    payment_intent_id = _as_string(payload.get("payment_intent"))

    await orders_repo.set_order_checkout_reference(
        order_id=order["id"],
        checkout_id=None,
        payment_intent=payment_intent_id,
        subscription_id=subscription_id,
        customer_id=customer_id,
    )
    await payments_repo.record_payment(
        order_id=order["id"],
        provider="stripe",
        provider_reference=payment_intent_id or _as_string(payload.get("id")),
        status="failed",
        amount_cents=int(payload.get("amount_due") or payload.get("amount_remaining") or order.get("amount_cents") or 0),
        currency=str(payload.get("currency") or order.get("currency") or "sek").lower(),
        metadata={
            "event": "invoice.payment_failed",
            "invoice_id": _as_string(payload.get("id")),
        },
        payload=dict(payload),
    )

    current_membership = await memberships_repo.get_membership(str(order["user_id"]))
    await _apply_membership_state(
        order,
        status="past_due",
        effective_at=current_membership.get("effective_at") if current_membership else None,
        expires_at=current_membership.get("expires_at") if current_membership else None,
        canceled_at=current_membership.get("canceled_at") if current_membership else None,
        ended_at=None,
        step="membership_invoice_payment_failed",
        info={
            "order_id": str(order["id"]),
            "invoice_id": _as_string(payload.get("id")),
            "payment_intent": payment_intent_id,
        },
    )


def _extract_amount_and_currency(price: Mapping[str, Any]) -> tuple[int, str]:
    amount_cents = int(price.get("unit_amount") or 0)
    currency = str(price.get("currency") or "sek").lower()
    if amount_cents <= 0:
        raise SubscriptionError("Stripe-priset saknar belopp", status_code=400)
    return amount_cents, currency


def _price_missing_message(
    price_config: stripe_mode.MembershipPriceConfig,
    context: stripe_mode.StripeContext,
) -> str:
    return (
        f"{price_config.env_var} ({price_config.price_id}) är inte tillgängligt i Stripe "
        f"{context.mode.value}-läge för {context.secret_source}"
    )


def _format_invalid_request(exc: stripe.error.InvalidRequestError) -> str:  # type: ignore[attr-defined]
    param = getattr(exc, "param", None)
    if param:
        return f"Stripe-betalningen kunde inte startas. Kontrollera parametern {param}."
    return "Stripe-betalningen kunde inte startas."


def _build_frontend_url(path: str) -> str:
    base = settings.frontend_base_url or "http://localhost:3000"
    base = base.rstrip("/")
    normalized_path = path.lstrip("/")
    return f"{base}/{normalized_path}"


async def _get_or_create_customer(user: Mapping[str, Any]) -> str:
    user_id = str(user["id"])
    customer_id = await stripe_customers_repo.get_customer_id_for_user(user_id)
    if customer_id:
        return customer_id

    def _create_customer() -> dict[str, Any]:
        return stripe.Customer.create(
            email=user.get("email"),
            name=user.get("display_name"),
            metadata={"user_id": user_id},
        )

    customer = await run_in_threadpool(_create_customer)
    customer_id = customer.get("id")
    if not isinstance(customer_id, str):
        raise SubscriptionError("Kunde inte skapa Stripe-kund", status_code=502)
    await stripe_customers_repo.upsert_customer(user_id, customer_id)
    return customer_id


async def _resolve_membership_subscription_id(
    user_id: str,
    *,
    requested_subscription_id: str | None = None,
) -> str:
    membership = await memberships_repo.get_membership(user_id)
    if not membership:
        raise SubscriptionError("Ingen aktiv prenumeration hittades", status_code=404)

    user_orders = await orders_repo.list_user_orders(user_id, limit=200)
    membership_subscription_id = None
    for order in user_orders:
        if str(order.get("order_type") or "").lower() != "subscription":
            continue
        subscription_id = _as_string(order.get("stripe_subscription_id"))
        if subscription_id:
            membership_subscription_id = subscription_id
            break
    if not membership_subscription_id:
        raise SubscriptionError(
            "Prenumerationen saknar prenumerations-id i köpunderlaget",
            status_code=400,
        )

    if requested_subscription_id and requested_subscription_id != membership_subscription_id:
        raise SubscriptionError(
            "Angivet prenumerations-id matchar inte ditt konto",
            status_code=403,
        )
    return str(membership_subscription_id)


async def _resolve_membership_purchase_order_for_resolution(
    user_id: str,
    *,
    requested_subscription_id: str | None = None,
) -> dict[str, Any]:
    user_orders = await orders_repo.list_user_orders(user_id, limit=200)
    subscription_orders = [
        order
        for order in user_orders
        if str(order.get("order_type") or "").lower() == "subscription"
    ]
    if not subscription_orders:
        raise SubscriptionError(
            "Ingen medlemskapsbeställning hittades",
            status_code=404,
        )

    if requested_subscription_id:
        for order in subscription_orders:
            if _as_string(order.get("stripe_subscription_id")) == requested_subscription_id:
                return order
        raise SubscriptionError(
            "Angivet prenumerations-id matchar inte ditt konto",
            status_code=403,
        )

    for order in subscription_orders:
        if _as_string(order.get("stripe_subscription_id")):
            return order

    raise SubscriptionError(
        "Prenumerationen saknar prenumerations-id i köpunderlaget",
        status_code=400,
    )


async def _resolve_membership_refund_payment_intent(
    order: Mapping[str, Any],
    *,
    requested_payment_intent: str | None = None,
) -> str:
    order_id = str(order["id"])
    if requested_payment_intent:
        payment = await payments_repo.get_payment_for_order_by_reference(
            order_id,
            requested_payment_intent,
            status="paid",
        )
        if not payment:
            raise SubscriptionError(
                "Angiven betalningsreferens tillhör inte medlemskapsköpet",
                status_code=403,
            )
        return requested_payment_intent

    latest_paid_payment = await payments_repo.get_latest_payment_for_order(
        order_id,
        status="paid",
    )
    provider_reference = _as_string((latest_paid_payment or {}).get("provider_reference"))
    if provider_reference:
        return provider_reference

    fallback_payment_intent = _as_string(order.get("stripe_payment_intent"))
    if fallback_payment_intent:
        return fallback_payment_intent

    raise SubscriptionError(
        "Kunde inte fastställa vilken medlemskapsbetalning som ska återbetalas",
        status_code=400,
    )


async def _resolve_membership_order(
    *,
    metadata: Mapping[str, Any] | None = None,
    subscription_id: str | None = None,
    checkout_id: str | None = None,
    payment_intent_id: str | None = None,
) -> dict[str, Any]:
    order_id = None
    if isinstance(metadata, Mapping):
        raw_order_id = metadata.get("order_id")
        if isinstance(raw_order_id, str) and raw_order_id.strip():
            order_id = raw_order_id.strip()

    order = None
    if order_id:
        order = await orders_repo.get_order(order_id)
    if not order and subscription_id:
        order = await orders_repo.get_order_by_subscription_id(subscription_id)
    if not order and checkout_id:
        order = await orders_repo.get_order_by_checkout_id(checkout_id)
    if not order and payment_intent_id:
        order = await orders_repo.get_order_by_payment_intent(payment_intent_id)
    if not order:
        raise SubscriptionError(
            "Medlemskapsbekräftelsen kunde inte hitta beställningen",
            status_code=500,
        )
    return order


def _validate_membership_session_user(
    *,
    metadata: Mapping[str, Any],
    order: Mapping[str, Any],
) -> None:
    metadata_user_id = _as_string(metadata.get("user_id"))
    order_user_id = _as_string(order.get("user_id"))
    if not order_user_id:
        raise SubscriptionError(
            "Medlemskapsbekräftelsen saknar användarkoppling",
            status_code=500,
        )
    if metadata_user_id and metadata_user_id != order_user_id:
        raise SubscriptionError(
            "Medlemskapsbekräftelsen matchar inte beställningens användare",
            status_code=500,
        )


async def _resolve_membership_order_from_invoice(
    payload: Mapping[str, Any],
) -> dict[str, Any]:
    return await _resolve_membership_order(
        metadata=_metadata_dict(payload),
        subscription_id=_as_string(payload.get("subscription")),
        payment_intent_id=_as_string(payload.get("payment_intent")),
    )


async def _sync_membership_order_references(
    payload: Mapping[str, Any],
) -> dict[str, Any]:
    order = await _resolve_membership_order(
        metadata=_metadata_dict(payload),
        subscription_id=_as_string(payload.get("id")),
    )
    await orders_repo.set_order_checkout_reference(
        order_id=order["id"],
        checkout_id=None,
        payment_intent=None,
        subscription_id=_as_string(payload.get("id")),
        customer_id=_as_string(payload.get("customer")),
    )
    return order


async def _apply_membership_state(
    order: Mapping[str, Any],
    *,
    status: str,
    effective_at: datetime | None,
    expires_at: datetime | None,
    canceled_at: datetime | None,
    ended_at: datetime | None,
    step: str,
    info: dict[str, Any],
) -> None:
    user_id = str(order["user_id"])
    _, _ = await _write_payment_membership_state(
        user_id,
        status=status,
        effective_at=effective_at,
        expires_at=expires_at,
        canceled_at=canceled_at,
        ended_at=ended_at,
    )
    log_info = dict(info)
    await membership_support_repo.insert_billing_log(
        user_id=user_id,
        step=step,
        info=log_info,
    )
    await sync_onboarding_state(user_id)


async def _write_payment_membership_state(
    user_id: str,
    *,
    status: str,
    effective_at: datetime | None,
    expires_at: datetime | None,
    canceled_at: datetime | None,
    ended_at: datetime | None,
) -> tuple[Mapping[str, Any] | None, bool]:
    existing_membership = await memberships_repo.get_membership(user_id)
    membership = await memberships_repo.upsert_membership_record(
        user_id,
        status=status,
        effective_at=effective_at
        if effective_at is not None
        else (existing_membership or {}).get("effective_at"),
        expires_at=expires_at,
        canceled_at=canceled_at,
        ended_at=ended_at,
        source="purchase",
    )
    return membership, True


def _canonical_status_from_subscription_payload(payload: Mapping[str, Any]) -> str:
    now = datetime.now(timezone.utc)
    status_value = str(payload.get("status") or "").strip().lower()
    expires_at = _subscription_expires_at(payload)

    if status_value in {"past_due", "unpaid"}:
        return "past_due"
    if status_value in {"incomplete", "incomplete_expired"}:
        return "inactive"
    if bool(payload.get("cancel_at_period_end")):
        return "canceled"
    if status_value == "canceled":
        if expires_at and expires_at > now:
            return "canceled"
        return "expired"
    if expires_at and expires_at <= now and status_value not in {"active"}:
        return "expired"
    if status_value in {"active", "trialing"}:
        return "active"
    return "inactive"


def _subscription_expires_at(payload: Mapping[str, Any]) -> datetime | None:
    return _to_datetime(
        payload.get("current_period_end")
        or payload.get("trial_end")
        or payload.get("cancel_at")
        or payload.get("ended_at")
    )


def _subscription_is_trialing(payload: Mapping[str, Any]) -> bool:
    return str(payload.get("status") or "").strip().lower() == "trialing"


def _subscription_canceled_at(payload: Mapping[str, Any]) -> datetime | None:
    return _to_datetime(payload.get("canceled_at") or payload.get("cancel_at"))


def _subscription_ended_at(payload: Mapping[str, Any]) -> datetime | None:
    return _to_datetime(payload.get("ended_at"))


def _extract_period(payload: Mapping[str, Any]) -> dict[str, datetime | None]:
    lines = payload.get("lines", {})
    data = lines.get("data") if isinstance(lines, Mapping) else None
    if isinstance(data, list) and data:
        period = data[0].get("period") or {}
        start = _to_datetime(period.get("start"))
        end = _to_datetime(period.get("end"))
        return {"start": start, "end": end}
    return {"start": None, "end": None}


def _metadata_dict(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    metadata = payload.get("metadata")
    return metadata if isinstance(metadata, Mapping) else {}


def _as_string(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return str(value)


def _to_datetime(value: Any) -> datetime | None:
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    return None
