from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool


async def create_payment_command(
    *,
    user_id: str | UUID,
    command_type: str,
    idempotency_key: str | None,
    request_fingerprint: str,
    request_metadata: dict[str, Any] | None,
    status: str = "created",
    stripe_checkout_session_id: str | None = None,
    stripe_payment_intent_id: str | None = None,
    stripe_subscription_id: str | None = None,
    amount_cents: int,
    currency: str,
    course_id: str | UUID | None = None,
    bundle_id: str | UUID | None = None,
    service_id: str | UUID | None = None,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.payment_commands (
                        user_id,
                        command_type,
                        idempotency_key,
                        request_fingerprint,
                        request_metadata,
                        status,
                        stripe_checkout_session_id,
                        stripe_payment_intent_id,
                        stripe_subscription_id,
                        amount_cents,
                        currency,
                        course_id,
                        bundle_id,
                        service_id
                    )
                    VALUES (
                        %s,
                        %s::app.payment_command_type,
                        %s,
                        %s,
                        %s,
                        %s::app.payment_command_status,
                        %s,
                        %s,
                        %s,
                        %s,
                        %s,
                        %s,
                        %s,
                        %s
                    )
                    RETURNING command_id,
                              user_id,
                              command_type,
                              idempotency_key,
                              request_fingerprint,
                              request_metadata,
                              status,
                              stripe_checkout_session_id,
                              stripe_payment_intent_id,
                              stripe_subscription_id,
                              amount_cents,
                              currency,
                              course_id,
                              bundle_id,
                              service_id,
                              created_at,
                              updated_at
                    """,
                    (
                        user_id,
                        command_type,
                        idempotency_key,
                        request_fingerprint,
                        Jsonb(request_metadata or {}),
                        status,
                        stripe_checkout_session_id,
                        stripe_payment_intent_id,
                        stripe_subscription_id,
                        amount_cents,
                        currency,
                        course_id,
                        bundle_id,
                        service_id,
                    ),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def mark_payment_command_session_created(
    *,
    command_id: str | UUID,
    stripe_checkout_session_id: str | None,
    stripe_payment_intent_id: str | None,
    stripe_subscription_id: str | None,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    UPDATE app.payment_commands
                       SET status = 'session_created',
                           stripe_checkout_session_id = COALESCE(
                               %s,
                               stripe_checkout_session_id
                           ),
                           stripe_payment_intent_id = COALESCE(
                               %s,
                               stripe_payment_intent_id
                           ),
                           stripe_subscription_id = COALESCE(
                               %s,
                               stripe_subscription_id
                           ),
                           updated_at = now()
                     WHERE command_id = %s
                     RETURNING command_id,
                               user_id,
                               command_type,
                               idempotency_key,
                               request_fingerprint,
                               request_metadata,
                               status,
                               stripe_checkout_session_id,
                               stripe_payment_intent_id,
                               stripe_subscription_id,
                               amount_cents,
                               currency,
                               course_id,
                               bundle_id,
                               service_id,
                               created_at,
                               updated_at
                    """,
                    (
                        stripe_checkout_session_id,
                        stripe_payment_intent_id,
                        stripe_subscription_id,
                        command_id,
                    ),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def resolve_payment_command_id(
    *,
    stripe_checkout_session_id: str | None = None,
    stripe_payment_intent_id: str | None = None,
    stripe_subscription_id: str | None = None,
) -> str | None:
    async with get_conn() as cur:
        try:
            if stripe_checkout_session_id:
                await cur.execute(
                    """
                    SELECT command_id
                    FROM app.payment_commands
                    WHERE stripe_checkout_session_id = %s
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                    (stripe_checkout_session_id,),
                )
                row = await cur.fetchone()
                if row and row.get("command_id"):
                    return str(row["command_id"])

            if stripe_payment_intent_id:
                await cur.execute(
                    """
                    SELECT command_id
                    FROM app.payment_commands
                    WHERE stripe_payment_intent_id = %s
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                    (stripe_payment_intent_id,),
                )
                row = await cur.fetchone()
                if row and row.get("command_id"):
                    return str(row["command_id"])

            if stripe_subscription_id:
                await cur.execute(
                    """
                    SELECT command_id
                    FROM app.payment_commands
                    WHERE stripe_subscription_id = %s
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                    (stripe_subscription_id,),
                )
                row = await cur.fetchone()
                if row and row.get("command_id"):
                    return str(row["command_id"])
        except errors.UndefinedTable:
            return None
    return None


async def insert_stripe_event_ledger(
    *,
    event_id: str,
    event_type: str,
    raw_event: dict[str, Any],
    resolved_command_id: str | UUID | None,
) -> bool | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.stripe_event_ledger (
                        provider,
                        event_id,
                        event_type,
                        received_at,
                        status,
                        raw_event,
                        resolved_command_id
                    )
                    VALUES (
                        'stripe',
                        %s,
                        %s,
                        now(),
                        'received',
                        %s,
                        %s
                    )
                    ON CONFLICT (event_id) DO NOTHING
                    RETURNING event_id
                    """,
                    (
                        event_id,
                        event_type,
                        Jsonb(raw_event),
                        resolved_command_id,
                    ),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await cur.fetchone()
            await conn.commit()
    return bool(row)
