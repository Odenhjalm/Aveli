from __future__ import annotations

from datetime import datetime
from typing import Any, Mapping
from uuid import uuid4

from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool

MembershipRow = dict[str, Any]
_TABLE_COLUMNS_CACHE: dict[tuple[str, str], set[str]] = {}
_UNSET = object()
_REQUIRED_MEMBERSHIP_COLUMNS = (
    "membership_id",
    "user_id",
    "status",
    "created_at",
    "updated_at",
)
_OPTIONAL_MEMBERSHIP_COLUMNS = (
    "end_date",
    "effective_at",
    "expires_at",
    "canceled_at",
    "ended_at",
    "source",
    "provider_customer_id",
    "provider_subscription_id",
    "plan_interval",
    "price_id",
    "stripe_customer_id",
    "stripe_subscription_id",
    "start_date",
)

async def _table_columns(schema: str, table: str) -> set[str]:
    cache_key = (schema, table)
    cached = _TABLE_COLUMNS_CACHE.get(cache_key)
    if cached is not None:
        return cached

    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = %s
              AND table_name = %s
            """,
            (schema, table),
        )
        rows = await cur.fetchall()

    columns = {
        str((row or {}).get("column_name"))
        for row in rows
        if (row or {}).get("column_name")
    }
    _TABLE_COLUMNS_CACHE[cache_key] = columns
    return columns


async def _membership_columns() -> tuple[tuple[str, ...], set[str]]:
    available_columns = await _table_columns("app", "memberships")
    if not set(_REQUIRED_MEMBERSHIP_COLUMNS).issubset(available_columns):
        return (), available_columns

    selected_columns = list(_REQUIRED_MEMBERSHIP_COLUMNS)
    for column in _OPTIONAL_MEMBERSHIP_COLUMNS:
        if column in available_columns and column not in selected_columns:
            selected_columns.append(column)

    return tuple(selected_columns), available_columns


def _resolve_explicit(explicit: Any, fallback: Any) -> Any:
    if explicit is _UNSET:
        return fallback
    return explicit


def _first_present(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None


def _expiry_column_sql(columns: set[str], alias: str = "m") -> str | None:
    if "expires_at" in columns and "end_date" in columns:
        return f"COALESCE({alias}.expires_at, {alias}.end_date)"
    if "expires_at" in columns:
        return f"{alias}.expires_at"
    if "end_date" in columns:
        return f"{alias}.end_date"
    return None


async def get_membership(user_id: str) -> MembershipRow | None:
    selected_columns, _ = await _membership_columns()
    if not selected_columns:
        return None

    async with get_conn() as cur:
        try:
            await cur.execute(
                f"""
                SELECT {", ".join(selected_columns)}
                  FROM app.memberships
                 WHERE user_id = %s
                 LIMIT 1
                """,
                (user_id,),
            )
        except (errors.UndefinedTable, errors.UndefinedColumn):
            return None
        row = await cur.fetchone()
    return _normalize_membership_row(row) if row else None


async def get_membership_by_stripe_reference(
    *,
    customer_id: str | None = None,
    subscription_id: str | None = None,
) -> MembershipRow | None:
    if not customer_id and not subscription_id:
        return None

    selected_columns, available_columns = await _membership_columns()
    if not selected_columns:
        return None

    lookups = (
        ("provider_subscription_id", subscription_id),
        ("stripe_subscription_id", subscription_id),
        ("provider_customer_id", customer_id),
        ("stripe_customer_id", customer_id),
    )

    async with get_conn() as cur:
        try:
            for column_name, lookup_value in lookups:
                if not lookup_value or column_name not in available_columns:
                    continue
                await cur.execute(
                    f"""
                    SELECT {", ".join(selected_columns)}
                      FROM app.memberships
                     WHERE {column_name} = %s
                     ORDER BY updated_at DESC
                     LIMIT 1
                    """,
                    (lookup_value,),
                )
                row = await cur.fetchone()
                if row:
                    return _normalize_membership_row(row)
        except (errors.UndefinedTable, errors.UndefinedColumn):
            return None

    return None


async def list_current_member_user_ids() -> list[str]:
    _, available_columns = await _membership_columns()
    if not available_columns:
        return []

    expiry_sql = _expiry_column_sql(available_columns)
    access_clause = "m.status = 'active'"
    if expiry_sql:
        access_clause = (
            f"(m.status = 'active' OR (m.status = 'canceled' AND {expiry_sql} IS NOT NULL AND {expiry_sql} > now()))"
        )

    async with get_conn() as cur:
        try:
            await cur.execute(
                f"""
                SELECT DISTINCT m.user_id
                  FROM app.memberships m
                 WHERE {access_clause}
                """
            )
            rows = await cur.fetchall()
        except (errors.UndefinedTable, errors.UndefinedColumn):
            return []

    return [str(row["user_id"]) for row in (rows or []) if row.get("user_id")]


async def set_customer_id(user_id: str, customer_id: str) -> None:
    _, available_columns = await _membership_columns()
    customer_columns = [
        column_name
        for column_name in ("provider_customer_id", "stripe_customer_id")
        if column_name in available_columns
    ]
    if not customer_columns:
        return

    assignments = ", ".join(f"{column_name} = %s" for column_name in customer_columns)
    params = [customer_id for _ in customer_columns]
    params.extend([user_id])

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    f"""
                    UPDATE app.memberships
                       SET {assignments},
                           updated_at = now()
                     WHERE user_id = %s
                    """,
                    params,
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return
            await conn.commit()


async def upsert_membership_record(
    user_id: str,
    *,
    status: str | None = None,
    effective_at: datetime | None | object = _UNSET,
    expires_at: datetime | None | object = _UNSET,
    canceled_at: datetime | None | object = _UNSET,
    ended_at: datetime | None | object = _UNSET,
    source: str | None | object = _UNSET,
    provider_customer_id: str | None | object = _UNSET,
    provider_subscription_id: str | None | object = _UNSET,
    plan_interval: str | None = None,
    price_id: str | None = None,
    stripe_customer_id: str | None = None,
    stripe_subscription_id: str | None = None,
    start_date: datetime | None = None,
    end_date: datetime | None = None,
) -> MembershipRow:
    selected_columns, available_columns = await _membership_columns()
    if not selected_columns:
        raise RuntimeError("app.memberships is unavailable")

    existing = await get_membership(user_id)
    membership_id = str((existing or {}).get("membership_id") or uuid4())

    resolved_status = str(status or (existing or {}).get("status") or "inactive").strip().lower()
    existing_effective_at = _first_present(
        (existing or {}).get("effective_at"),
        (existing or {}).get("start_date"),
    )
    existing_expires_at = _first_present(
        (existing or {}).get("expires_at"),
        (existing or {}).get("end_date"),
    )
    existing_provider_customer_id = _first_present(
        (existing or {}).get("provider_customer_id"),
        (existing or {}).get("stripe_customer_id"),
    )
    existing_provider_subscription_id = _first_present(
        (existing or {}).get("provider_subscription_id"),
        (existing or {}).get("stripe_subscription_id"),
    )

    effective_explicit = effective_at if effective_at is not _UNSET else start_date
    expires_explicit = expires_at if expires_at is not _UNSET else end_date
    customer_explicit = (
        provider_customer_id
        if provider_customer_id is not _UNSET
        else (stripe_customer_id if stripe_customer_id is not None else _UNSET)
    )
    subscription_explicit = (
        provider_subscription_id
        if provider_subscription_id is not _UNSET
        else (stripe_subscription_id if stripe_subscription_id is not None else _UNSET)
    )

    values_by_column: dict[str, Any] = {
        "membership_id": membership_id,
        "user_id": user_id,
        "status": resolved_status,
    }

    if "effective_at" in available_columns:
        values_by_column["effective_at"] = _resolve_explicit(effective_explicit, existing_effective_at)
    if "expires_at" in available_columns:
        values_by_column["expires_at"] = _resolve_explicit(expires_explicit, existing_expires_at)
    if "canceled_at" in available_columns:
        values_by_column["canceled_at"] = _resolve_explicit(
            canceled_at,
            (existing or {}).get("canceled_at"),
        )
    if "ended_at" in available_columns:
        values_by_column["ended_at"] = _resolve_explicit(
            ended_at,
            (existing or {}).get("ended_at"),
        )
    if "source" in available_columns:
        values_by_column["source"] = _resolve_explicit(
            source,
            (existing or {}).get("source"),
        )
    if "provider_customer_id" in available_columns:
        values_by_column["provider_customer_id"] = _resolve_explicit(
            customer_explicit,
            existing_provider_customer_id,
        )
    if "provider_subscription_id" in available_columns:
        values_by_column["provider_subscription_id"] = _resolve_explicit(
            subscription_explicit,
            existing_provider_subscription_id,
        )
    if "plan_interval" in available_columns:
        values_by_column["plan_interval"] = plan_interval or (existing or {}).get("plan_interval")
    if "price_id" in available_columns:
        values_by_column["price_id"] = price_id or (existing or {}).get("price_id")
    if "stripe_customer_id" in available_columns:
        values_by_column["stripe_customer_id"] = _resolve_explicit(
            customer_explicit,
            existing_provider_customer_id,
        )
    if "stripe_subscription_id" in available_columns:
        values_by_column["stripe_subscription_id"] = _resolve_explicit(
            subscription_explicit,
            existing_provider_subscription_id,
        )
    if "start_date" in available_columns:
        values_by_column["start_date"] = _resolve_explicit(
            effective_explicit,
            existing_effective_at,
        )
    if "end_date" in available_columns:
        values_by_column["end_date"] = _resolve_explicit(
            expires_explicit,
            existing_expires_at,
        )

    dynamic_columns = [
        column_name
        for column_name in values_by_column.keys()
        if column_name not in {"membership_id", "user_id", "status"}
    ]
    insert_columns = ["membership_id", "user_id", "status", *dynamic_columns, "created_at", "updated_at"]
    insert_values = [
        values_by_column["membership_id"],
        values_by_column["user_id"],
        values_by_column["status"],
        *[values_by_column[column_name] for column_name in dynamic_columns],
    ]
    insert_placeholders = ", ".join(
        [
            *["%s" for _ in range(3 + len(dynamic_columns))],
            "now()",
            "now()",
        ]
    )
    update_assignments = [
        "status = EXCLUDED.status",
        *[f"{column_name} = EXCLUDED.{column_name}" for column_name in dynamic_columns],
        "updated_at = now()",
    ]

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                INSERT INTO app.memberships ({", ".join(insert_columns)})
                VALUES ({insert_placeholders})
                ON CONFLICT (user_id) DO UPDATE
                SET {", ".join(update_assignments)}
                RETURNING {", ".join(selected_columns)}
                """,
                insert_values,
            )
            row = await cur.fetchone()
            await conn.commit()
    return _normalize_membership_row(row)


