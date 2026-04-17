from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Sequence
from uuid import UUID

from psycopg import errors
from psycopg.rows import dict_row

from ..config import settings
from ..db import pool


SCHEMA_VERSION = "stripe_observability_v1"
AUTHORITY_NOTE = "observability_not_authority"
_RECENT_LIMIT = 25


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral() else float(value)
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value


def _issue(code: str, source: str, message: str, *, severity: str = "error") -> dict[str, Any]:
    return {
        "code": code,
        "source": source,
        "message": message,
        "severity": severity,
    }


def _mismatch(code: str, source: str, message: str, rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "code": code,
        "source": source,
        "message": message,
        "row_count": len(rows),
        "rows": rows,
    }


def _status_from(issues: list[dict[str, Any]], mismatches: list[dict[str, Any]]) -> str:
    severities = {str(issue.get("severity") or "error") for issue in issues}
    if "error" in severities:
        return "blocked"
    if "warning" in severities or mismatches:
        return "warning"
    return "ok"


def _surface(
    artifact_type: str,
    *,
    data: dict[str, Any],
    issues: list[dict[str, Any]],
    mismatches: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "artifact_type": artifact_type,
        "schema_version": SCHEMA_VERSION,
        "generated_at_utc": _now_iso(),
        "status": _status_from(issues, mismatches),
        "authority_note": AUTHORITY_NOTE,
        "data_sources": [
            "app.orders",
            "app.payments",
            "app.payment_events",
            "app.billing_logs",
            "app.memberships",
            "app.stripe_customers",
        ],
        "read_only": True,
        "authority_override": False,
        "stripe_api_used": False,
        "forbidden_actions": ["refund", "cancel_subscription", "write"],
        "data": _json_safe(data),
        "mismatches": _json_safe(mismatches),
        "issues": issues,
    }


async def _fetch_all(sql: str, params: Sequence[Any] = ()) -> list[dict[str, Any]]:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute("SET TRANSACTION READ ONLY")
            await cur.execute(sql, params)
            rows = await cur.fetchall()
        await conn.rollback()
    return [_json_safe(dict(row)) for row in rows]


async def _fetch_one(sql: str, params: Sequence[Any] = ()) -> dict[str, Any]:
    rows = await _fetch_all(sql, params)
    return rows[0] if rows else {}


async def _safe_fetch_one(source: str, sql: str, params: Sequence[Any] = ()) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    try:
        return await _fetch_one(sql, params), []
    except (errors.UndefinedTable, errors.UndefinedColumn):
        return {}, [
            _issue(
                "stripe_observability_schema_unavailable",
                source,
                f"{source} schema is unavailable",
                severity="warning",
            )
        ]
    except Exception as exc:
        return {}, [
            _issue(
                "stripe_observability_read_failed",
                source,
                f"{source} read failed: {exc.__class__.__name__}",
            )
        ]


async def _safe_fetch_all(source: str, sql: str, params: Sequence[Any] = ()) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    try:
        return await _fetch_all(sql, params), []
    except (errors.UndefinedTable, errors.UndefinedColumn):
        return [], [
            _issue(
                "stripe_observability_schema_unavailable",
                source,
                f"{source} schema is unavailable",
                severity="warning",
            )
        ]
    except Exception as exc:
        return [], [
            _issue(
                "stripe_observability_read_failed",
                source,
                f"{source} read failed: {exc.__class__.__name__}",
            )
        ]


