from __future__ import annotations

import hashlib
import json
import logging
from time import perf_counter
from typing import Any, Mapping

from .. import metrics
from ..repositories import payment_commands as payment_commands_repo

logger = logging.getLogger(__name__)


def extract_idempotency_key(headers: Mapping[str, str] | None) -> str | None:
    if not headers:
        return None
    raw_value = headers.get("idempotency-key") or headers.get("x-idempotency-key")
    if raw_value is None:
        return None
    value = raw_value.strip()
    return value or None


def build_request_fingerprint(request_metadata: Mapping[str, Any] | None) -> str:
    canonical_payload = json.dumps(
        request_metadata or {},
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    return hashlib.sha256(canonical_payload.encode("utf-8")).hexdigest()


async def create_checkout_command(
    *,
    user_id: str,
    command_type: str,
    idempotency_key: str | None,
    request_metadata: Mapping[str, Any] | None,
    amount_cents: int,
    currency: str,
    course_id: str | None,
    bundle_id: str | None,
    service_id: str | None,
) -> str | None:
    metadata = dict(request_metadata or {})
    metadata.setdefault("user_id", user_id)
    fingerprint = build_request_fingerprint(metadata)
    started = perf_counter()
    try:
        row = await payment_commands_repo.create_payment_command(
            user_id=user_id,
            command_type=command_type,
            idempotency_key=idempotency_key,
            request_fingerprint=fingerprint,
            request_metadata=metadata,
            status="created",
            amount_cents=amount_cents,
            currency=currency,
            course_id=course_id,
            bundle_id=bundle_id,
            service_id=service_id,
        )
    except Exception as exc:  # pragma: no cover - shadow write must never block checkout
        logger.exception(
            "Shadow payment command creation failed command_type=%s user_id=%s idempotency_key=%s: %s",
            command_type,
            user_id,
            idempotency_key,
            exc,
        )
        return None

    apply_duration_ms = (perf_counter() - started) * 1000
    if not row:
        logger.info(
            "Shadow payment command skipped command_type=%s user_id=%s idempotency_key=%s apply_duration_ms=%.2f",
            command_type,
            user_id,
            idempotency_key,
            apply_duration_ms,
        )
        return None

    command_id = row.get("command_id")
    if not command_id:
        return None

    metrics.payment_command_created.inc()
    logger.info(
        "Shadow payment command created command_id=%s command_type=%s idempotency_key=%s amount_cents=%s currency=%s apply_duration_ms=%.2f",
        command_id,
        command_type,
        idempotency_key,
        amount_cents,
        currency,
        apply_duration_ms,
    )
    return str(command_id)


async def mark_checkout_session_created(
    *,
    command_id: str | None,
    idempotency_key: str | None,
    stripe_checkout_session_id: str | None,
    stripe_payment_intent_id: str | None,
    stripe_subscription_id: str | None,
) -> None:
    if not command_id:
        return
    started = perf_counter()
    try:
        row = await payment_commands_repo.mark_payment_command_session_created(
            command_id=command_id,
            stripe_checkout_session_id=stripe_checkout_session_id,
            stripe_payment_intent_id=stripe_payment_intent_id,
            stripe_subscription_id=stripe_subscription_id,
        )
    except Exception as exc:  # pragma: no cover - shadow write must never block checkout
        logger.exception(
            "Shadow payment command session update failed command_id=%s idempotency_key=%s: %s",
            command_id,
            idempotency_key,
            exc,
        )
        return

    apply_duration_ms = (perf_counter() - started) * 1000
    if not row:
        logger.info(
            "Shadow payment command session update skipped command_id=%s idempotency_key=%s apply_duration_ms=%.2f",
            command_id,
            idempotency_key,
            apply_duration_ms,
        )
        return

    logger.info(
        "Shadow payment command session_created command_id=%s idempotency_key=%s stripe_checkout_session_id=%s stripe_payment_intent_id=%s stripe_subscription_id=%s apply_duration_ms=%.2f",
        command_id,
        idempotency_key,
        stripe_checkout_session_id,
        stripe_payment_intent_id,
        stripe_subscription_id,
        apply_duration_ms,
    )


def extract_event_stripe_identifiers(
    event_type: str | None,
    data_object: Mapping[str, Any] | None,
) -> dict[str, str | None]:
    payload = data_object or {}
    normalized_type = event_type or ""

    object_id = payload.get("id")
    payment_intent = payload.get("payment_intent")
    subscription = payload.get("subscription")

    stripe_checkout_session_id: str | None = None
    stripe_payment_intent_id: str | None = None
    stripe_subscription_id: str | None = None

    if normalized_type.startswith("checkout.session.") and isinstance(object_id, str):
        stripe_checkout_session_id = object_id
    if normalized_type.startswith("payment_intent.") and isinstance(object_id, str):
        stripe_payment_intent_id = object_id
    elif isinstance(payment_intent, str):
        stripe_payment_intent_id = payment_intent

    if normalized_type.startswith("customer.subscription.") and isinstance(object_id, str):
        stripe_subscription_id = object_id
    elif isinstance(subscription, str):
        stripe_subscription_id = subscription

    return {
        "stripe_checkout_session_id": stripe_checkout_session_id,
        "stripe_payment_intent_id": stripe_payment_intent_id,
        "stripe_subscription_id": stripe_subscription_id,
    }


async def resolve_command_id_from_event(
    *,
    event_type: str | None,
    data_object: Mapping[str, Any] | None,
) -> tuple[str | None, dict[str, str | None]]:
    stripe_identifiers = extract_event_stripe_identifiers(event_type, data_object)
    try:
        command_id = await payment_commands_repo.resolve_payment_command_id(
            stripe_checkout_session_id=stripe_identifiers["stripe_checkout_session_id"],
            stripe_payment_intent_id=stripe_identifiers["stripe_payment_intent_id"],
            stripe_subscription_id=stripe_identifiers["stripe_subscription_id"],
        )
    except Exception as exc:  # pragma: no cover - shadow lookup must never block webhook
        logger.exception(
            "Shadow payment command resolve failed event_type=%s ids=%s: %s",
            event_type,
            stripe_identifiers,
            exc,
        )
        return None, stripe_identifiers
    return command_id, stripe_identifiers


async def record_webhook_event(
    *,
    event_id: str,
    event_type: str,
    raw_event: dict[str, Any],
    resolved_command_id: str | None,
) -> bool | None:
    started = perf_counter()
    try:
        inserted = await payment_commands_repo.insert_stripe_event_ledger(
            event_id=event_id,
            event_type=event_type,
            raw_event=raw_event,
            resolved_command_id=resolved_command_id,
        )
    except Exception as exc:  # pragma: no cover - shadow ledger must never block webhook
        logger.exception(
            "Shadow stripe ledger insert failed event_id=%s event_type=%s resolved_command_id=%s: %s",
            event_id,
            event_type,
            resolved_command_id,
            exc,
        )
        return None

    apply_duration_ms = (perf_counter() - started) * 1000
    if inserted is None:
        logger.info(
            "Shadow stripe ledger write skipped event_id=%s event_type=%s resolved_command_id=%s apply_duration_ms=%.2f",
            event_id,
            event_type,
            resolved_command_id,
            apply_duration_ms,
        )
        return None

    logger.info(
        "Shadow stripe ledger write event_id=%s event_type=%s resolved_command_id=%s duplicate_detection=%s apply_duration_ms=%.2f",
        event_id,
        event_type,
        resolved_command_id,
        inserted is False,
        apply_duration_ms,
    )
    return inserted
