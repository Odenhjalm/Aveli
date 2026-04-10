from __future__ import annotations

import logging
from typing import Any, Mapping

from ..services import course_bundles_service

logger = logging.getLogger(__name__)


async def handle_paid_checkout_order(
    *,
    order: Mapping[str, Any],
    stripe_customer_id: str | None,
    payment_intent_id: str | None,
    event_type: str,
) -> None:
    order_metadata = order.get("metadata")
    if not isinstance(order_metadata, Mapping):
        order_metadata = {}

    user_id = order.get("user_id") or order_metadata.get("user_id")
    bundle_id = order_metadata.get("bundle_id")
    if not user_id or not bundle_id:
        logger.warning(
            "Bundle checkout completion missing user or bundle; order_id=%s event=%s",
            order.get("id"),
            event_type,
        )
        return

    try:
        await course_bundles_service.grant_bundle_entitlements(
            str(bundle_id),
            str(user_id),
            stripe_customer_id=stripe_customer_id,
            payment_intent_id=payment_intent_id,
        )
    except Exception as exc:  # pragma: no cover - defensive logging
        logger.warning(
            "Failed to grant bundle entitlements; bundle=%s error=%s",
            bundle_id,
            exc,
        )
