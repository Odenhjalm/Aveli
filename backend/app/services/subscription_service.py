from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Mapping

import stripe
from starlette.concurrency import run_in_threadpool

from ..config import settings
from ..repositories import memberships as memberships_repo
from ..repositories import stripe_customers as stripe_customers_repo
from ..schemas.billing import SubscriptionCheckoutResponse, SubscriptionInterval

logger = logging.getLogger(__name__)


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


async def create_subscription_checkout(
    user: Mapping[str, Any], interval: SubscriptionInterval
) -> SubscriptionCheckoutResponse:
    secret = settings.stripe_secret_key
    if not secret:
        raise SubscriptionConfigError("Stripe secret key is missing")

    price_id = _price_for_interval(interval)
    if not price_id:
        raise SubscriptionConfigError("Stripe price for interval is missing")

    stripe.api_key = secret
    user_id = str(user["id"])
    customer_id = await _get_or_create_customer(user)

    success_url = settings.checkout_success_url or _build_frontend_url("checkout/success")
    cancel_url = settings.checkout_cancel_url or _build_frontend_url("checkout/cancel")

    def _create_session() -> dict[str, Any]:
        return stripe.checkout.Session.create(
            mode="subscription",
            ui_mode=settings.stripe_checkout_ui_mode or "custom",
            customer=customer_id,
            line_items=[{"price": price_id, "quantity": 1}],
            success_url=success_url,
            cancel_url=cancel_url,
            locale="sv",
            metadata={"user_id": user_id, "interval": interval.value},
            subscription_data={
                "metadata": {"user_id": user_id, "interval": interval.value},
            },
        )

    session = await run_in_threadpool(_create_session)
    checkout_url = session.get("url")
    if not isinstance(checkout_url, str):
        raise SubscriptionError("Stripe session missing checkout url", status_code=502)

    await memberships_repo.upsert_membership_record(
        user_id,
        plan_interval=interval.value,
        price_id=price_id,
        status="incomplete",
        stripe_customer_id=customer_id,
    )

    await memberships_repo.insert_billing_log(
        user_id=user_id,
        step="create_subscription_session",
        info={
            "interval": interval.value,
            "price_id": price_id,
            "session_id": session.get("id"),
        },
    )

    return SubscriptionCheckoutResponse(checkout_url=checkout_url)


async def create_checkout_session(user: Mapping[str, Any], interval: SubscriptionInterval) -> str:
    secret = settings.stripe_secret_key
    if not secret:
        raise SubscriptionConfigError("Stripe secret key is missing")

    price_id = _price_for_interval(interval)
    if not price_id:
        raise SubscriptionConfigError("Stripe price for interval is missing")

    stripe.api_key = secret
    user_id = str(user["id"])
    customer_id = await _get_or_create_customer(user)

    def _create_session() -> dict[str, Any]:
        return stripe.checkout.Session.create(
            mode="subscription",
            customer=customer_id,
            line_items=[{"price": price_id, "quantity": 1}],
            subscription_data={"trial_period_days": 14},
            success_url=settings.checkout_success_url
            or "aveliapp://checkout_success",
            cancel_url=settings.checkout_cancel_url
            or "aveliapp://checkout_cancel",
            locale="sv",
        )

    session = await run_in_threadpool(_create_session)
    checkout_url = session.get("url")
    if not isinstance(checkout_url, str):
        raise SubscriptionError("Stripe session missing checkout url", status_code=502)

    await memberships_repo.insert_billing_log(
        user_id=user_id,
        step="create_checkout_session",
        info={
            "interval": interval.value,
            "price_id": price_id,
            "session_id": session.get("id"),
        },
    )

    return checkout_url