async def insert_payment_event(event_id: str, payload: dict[str, Any]) -> bool:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.payment_events (event_id, payload, processed_at)
                    VALUES (%s, %s, now())
                    ON CONFLICT (event_id) DO NOTHING
                    RETURNING event_id
                    """,
                    (event_id, Jsonb(payload)),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return True
            row = await cur.fetchone()
            await conn.commit()
    return row is not None


async def insert_billing_log(
    *,
    user_id: str | None,
    step: str,
    info: dict[str, Any] | None = None,
) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.billing_logs (user_id, step, info, created_at)
                    VALUES (%s, %s, %s, now())
                    """,
                    (user_id, step, Jsonb(info or {})),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return
            await conn.commit()


def _normalize_membership_row(row: Mapping[str, Any] | None) -> MembershipRow | None:
    if row is None:
        return None
    data = dict(row)
    effective_at = _first_present(data.get("effective_at"), data.get("start_date"))
    expires_at = _first_present(data.get("expires_at"), data.get("end_date"))
    provider_customer_id = _first_present(
        data.get("provider_customer_id"),
        data.get("stripe_customer_id"),
        data.get("customer_id"),
    )
    provider_subscription_id = _first_present(
        data.get("provider_subscription_id"),
        data.get("stripe_subscription_id"),
        data.get("subscription_id"),
    )
    normalized: MembershipRow = {
        "id": data.get("membership_id") or data.get("id"),
        "membership_id": data.get("membership_id") or data.get("id"),
        "user_id": data.get("user_id"),
        "status": data.get("status"),
        "effective_at": effective_at,
        "expires_at": expires_at,
        "canceled_at": data.get("canceled_at"),
        "ended_at": data.get("ended_at"),
        "source": data.get("source"),
        "provider_customer_id": provider_customer_id,
        "provider_subscription_id": provider_subscription_id,
        "customer_id": provider_customer_id,
        "subscription_id": provider_subscription_id,
        "stripe_customer_id": provider_customer_id,
        "stripe_subscription_id": provider_subscription_id,
        "start_date": effective_at,
        "end_date": expires_at,
        "price_id": data.get("price_id"),
        "plan_interval": data.get("plan_interval"),
        "created_at": data.get("created_at"),
        "updated_at": data.get("updated_at"),
    }
    return normalized


__all__ = [
    "get_membership",
    "get_membership_by_stripe_reference",
    "insert_billing_log",
    "insert_payment_event",
    "list_current_member_user_ids",
    "set_customer_id",
    "upsert_membership_record",
]
