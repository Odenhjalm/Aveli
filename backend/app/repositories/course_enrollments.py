from __future__ import annotations

from typing import Any
from uuid import UUID, uuid4

from psycopg.rows import dict_row

from ..db import pool


class BundleEnrollmentFulfillmentError(RuntimeError):
    """Raised when bundle snapshot fulfillment violates canonical contracts."""


def _as_uuid_text(value: str | UUID | Any, label: str) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        raise BundleEnrollmentFulfillmentError(f"{label} is required")
    try:
        return str(UUID(normalized))
    except ValueError as exc:
        raise BundleEnrollmentFulfillmentError(f"{label} must be a UUID") from exc


def _validate_snapshot_rows(
    rows: list[dict[str, Any]],
    *,
    order_id: str,
    bundle_id: str,
) -> None:
    if not rows:
        raise BundleEnrollmentFulfillmentError(
            "bundle fulfillment requires an immutable order snapshot"
        )

    positions: list[int] = []
    course_ids: set[str] = set()
    for row in rows:
        if _as_uuid_text(row.get("order_id"), "snapshot order_id") != order_id:
            raise BundleEnrollmentFulfillmentError(
                "bundle snapshot row belongs to a different order"
            )
        if _as_uuid_text(row.get("bundle_id"), "snapshot bundle_id") != bundle_id:
            raise BundleEnrollmentFulfillmentError(
                "bundle snapshot row belongs to a different bundle"
            )
        course_id = _as_uuid_text(row.get("course_id"), "snapshot course_id")
        if course_id in course_ids:
            raise BundleEnrollmentFulfillmentError(
                "bundle snapshot contains duplicate courses"
            )
        course_ids.add(course_id)
        try:
            positions.append(int(row.get("position")))
        except (TypeError, ValueError) as exc:
            raise BundleEnrollmentFulfillmentError(
                "bundle snapshot position is invalid"
            ) from exc

    expected = list(range(1, len(rows) + 1))
    if sorted(positions) != expected:
        raise BundleEnrollmentFulfillmentError(
            "bundle snapshot positions must be contiguous from 1"
        )


async def fulfill_bundle_order_snapshot(
    *,
    order_id: str | UUID,
    user_id: str | UUID,
    bundle_id: str | UUID,
) -> list[dict[str, Any]]:
    """Create purchase enrollments from app.bundle_order_courses in one transaction."""

    normalized_order_id = _as_uuid_text(order_id, "order_id")
    normalized_user_id = _as_uuid_text(user_id, "user_id")
    normalized_bundle_id = _as_uuid_text(bundle_id, "bundle_id")

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        try:
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    SELECT id, user_id, bundle_id, order_type, status
                      FROM app.orders
                     WHERE id = %s::uuid
                     FOR UPDATE
                    """,
                    (normalized_order_id,),
                )
                order = await cur.fetchone()
                if order is None:
                    raise BundleEnrollmentFulfillmentError(
                        "bundle fulfillment order was not found"
                    )
                if str(order.get("order_type") or "").strip().lower() != "bundle":
                    raise BundleEnrollmentFulfillmentError(
                        "bundle fulfillment requires a bundle order"
                    )
                if order.get("bundle_id") is None:
                    raise BundleEnrollmentFulfillmentError(
                        "bundle fulfillment order is missing bundle_id"
                    )
                if (
                    _as_uuid_text(order.get("user_id"), "order user_id")
                    != normalized_user_id
                ):
                    raise BundleEnrollmentFulfillmentError(
                        "bundle fulfillment user does not match order"
                    )
                if (
                    _as_uuid_text(order.get("bundle_id"), "order bundle_id")
                    != normalized_bundle_id
                ):
                    raise BundleEnrollmentFulfillmentError(
                        "bundle fulfillment bundle does not match order"
                    )

                await cur.execute(
                    """
                    SELECT id, order_id, bundle_id, course_id, position, created_at
                      FROM app.bundle_order_courses
                     WHERE order_id = %s::uuid
                     ORDER BY position
                     FOR SHARE
                    """,
                    (normalized_order_id,),
                )
                snapshot_rows = [dict(row) for row in await cur.fetchall()]
                _validate_snapshot_rows(
                    snapshot_rows,
                    order_id=normalized_order_id,
                    bundle_id=normalized_bundle_id,
                )

                enrollments: list[dict[str, Any]] = []
                for snapshot_row in snapshot_rows:
                    await cur.execute(
                        """
                        SELECT
                            ce.id,
                            ce.user_id,
                            ce.course_id,
                            ce.source::text AS source,
                            ce.granted_at,
                            ce.drip_started_at,
                            ce.current_unlock_position
                          FROM app.canonical_create_course_enrollment(
                            %s::uuid,
                            %s::uuid,
                            %s::uuid,
                            'purchase'::app.course_enrollment_source,
                            clock_timestamp()
                          ) AS ce
                        """,
                        (
                            str(uuid4()),
                            normalized_user_id,
                            snapshot_row["course_id"],
                        ),
                    )
                    enrollment = await cur.fetchone()
                    if enrollment is None:
                        raise BundleEnrollmentFulfillmentError(
                            "canonical course enrollment was not returned"
                        )
                    enrollments.append(dict(enrollment))

            await conn.commit()
            return enrollments
        except Exception:
            await conn.rollback()
            raise


__all__ = [
    "BundleEnrollmentFulfillmentError",
    "fulfill_bundle_order_snapshot",
]
