from __future__ import annotations

import logging
from typing import Any, Mapping

from ..repositories import courses as courses_repo

logger = logging.getLogger(__name__)


async def handle_paid_checkout_order(
    *,
    order: Mapping[str, Any],
    event_type: str,
) -> None:
    order_metadata = order.get("metadata")
    if not isinstance(order_metadata, Mapping):
        order_metadata = {}

    user_id = order.get("user_id") or order_metadata.get("user_id")
    course_id = order.get("course_id")
    if not user_id or not course_id:
        logger.warning(
            "Course checkout completion missing user or course; order_id=%s event=%s",
            order.get("id"),
            event_type,
        )
        return

    await courses_repo.create_course_enrollment(
        user_id=str(user_id),
        course_id=str(course_id),
        source="purchase",
    )