async def cancel_subscription(
    user: Mapping[str, Any],
    *,
    subscription_id: str | None = None,
) -> dict[str, Any]:
    # Flutter-klienten slog tidigare mot ett legacy-endpoint som inte fanns vilket gjorde att
    # avbryt-knappen aldrig fungerade. Nu hanterar vi uppsägningen via Stripe på backend.
    secret = settings.stripe_secret_key
    if not secret:
        raise SubscriptionConfigError("Stripe secret key is missing")

    user_id = str(user["id"])
    membership = await memberships_repo.get_membership(user_id)
    if not membership:
        raise SubscriptionError("Ingen aktiv prenumeration hittades", status_code=404)

    target_subscription_id = subscription_id or membership.get("stripe_subscription_id")
    if not target_subscription_id:
        raise SubscriptionError("Prenumerationen saknar Stripe subscription-id", status_code=400)

    if subscription_id and subscription_id != target_subscription_id:
        raise SubscriptionError("Angivet subscription-id matchar inte ditt konto", status_code=400)

    stripe.api_key = secret

    def _cancel() -> dict[str, Any]:
        return stripe.Subscription.modify(  # type: ignore[attr-defined]
            target_subscription_id,
            cancel_at_period_end=True,
        )

    try:
        updated = await run_in_threadpool(_cancel)
    except stripe.error.InvalidRequestError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError("Stripe kunde inte avsluta prenumerationen", status_code=400) from exc
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError("Stripe-fel vid avbokning", status_code=502) from exc

    cancel_at_period_end = bool(updated.get("cancel_at_period_end"))
    period_end_raw = updated.get("current_period_end")
    end_date = _to_datetime(period_end_raw) if cancel_at_period_end else datetime.now(timezone.utc)
    status = updated.get("status") or "canceled"

    await memberships_repo.upsert_membership_record(
        user_id,
        plan_interval=membership.get("plan_interval"),
        price_id=membership.get("price_id"),
        status=status,
        stripe_customer_id=membership.get("stripe_customer_id"),
        stripe_subscription_id=target_subscription_id,
        end_date=end_date,
    )
    await memberships_repo.insert_billing_log(
        user_id=user_id,
        step="cancel_subscription",
        info={
            "subscription_id": target_subscription_id,
            "stripe_status": status,
            "cancel_at_period_end": cancel_at_period_end,
        },
    )
    return {
        "subscription_id": target_subscription_id,
        "status": status,
        "cancel_at_period_end": cancel_at_period_end,
        "current_period_end": _to_datetime(period_end_raw),
    }


async def handle_webhook(payload: bytes, signature: str | None) -> None:
    # Allow overriding the secret in tests by setting stripe_webhook_secret; fall back to the
    # billing-specific secret when the generic one is not provided.
    secret = settings.stripe_webhook_secret or settings.stripe_billing_webhook_secret
    if not secret:
        raise SubscriptionConfigError("Stripe webhook secret missing")
    if not signature:
        raise SubscriptionError("Missing Stripe signature")

    try:
        event = stripe.Webhook.construct_event(
            payload=payload.decode("utf-8"),
            sig_header=signature,
            secret=secret,
        )
    except ValueError as exc:
        raise SubscriptionError("Invalid Stripe payload") from exc
    except stripe.error.SignatureVerificationError as exc:  # type: ignore[attr-defined]
        raise SubscriptionError("Invalid Stripe signature") from exc

    await process_event(event)


async def process_event(event: Mapping[str, Any]) -> None:
    await memberships_repo.insert_payment_event(event.get("id", ""), event)

    event_type = event.get("type", "")
    data_object = event.get("data", {}).get("object", {})

    if event_type in {
        "customer.subscription.created",
        "customer.subscription.updated",
    }:
        await _handle_subscription_event(data_object)
    elif event_type == "customer.subscription.deleted":
        await _handle_subscription_event(data_object, override_status="canceled", force_end=True)
    elif event_type == "invoice.payment_succeeded":
        await _handle_invoice_payment_succeeded(data_object)
    elif event_type == "invoice.payment_failed":
        await memberships_repo.insert_billing_log(
            user_id=_extract_user_id(data_object),
            step="invoice.payment_failed",
            info={"subscription": data_object.get("subscription")},
        )
    else:
        logger.debug("Unhandled subscription event: %s", event_type)


async def _handle_subscription_event(
    payload: Mapping[str, Any],
    *,
    override_status: str | None = None,
    force_end: bool = False,
) -> None:
    subscription_id = payload.get("id")
    customer_id = payload.get("customer")
    status = override_status or payload.get("status")
    plan_interval, price_id = _extract_plan_from_payload(payload)
    user_id = _extract_user_id(payload)

    if not user_id and isinstance(customer_id, str):
        user_id = await stripe_customers_repo.get_user_id_by_customer(customer_id)

    if not user_id:
        membership = await memberships_repo.get_membership_by_stripe_reference(
            customer_id=customer_id if isinstance(customer_id, str) else None,
            subscription_id=subscription_id if isinstance(subscription_id, str) else None,
        )
        if membership:
            user_id = str(membership.get("user_id")) if membership.get("user_id") else None

    if not user_id:
        logger.warning(
            "Subscription event missing user mapping (subscription=%s, customer=%s)",
            subscription_id,
            customer_id,
        )
        return

    if not plan_interval or not price_id:
        logger.warning("Subscription event missing price information")
        return

    await memberships_repo.upsert_membership_record(
        user_id,
        plan_interval=plan_interval,
        price_id=price_id,
        status=status,
        stripe_customer_id=customer_id if isinstance(customer_id, str) else None,
        stripe_subscription_id=subscription_id if isinstance(subscription_id, str) else None,
        start_date=_to_datetime(payload.get("current_period_start")),
        end_date=_determine_end_date(payload, force_end=force_end),
    )


