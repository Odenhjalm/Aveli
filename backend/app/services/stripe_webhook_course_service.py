from __future__ import annotations

import logging
from typing import Any, Mapping

from ..repositories import courses as courses_repo

logger = logging.getLogger(__name__)


def _course_purchase_principals(
    order: Mapping[str, Any],
    *,
    event_type: str,
) -> tuple[str, str]:
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
    return str(user_id), str(course_id)


async def handle_paid_checkout_order(
    *,
    order: Mapping[str, Any],
    event_type: str,
    conn: Any | None = None,
) -> dict[str, Any]:
    user_id, course_id = _course_purchase_principals(
        order,
        event_type=event_type,
    )

    return await courses_repo.create_course_enrollment(
        user_id=user_id,
        course_id=course_id,
        source="purchase",
        conn=conn,
    )


async def assert_purchase_enrollment_exists(
    *,
    order: Mapping[str, Any],
    conn: Any | None = None,
    repair_missing_enrollment: bool = False,
    event_type: str = "course_checkout_reconciliation",
) -> dict[str, Any]:
    user_id, course_id = _course_purchase_principals(
        order,
        event_type=event_type,
    )

    enrollment = await courses_repo.get_course_enrollment(
        user_id,
        course_id,
        conn=conn,
    )
    if enrollment is None:
        if repair_missing_enrollment:
            return await handle_paid_checkout_order(
                order=order,
                event_type=event_type,
                conn=conn,
            )
        raise RuntimeError("Course purchase is missing canonical enrollment")
    if str(enrollment.get("source") or "").strip().lower() != "purchase":
        raise RuntimeError("Course purchase enrollment source is not purchase")
    return enrollment


async def revoke_paid_order_access(
    *,
    order: Mapping[str, Any],
    conn: Any | None = None,
) -> list[str]:
    previous_status = str(
        order.get("previous_status") or order.get("status") or ""
    ).strip().lower()
    if previous_status not in {"paid", "refunded"}:
        return []

    order_id = str(order.get("id") or "").strip()
    if not order_id:
        raise RuntimeError("Missing required webhook data: order_id")

    user_id, course_id = _course_purchase_principals(
        order,
        event_type="refund_reversal",
    )
    revoked = await courses_repo.revoke_course_enrollment(
        user_id,
        course_id,
        excluding_order_id=order_id,
        conn=conn,
    )
    return [course_id] if revoked else []
