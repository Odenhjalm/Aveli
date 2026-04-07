from __future__ import annotations

from datetime import datetime
from uuid import uuid4
from typing import Any, Mapping

from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool

MembershipRow = dict[str, Any]
_TABLE_COLUMNS_CACHE: dict[tuple[str, str], set[str]] = {}
_CANONICAL_MEMBERSHIP_COLUMNS = (
    "membership_id",
    "user_id",
    "status",
    "end_date",
    "created_at",
    "updated_at",
)
_OPTIONAL_COMPAT_MEMBERSHIP_COLUMNS = (
    "plan_interval",
    "price_id",
    "stripe_customer_id",
    "stripe_subscription_id",
    "start_date",
)


async def get_latest_subscription(user_id: str) -> MembershipRow | None:
    """Legacy helper name retained, but canonical app-entry authority is memberships only."""
    return await get_membership(user_id)


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
    if not set(_CANONICAL_MEMBERSHIP_COLUMNS).issubset(available_columns):
        return (), available_columns

    selected_columns = list(_CANONICAL_MEMBERSHIP_COLUMNS)
    for column in _OPTIONAL_COMPAT_MEMBERSHIP_COLUMNS:
        if column in available_columns:
            selected_columns.append(column)

    return tuple(selected_columns), available_columns


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
    """
    Find a membership by Stripe references. Prefer subscription_id matches, otherwise fall back
    to the most recent customer_id match. This avoids returning stale rows when dummy IDs (e.g. in tests)
    collide across users.
    """
    if not customer_id and not subscription_id:
        return None

    selected_columns, available_columns = await _membership_columns()
    if not selected_columns:
        return None

    async with get_conn() as cur:
        try:
            if subscription_id and "stripe_subscription_id" in available_columns:
                await cur.execute(
                    f"""
                    SELECT {", ".join(selected_columns)}
                      FROM app.memberships
                     WHERE stripe_subscription_id = %s
                     ORDER BY updated_at DESC
                     LIMIT 1
                    """,
                    (subscription_id,),
                )
                row = await cur.fetchone()
                if row:
                    return _normalize_membership_row(row)

            if customer_id and "stripe_customer_id" in available_columns:
                await cur.execute(
                    f"""
                    SELECT {", ".join(selected_columns)}
                      FROM app.memberships
                     WHERE stripe_customer_id = %s
                     ORDER BY updated_at DESC
                     LIMIT 1
                    """,
                    (customer_id,),
                )
                row = await cur.fetchone()
                if row:
                    return _normalize_membership_row(row)
        except (errors.UndefinedTable, errors.UndefinedColumn):
            return None

    return None


async def set_customer_id(user_id: str, customer_id: str) -> None:
    _, available_columns = await _membership_columns()
    if "stripe_customer_id" not in available_columns:
        return

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    UPDATE app.memberships
                       SET stripe_customer_id = %s,
                           updated_at = now()
                     WHERE user_id = %s
                    """,
                    (customer_id, user_id),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return
            await conn.commit()


async def upsert_membership_record(
    user_id: str,
    *,
    plan_interval: str | None = None,
    price_id: str | None = None,
    status: str | None = None,
    stripe_customer_id: str | None = None,
    stripe_subscription_id: str | None = None,
    start_date: datetime | None = None,
    end_date: datetime | None = None,
) -> MembershipRow:
    _, available_columns = await _membership_columns()
    if not set(_CANONICAL_MEMBERSHIP_COLUMNS).issubset(available_columns):
        raise RuntimeError("app.memberships is unavailable")

    existing = await get_membership(user_id)

    # When legacy billing columns still exist, keep them as non-authority compatibility
    # fields. When the canonical baseline shape is active, only canonical app-entry fields
    # are written.
    if {"plan_interval", "price_id"}.issubset(available_columns):
        plan_value = plan_interval or (existing or {}).get("plan_interval")
        price_value = price_id or (existing or {}).get("price_id")
        if not plan_value or not price_value:
            raise ValueError("plan_interval and price_id are required for memberships")

        async with pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                try:
                    await cur.execute(
                        """
                        INSERT INTO app.memberships (
                            user_id,
                            plan_interval,
                            price_id,
                            status,
                            stripe_customer_id,
                            stripe_subscription_id,
                            start_date,
                            end_date,
                            created_at,
                            updated_at
                        )
                        VALUES (%s, %s, %s, COALESCE(%s, 'active'), %s, %s, COALESCE(%s, now()), %s, now(), now())
                        ON CONFLICT (user_id) DO UPDATE
                        SET plan_interval = EXCLUDED.plan_interval,
                            price_id = EXCLUDED.price_id,
                            status = COALESCE(EXCLUDED.status, app.memberships.status),
                            stripe_customer_id = COALESCE(EXCLUDED.stripe_customer_id, app.memberships.stripe_customer_id),
                            stripe_subscription_id = COALESCE(
                                EXCLUDED.stripe_subscription_id,
                                app.memberships.stripe_subscription_id
                            ),
                            start_date = COALESCE(EXCLUDED.start_date, app.memberships.start_date),
                            end_date = COALESCE(EXCLUDED.end_date, app.memberships.end_date),
                            updated_at = now()
                        RETURNING membership_id,
                                  user_id,
                                  plan_interval,
                                  price_id,
                                  stripe_customer_id,
                                  stripe_subscription_id,
                                  status,
                                  start_date,
                                  end_date,
                                  created_at,
                                  updated_at
                        """,
                        (
                            user_id,
                            plan_value,
                            price_value,
                            status,
                            stripe_customer_id,
                            stripe_subscription_id,
                            start_date,
                            end_date,
                        ),
                    )
                except errors.UndefinedTable:
                    raise
                row = await cur.fetchone()
                await conn.commit()
        return _normalize_membership_row(row)

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.memberships (
                    membership_id,
                    user_id,
                    status,
                    end_date,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, COALESCE(%s, 'active'), %s, now(), now())
                ON CONFLICT (user_id) DO UPDATE
                SET status = COALESCE(EXCLUDED.status, app.memberships.status),
                    end_date = EXCLUDED.end_date,
                    updated_at = now()
                RETURNING membership_id,
                          user_id,
                          status,
                          end_date,
                          created_at,
                          updated_at
                """,
                (
                    str((existing or {}).get("membership_id") or uuid4()),
                    user_id,
                    status,
                    end_date,
                ),
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
    normalized: MembershipRow = {
        "id": data.get("membership_id") or data.get("id"),
        "membership_id": data.get("membership_id") or data.get("id"),
        "user_id": data.get("user_id"),
        "subscription_id": data.get("stripe_subscription_id") or data.get("subscription_id"),
        "customer_id": data.get("stripe_customer_id") or data.get("customer_id"),
        "status": data.get("status"),
        "price_id": data.get("price_id"),
        "plan_interval": data.get("plan_interval"),
        "stripe_subscription_id": data.get("stripe_subscription_id"),
        "stripe_customer_id": data.get("stripe_customer_id"),
        "start_date": data.get("start_date"),
        "end_date": data.get("end_date"),
        "created_at": data.get("created_at"),
        "updated_at": data.get("updated_at"),
    }
    return normalized


__all__ = [
    "get_latest_subscription",
    "get_membership",
    "upsert_membership_record",
    "get_membership_by_stripe_reference",
    "insert_payment_event",
    "insert_billing_log",
]