async def get_checkout_sessions() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    summary, summary_issues = await _safe_fetch_one(
        "app.orders.checkout_sessions",
        """
        SELECT
          COUNT(*) FILTER (WHERE stripe_checkout_id IS NOT NULL)::int AS checkout_order_count,
          COUNT(*) FILTER (WHERE stripe_checkout_id IS NOT NULL AND status = 'pending')::int AS pending_checkout_order_count,
          COUNT(*) FILTER (WHERE stripe_checkout_id IS NOT NULL AND status = 'paid')::int AS paid_checkout_order_count,
          COUNT(*) FILTER (WHERE stripe_checkout_id IS NOT NULL AND order_type = 'subscription')::int AS subscription_checkout_order_count
        FROM app.orders
        """,
    )
    issues.extend(summary_issues)
    recent, recent_issues = await _safe_fetch_all(
        "app.orders.checkout_sessions.recent",
        """
        SELECT id AS order_id,
               user_id,
               order_type,
               status,
               amount_cents,
               currency,
               stripe_checkout_id,
               stripe_payment_intent,
               stripe_subscription_id,
               stripe_customer_id,
               created_at,
               updated_at
        FROM app.orders
        WHERE stripe_checkout_id IS NOT NULL
        ORDER BY updated_at DESC, created_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(recent_issues)
    duplicates, duplicate_issues = await _safe_fetch_all(
        "app.orders.checkout_sessions.duplicates",
        """
        SELECT stripe_checkout_id,
               COUNT(*)::int AS order_count,
               array_agg(id::text ORDER BY updated_at DESC) AS order_ids
        FROM app.orders
        WHERE stripe_checkout_id IS NOT NULL
        GROUP BY stripe_checkout_id
        HAVING COUNT(*) > 1
        ORDER BY stripe_checkout_id
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(duplicate_issues)
    if duplicates:
        mismatches.append(
            _mismatch(
                "duplicate_checkout_session_reference",
                "app.orders.stripe_checkout_id",
                "One Stripe checkout session is linked to multiple app orders",
                duplicates,
            )
        )
    unpaid_settlement, unpaid_issues = await _safe_fetch_all(
        "app.orders_to_app.payments.checkout_settlement",
        """
        SELECT o.id AS order_id,
               o.stripe_checkout_id,
               o.stripe_payment_intent,
               o.status
        FROM app.orders o
        LEFT JOIN app.payments p
          ON p.order_id = o.id
         AND p.provider = 'stripe'
         AND p.status = 'paid'
        WHERE o.stripe_checkout_id IS NOT NULL
          AND o.status = 'paid'
          AND p.id IS NULL
        ORDER BY o.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(unpaid_issues)
    if unpaid_settlement:
        mismatches.append(
            _mismatch(
                "paid_checkout_order_without_payment_record",
                "app.orders_to_app.payments",
                "A paid checkout-backed order has no paid Stripe payment row",
                unpaid_settlement,
            )
        )
    orphaned_events, orphaned_event_issues = await _safe_fetch_all(
        "app.payment_events.checkout_to_app.orders",
        """
        SELECT event_id,
               event_type,
               payload #>> '{data,object,id}' AS stripe_checkout_id,
               payload #>> '{data,object,metadata,order_id}' AS metadata_order_id,
               processed_at
        FROM app.payment_events pe
        WHERE event_type IN ('checkout.session.completed', 'checkout.session.async_payment_succeeded')
          AND NOT EXISTS (
            SELECT 1
            FROM app.orders o
            WHERE o.id::text = COALESCE(NULLIF(pe.payload #>> '{data,object,metadata,order_id}', ''), '<missing>')
               OR o.stripe_checkout_id = pe.payload #>> '{data,object,id}'
          )
        ORDER BY processed_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(orphaned_event_issues)
    if orphaned_events:
        mismatches.append(
            _mismatch(
                "checkout_webhook_without_app_order",
                "app.payment_events_to_app.orders",
                "A checkout webhook event cannot be correlated to an app order",
                orphaned_events,
            )
        )
    return _surface(
        "stripe_checkout_health",
        data={"summary": summary, "recent_orders": recent},
        issues=issues,
        mismatches=mismatches,
    )


async def get_subscriptions() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    summary, summary_issues = await _safe_fetch_one(
        "app.orders.subscriptions",
        """
        SELECT
          COUNT(*) FILTER (WHERE order_type = 'subscription')::int AS subscription_order_count,
          COUNT(*) FILTER (WHERE stripe_subscription_id IS NOT NULL)::int AS stripe_subscription_reference_count,
          COUNT(*) FILTER (WHERE order_type = 'subscription' AND status = 'paid')::int AS paid_subscription_order_count
        FROM app.orders
        """,
    )
    issues.extend(summary_issues)
    recent, recent_issues = await _safe_fetch_all(
        "app.orders.subscriptions.recent",
        """
        SELECT o.id AS order_id,
               o.user_id,
               o.status AS order_status,
               o.stripe_checkout_id,
               o.stripe_subscription_id,
               o.stripe_customer_id,
               m.status AS membership_status,
               m.end_date AS membership_end_date,
               sc.customer_id AS mapped_customer_id,
               o.created_at,
               o.updated_at
        FROM app.orders o
        LEFT JOIN app.memberships m
          ON m.user_id = o.user_id
        LEFT JOIN app.stripe_customers sc
          ON sc.user_id = o.user_id
        WHERE o.order_type = 'subscription'
           OR o.stripe_subscription_id IS NOT NULL
        ORDER BY o.updated_at DESC, o.created_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(recent_issues)
    missing_subscription_id, missing_id_issues = await _safe_fetch_all(
        "app.orders.subscriptions.missing_stripe_subscription_id",
        """
        SELECT id AS order_id,
               user_id,
               status,
               stripe_checkout_id,
               stripe_customer_id
        FROM app.orders
        WHERE order_type = 'subscription'
          AND status = 'paid'
          AND stripe_subscription_id IS NULL
        ORDER BY updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(missing_id_issues)
    if missing_subscription_id:
        mismatches.append(
            _mismatch(
                "paid_subscription_order_missing_subscription_id",
                "app.orders.stripe_subscription_id",
                "A paid subscription order is missing its Stripe subscription id",
                missing_subscription_id,
            )
        )
    missing_memberships, missing_membership_issues = await _safe_fetch_all(
        "app.orders.subscriptions_to_app.memberships",
        """
        SELECT o.id AS order_id,
               o.user_id,
               o.stripe_subscription_id,
               o.status
        FROM app.orders o
        LEFT JOIN app.memberships m
          ON m.user_id = o.user_id
        WHERE o.order_type = 'subscription'
          AND o.status = 'paid'
          AND m.membership_id IS NULL
        ORDER BY o.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(missing_membership_issues)
    if missing_memberships:
        mismatches.append(
            _mismatch(
                "paid_subscription_order_without_membership",
                "app.orders_to_app.memberships",
                "A paid subscription order has no app membership row",
                missing_memberships,
            )
        )
    customer_mismatches, customer_issues = await _safe_fetch_all(
        "app.orders_to_app.stripe_customers",
        """
        SELECT o.id AS order_id,
               o.user_id,
               o.stripe_customer_id AS order_customer_id,
               sc.customer_id AS mapped_customer_id
        FROM app.orders o
        JOIN app.stripe_customers sc
          ON sc.user_id = o.user_id
        WHERE o.stripe_customer_id IS NOT NULL
          AND sc.customer_id IS NOT NULL
          AND o.stripe_customer_id <> sc.customer_id
        ORDER BY o.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(customer_issues)
    if customer_mismatches:
        mismatches.append(
            _mismatch(
                "stripe_customer_mapping_mismatch",
                "app.orders_to_app.stripe_customers",
                "Order Stripe customer id differs from retained Stripe customer mapping",
                customer_mismatches,
            )
        )
    duplicate_subscriptions, duplicate_issues = await _safe_fetch_all(
        "app.orders.subscriptions.duplicates",
        """
        SELECT stripe_subscription_id,
               COUNT(*)::int AS order_count,
               array_agg(id::text ORDER BY updated_at DESC) AS order_ids
        FROM app.orders
        WHERE stripe_subscription_id IS NOT NULL
        GROUP BY stripe_subscription_id
        HAVING COUNT(*) > 1
        ORDER BY stripe_subscription_id
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(duplicate_issues)
    if duplicate_subscriptions:
        mismatches.append(
            _mismatch(
                "duplicate_subscription_reference",
                "app.orders.stripe_subscription_id",
                "One Stripe subscription is linked to multiple app orders",
                duplicate_subscriptions,
            )
        )
    return _surface(
        "stripe_subscription_health",
        data={"summary": summary, "recent_subscription_orders": recent},
        issues=issues,
        mismatches=mismatches,
    )


async def get_payments() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    summary, summary_issues = await _safe_fetch_all(
        "app.payments.stripe.status_counts",
        """
        SELECT status,
               COUNT(*)::int AS payment_count,
               COALESCE(SUM(amount_cents), 0)::int AS amount_cents_total
        FROM app.payments
        WHERE provider = 'stripe'
        GROUP BY status
        ORDER BY status
        """,
    )
    issues.extend(summary_issues)
    recent, recent_issues = await _safe_fetch_all(
        "app.payments.stripe.recent",
        """
        SELECT p.id AS payment_id,
               p.order_id,
               p.provider_reference,
               p.status AS payment_status,
               p.amount_cents,
               p.currency,
               o.status AS order_status,
               o.stripe_payment_intent,
               o.stripe_checkout_id,
               o.stripe_subscription_id,
               p.created_at,
               p.updated_at
        FROM app.payments p
        LEFT JOIN app.orders o
          ON o.id = p.order_id
        WHERE p.provider = 'stripe'
        ORDER BY p.updated_at DESC, p.created_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(recent_issues)
    orphaned_payments, orphaned_issues = await _safe_fetch_all(
        "app.payments_to_app.orders",
        """
        SELECT p.id AS payment_id,
               p.order_id,
               p.provider_reference,
               p.status
        FROM app.payments p
        LEFT JOIN app.orders o
          ON o.id = p.order_id
        WHERE p.provider = 'stripe'
          AND o.id IS NULL
        ORDER BY p.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(orphaned_issues)
    if orphaned_payments:
        mismatches.append(
            _mismatch(
                "stripe_payment_without_order",
                "app.payments_to_app.orders",
                "A Stripe payment row has no matching app order",
                orphaned_payments,
            )
        )
    paid_payment_unpaid_order, unpaid_order_issues = await _safe_fetch_all(
        "app.payments.paid_to_app.orders",
        """
        SELECT p.id AS payment_id,
               p.order_id,
               p.provider_reference,
               p.status AS payment_status,
               o.status AS order_status
        FROM app.payments p
        JOIN app.orders o
          ON o.id = p.order_id
        WHERE p.provider = 'stripe'
          AND p.status = 'paid'
          AND o.status <> 'paid'
        ORDER BY p.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(unpaid_order_issues)
    if paid_payment_unpaid_order:
        mismatches.append(
            _mismatch(
                "paid_stripe_payment_unpaid_order",
                "app.payments_to_app.orders",
                "A paid Stripe payment is linked to an app order that is not paid",
                paid_payment_unpaid_order,
            )
        )
    reference_mismatches, reference_issues = await _safe_fetch_all(
        "app.payments.provider_reference_to_app.orders.stripe_payment_intent",
        """
        SELECT p.id AS payment_id,
               p.order_id,
               p.provider_reference,
               o.stripe_payment_intent
        FROM app.payments p
        JOIN app.orders o
          ON o.id = p.order_id
        WHERE p.provider = 'stripe'
          AND p.provider_reference IS NOT NULL
          AND o.stripe_payment_intent IS NOT NULL
          AND p.provider_reference <> o.stripe_payment_intent
        ORDER BY p.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(reference_issues)
    if reference_mismatches:
        mismatches.append(
            _mismatch(
                "payment_reference_mismatch",
                "app.payments_to_app.orders",
                "Stripe payment provider_reference differs from order stripe_payment_intent",
                reference_mismatches,
            )
        )
    return _surface(
        "stripe_payment_health",
        data={"status_counts": summary, "recent_payments": recent},
        issues=issues,
        mismatches=mismatches,
    )


async def get_webhook_state() -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    event_counts, event_count_issues = await _safe_fetch_all(
        "app.payment_events.event_counts",
        """
        SELECT event_type,
               COUNT(*)::int AS event_count,
               MAX(processed_at) AS last_processed_at
        FROM app.payment_events
        GROUP BY event_type
        ORDER BY event_type
        """,
    )
    issues.extend(event_count_issues)
    recent_events, recent_event_issues = await _safe_fetch_all(
        "app.payment_events.recent",
        """
        SELECT event_id,
               event_type,
               payload #>> '{data,object,id}' AS stripe_object_id,
               payload #>> '{data,object,metadata,order_id}' AS metadata_order_id,
               metadata ->> 'status' AS processing_status,
               created_at,
               processed_at
        FROM app.payment_events
        ORDER BY processed_at DESC, created_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(recent_event_issues)
    billing_steps, billing_step_issues = await _safe_fetch_all(
        "app.billing_logs.step_counts",
        """
        SELECT step,
               COUNT(*)::int AS log_count,
               MAX(created_at) AS last_created_at
        FROM app.billing_logs
        GROUP BY step
        ORDER BY step
        """,
    )
    issues.extend(billing_step_issues)
    recent_billing_logs, recent_billing_issues = await _safe_fetch_all(
        "app.billing_logs.recent",
        """
        SELECT id AS billing_log_id,
               step,
               user_id,
               related_order_id,
               created_at
        FROM app.billing_logs
        ORDER BY created_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(recent_billing_issues)
    incomplete_events, incomplete_event_issues = await _safe_fetch_all(
        "app.payment_events.metadata_status",
        """
        SELECT event_id,
               event_type,
               metadata ->> 'status' AS processing_status,
               processed_at
        FROM app.payment_events
        WHERE COALESCE(metadata ->> 'status', '') <> 'completed'
        ORDER BY processed_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(incomplete_event_issues)
    if incomplete_events:
        mismatches.append(
            _mismatch(
                "stripe_webhook_not_marked_completed",
                "app.payment_events.metadata",
                "A Stripe webhook event exists without completed processing metadata",
                incomplete_events,
            )
        )
    webhook_orders, webhook_order_issues = await _safe_fetch_all(
        "app.payment_events_to_app.orders",
        """
        SELECT pe.event_id,
               pe.event_type,
               pe.payload #>> '{data,object,metadata,order_id}' AS metadata_order_id,
               pe.payload #>> '{data,object,id}' AS stripe_object_id,
               pe.processed_at
        FROM app.payment_events pe
        WHERE COALESCE(pe.payload #>> '{data,object,metadata,order_id}', '') <> ''
          AND NOT EXISTS (
            SELECT 1
            FROM app.orders o
            WHERE o.id::text = pe.payload #>> '{data,object,metadata,order_id}'
          )
        ORDER BY pe.processed_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    issues.extend(webhook_order_issues)
    if webhook_orders:
        mismatches.append(
            _mismatch(
                "stripe_webhook_order_reference_missing",
                "app.payment_events_to_app.orders",
                "A Stripe webhook metadata.order_id does not match an app order",
                webhook_orders,
            )
        )
    return _surface(
        "stripe_webhook_health",
        data={
            "event_counts": event_counts,
            "recent_events": recent_events,
            "billing_step_counts": billing_steps,
            "recent_billing_logs": recent_billing_logs,
        },
        issues=issues,
        mismatches=mismatches,
    )


async def get_app_reconciliation() -> dict[str, Any]:
    checkout = await get_checkout_sessions()
    subscriptions = await get_subscriptions()
    payments = await get_payments()
    webhooks = await get_webhook_state()
    access_issues: list[dict[str, Any]] = []
    paid_course_orders_without_access, course_access_issues = await _safe_fetch_all(
        "app.orders_to_app.course_enrollments",
        """
        SELECT o.id AS order_id,
               o.user_id,
               o.order_type::text AS order_type,
               o.course_id,
               o.status,
               o.stripe_checkout_id,
               o.stripe_payment_intent,
               o.updated_at
        FROM app.orders o
        LEFT JOIN app.course_enrollments ce
          ON ce.user_id = o.user_id
         AND ce.course_id = o.course_id
        WHERE o.status = 'paid'
          AND o.course_id IS NOT NULL
          AND ce.id IS NULL
        ORDER BY o.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    access_issues.extend(course_access_issues)

    paid_subscriptions_without_access, subscription_access_issues = await _safe_fetch_all(
        "app.orders_to_app.memberships.reconciliation",
        """
        SELECT o.id AS order_id,
               o.user_id,
               o.order_type::text AS order_type,
               o.stripe_subscription_id,
               o.status,
               o.updated_at
        FROM app.orders o
        LEFT JOIN app.memberships m
          ON m.user_id = o.user_id
        WHERE o.order_type = 'subscription'
          AND o.status = 'paid'
          AND m.membership_id IS NULL
        ORDER BY o.updated_at DESC
        LIMIT %s
        """,
        (_RECENT_LIMIT,),
    )
    access_issues.extend(subscription_access_issues)

    surfaces = {
        "checkout_health": checkout,
        "subscription_health": subscriptions,
        "payment_health": payments,
        "webhook_health": webhooks,
    }
    issues = [
        _issue(
            "stripe_observability_surface_not_ok",
            key,
            f"{key} status is {surface.get('status')}",
            severity="warning" if surface.get("status") == "warning" else "error",
        )
        for key, surface in surfaces.items()
        if surface.get("status") != "ok"
    ]
    mismatches = [
        item
        for surface in surfaces.values()
        for item in surface.get("mismatches", [])
    ]
    issues.extend(access_issues)
    if paid_course_orders_without_access:
        mismatches.append(
            _mismatch(
                "paid_course_order_without_course_access",
                "app.orders_to_app.course_enrollments",
                "A paid course-backed Stripe order has no matching course enrollment",
                paid_course_orders_without_access,
            )
        )
    if paid_subscriptions_without_access:
        mismatches.append(
            _mismatch(
                "paid_subscription_without_membership_access",
                "app.orders_to_app.memberships",
                "A paid Stripe subscription order has no matching app membership",
                paid_subscriptions_without_access,
            )
        )
    return _surface(
        "stripe_app_reconciliation",
        data={
            "stripe_config": {
                "secret_key_configured": bool(settings.stripe_secret_key),
                "webhook_secret_configured": bool(settings.stripe_webhook_secret),
                "billing_webhook_secret_configured": bool(settings.stripe_billing_webhook_secret),
                "checkout_ui_mode": settings.stripe_checkout_ui_mode,
            },
            "surface_status": {
                key: surface.get("status")
                for key, surface in surfaces.items()
            },
            "correlation_keys": ["order_id", "user_id", "stripe_checkout_id", "stripe_payment_intent", "stripe_subscription_id"],
            "payment_success_access_checks": {
                "paid_course_orders_without_access_count": len(paid_course_orders_without_access),
                "paid_subscriptions_without_access_count": len(paid_subscriptions_without_access),
            },
        },
        issues=issues,
        mismatches=mismatches,
    )


async def get_stripe_observability_summary() -> dict[str, Any]:
    return await get_app_reconciliation()