async def _handle_invoice_payment_succeeded(payload: Mapping[str, Any]) -> None:
    customer_id = payload.get("customer")
    subscription_id = payload.get("subscription")
    plan_interval, price_id = _extract_plan_from_invoice(payload)
    period = _extract_period(payload)

    membership = await memberships_repo.get_membership_by_stripe_reference(
        customer_id=customer_id if isinstance(customer_id, str) else None,
        subscription_id=subscription_id if isinstance(subscription_id, str) else None,
    )

    user_id: str | None = None
    if membership and membership.get("user_id"):
        user_id = str(membership["user_id"])
    elif isinstance(customer_id, str):
        user_id = await stripe_customers_repo.get_user_id_by_customer(customer_id)

    if not user_id:
        logger.info("Invoice event could not be mapped to a user")
        return

    if not plan_interval and membership:
        plan_interval = membership.get("plan_interval")
    if not price_id and membership:
        price_id = membership.get("price_id")

    if not plan_interval or not price_id:
        logger.info("Invoice event missing price metadata")
        return

    await memberships_repo.upsert_membership_record(
        user_id,
        plan_interval=plan_interval,
        price_id=price_id,
        status="active",
        stripe_customer_id=customer_id if isinstance(customer_id, str) else None,
        stripe_subscription_id=subscription_id if isinstance(subscription_id, str) else None,
        start_date=period.get("start"),
        end_date=period.get("end"),
    )


def _price_for_interval(interval: SubscriptionInterval) -> str | None:
    if interval is SubscriptionInterval.month:
        return settings.stripe_price_monthly
    if interval is SubscriptionInterval.year:
        return settings.stripe_price_yearly
    return None


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
        raise SubscriptionError("Failed to create Stripe customer", status_code=502)
    await stripe_customers_repo.upsert_customer(user_id, customer_id)
    return customer_id


def _extract_plan_from_payload(payload: Mapping[str, Any]) -> tuple[str | None, str | None]:
    items = payload.get("items", {})
    data = items.get("data") if isinstance(items, Mapping) else None
    if isinstance(data, list) and data:
        price = data[0].get("price") or {}
        interval = _extract_interval_from_price(price)
        return interval, price.get("id")
    price_obj = payload.get("plan")
    if isinstance(price_obj, Mapping):
        return price_obj.get("interval"), price_obj.get("id")
    return None, None


def _extract_plan_from_invoice(payload: Mapping[str, Any]) -> tuple[str | None, str | None]:
    lines = payload.get("lines", {})
    data = lines.get("data") if isinstance(lines, Mapping) else None
    if isinstance(data, list) and data:
        price = data[0].get("price") or {}
        return _extract_interval_from_price(price), price.get("id")
    return None, None


def _extract_interval_from_price(price: Mapping[str, Any]) -> str | None:
    recurring = price.get("recurring") if isinstance(price, Mapping) else None
    if isinstance(recurring, Mapping):
        interval = recurring.get("interval")
        if isinstance(interval, str):
            return interval
    return None


def _extract_period(payload: Mapping[str, Any]) -> dict[str, datetime | None]:
    lines = payload.get("lines", {})
    data = lines.get("data") if isinstance(lines, Mapping) else None
    if isinstance(data, list) and data:
        period = data[0].get("period") or {}
        start = _to_datetime(period.get("start"))
        end = _to_datetime(period.get("end"))
        return {"start": start, "end": end}
    return {"start": None, "end": None}


def _extract_user_id(payload: Mapping[str, Any]) -> str | None:
    metadata = payload.get("metadata")
    if isinstance(metadata, Mapping):
        user_id = metadata.get("user_id")
        if isinstance(user_id, str):
            return user_id
    return None


def _determine_end_date(payload: Mapping[str, Any], *, force_end: bool = False) -> datetime | None:
    if force_end:
        return datetime.now(timezone.utc)
    end_value = payload.get("current_period_end")
    return _to_datetime(end_value)


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
