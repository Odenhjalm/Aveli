from __future__ import annotations

from datetime import datetime, timezone
import logging

import stripe
from starlette.concurrency import run_in_threadpool

from ..db import pool
from .. import stripe_mode
from ..repositories import orders as orders_repo
from ..repositories import payments as payments_repo
from ..repositories import teachers as teachers_repo
from ..services import checkout_service, stripe_webhook_course_service

logger = logging.getLogger(__name__)


async def handle_payment_intent_succeeded(payload: dict[str, object]) -> None:
    await checkout_service.handle_payment_intent_succeeded(payload)


async def handle_refund_event(
    event_type: str,
    payload: dict[str, object],
    *,
    conn: object | None = None,
) -> None:
    payment_intent_id: str | None = None
    if event_type == "payment_intent.canceled":
        intent_value = payload.get("id")
        if isinstance(intent_value, str):
            payment_intent_id = intent_value
    elif event_type == "charge.refunded":
        intent_value = payload.get("payment_intent")
        if isinstance(intent_value, str):
            payment_intent_id = intent_value

    if not payment_intent_id:
        logger.info("Refund event missing payment intent id: event=%s", event_type)
        return

    async def _execute(active_conn: object) -> None:
        order = await orders_repo.get_order_by_payment_intent(
            payment_intent_id,
            conn=active_conn,
        )
        if not order:
            logger.info(
                "Refund event could not match order by payment intent: %s",
                payment_intent_id,
            )
            return

        refunded_order = await orders_repo.mark_order_refunded(
            order["id"],
            payment_intent=payment_intent_id,
            conn=active_conn,
        )
        if not refunded_order:
            return

        if refunded_order.get("course_id"):
            await stripe_webhook_course_service.revoke_paid_order_access(
                order=refunded_order,
                conn=active_conn,
            )

        await payments_repo.record_payment(
            order_id=refunded_order["id"],
            provider="stripe",
            provider_reference=payment_intent_id,
            status="refunded",
            amount_cents=int(refunded_order.get("amount_cents") or 0),
            currency=(refunded_order.get("currency") or "sek").lower(),
            metadata={"event": event_type},
            payload=payload,
            conn=active_conn,
        )

    if conn is not None:
        await _execute(conn)
        return

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        try:
            await _execute(active_conn)
            await active_conn.commit()
        except Exception:
            await active_conn.rollback()
            raise


async def handle_connect_event(
    *,
    event_type: str,
    event_payload: dict[str, object],
    data_object: dict[str, object],
    context: stripe_mode.StripeContext,
) -> None:
    account_id = (
        data_object.get("id")
        if event_type == "account.updated"
        else event_payload.get("account") or data_object.get("account")
    )
    if not isinstance(account_id, str):
        logger.info("Stripe account event without account id: %s", event_type)
        return

    teacher = await teachers_repo.get_teacher_by_account(account_id)
    if not teacher:
        logger.info("No teacher row for account %s", account_id)
        return

    stripe.api_key = context.secret_key
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

    await teachers_repo.update_teacher_status(
        teacher["profile_id"],
        charges_enabled=charges_enabled,
        payouts_enabled=payouts_enabled,
        requirements_due=requirements,
        status=status_value,
        onboarded_at=onboarded_at,
    )
