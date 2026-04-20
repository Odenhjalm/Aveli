from __future__ import annotations

import logging
from typing import Any, Mapping

from ..repositories import courses as courses_repo

logger = logging.getLogger(__name__)


async def handle_paid_checkout_order(
    *,
    order: Mapping[str, Any],
    event_type: str,
    conn: Any | None = None,
) -> dict[str, Any]:
    order_metadata = order.get("metadata")
    if not isinstance(order_metadata, Mapping):
        order_metadata = {}

    user_id = order.get("user_id") or order_metadata.get("user_id")
    course_id = order.get("course_id")
    if not user_id:
        logger.warning(
            "Course checkout completion missing user; order_id=%s event=%s",
            order.get("id"),
            event_type,
        )
        raise RuntimeError("Missing required webhook data: user_id")
    if not course_id:
        logger.warning(
            "Course checkout completion missing course; order_id=%s event=%s",
            order.get("id"),
            event_type,
        )
        raise RuntimeError("Missing required webhook data: course_id")

    return await courses_repo.create_course_enrollment(
        user_id=str(user_id),
        course_id=str(course_id),
        source="purchase",
        conn=conn,
    )


async def assert_purchase_enrollment_exists(
    *,
    order: Mapping[str, Any],
    conn: Any | None = None,
) -> dict[str, Any]:
    user_id = order.get("user_id")
    course_id = order.get("course_id")
    if not user_id or not course_id:
        raise RuntimeError("Missing required webhook data: user_id/course_id")

    enrollment = await courses_repo.get_course_enrollment(
        str(user_id),
        str(course_id),
        conn=conn,
    )
    if enrollment is None:
        raise RuntimeError("Course purchase is missing canonical enrollment")
    if str(enrollment.get("source") or "").strip().lower() != "purchase":
        raise RuntimeError("Course purchase enrollment source is not purchase")
    return enrollment
