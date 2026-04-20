from __future__ import annotations

import logging
from typing import Any, Mapping

from ..repositories import course_enrollments

logger = logging.getLogger(__name__)

SAFE_BUNDLE_FULFILLMENT_ERROR = (
    "Betalningen är registrerad, men kurserna kunde inte aktiveras ännu."
)


class BundleFulfillmentError(RuntimeError):
    pass


async def handle_paid_checkout_order(
    *,
    order: Mapping[str, Any],
    event_type: str,
) -> None:
    order_id = order.get("id")
    user_id = order.get("user_id")
    bundle_id = order.get("bundle_id")
    order_type = str(order.get("order_type") or "").strip().lower()

    if order_type != "bundle":
        logger.warning(
            "Bundle checkout completion resolved non-bundle order; "
            "order_id=%s event=%s",
            order_id,
            event_type,
        )
        raise BundleFulfillmentError(SAFE_BUNDLE_FULFILLMENT_ERROR)
    if not order_id:
        logger.warning(
            "Bundle checkout completion missing order id; event=%s",
            event_type,
        )
        raise BundleFulfillmentError(SAFE_BUNDLE_FULFILLMENT_ERROR)
    if not user_id:
        logger.warning(
            "Bundle checkout completion missing user; order_id=%s event=%s",
            order_id,
            event_type,
        )
        raise BundleFulfillmentError(SAFE_BUNDLE_FULFILLMENT_ERROR)
    if not bundle_id:
        logger.warning(
            "Bundle checkout completion missing bundle; order_id=%s event=%s",
            order_id,
            event_type,
        )
        raise BundleFulfillmentError(SAFE_BUNDLE_FULFILLMENT_ERROR)

    try:
        await course_enrollments.fulfill_bundle_order_snapshot(
            order_id=str(order_id),
            user_id=str(user_id),
            bundle_id=str(bundle_id),
        )
    except Exception as exc:
        logger.exception(
            "Bundle snapshot fulfillment failed; order_id=%s bundle_id=%s event=%s",
            order_id,
            bundle_id,
            event_type,
        )
        raise BundleFulfillmentError(SAFE_BUNDLE_FULFILLMENT_ERROR) from exc
