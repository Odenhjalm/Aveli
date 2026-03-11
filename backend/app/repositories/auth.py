from __future__ import annotations

from datetime import datetime
import uuid
from typing import Any
from uuid import UUID

from psycopg import InterfaceError, errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool
from ..utils.referrals import referral_membership_window
from .referrals import normalize_referral_code, normalize_referral_email


class UniqueViolationError(Exception):
    """Raised when attempting to insert a record that already exists."""


class InvalidReferralCodeError(Exception):
    """Raised when a supplied referral code cannot be redeemed."""


async def create_user(
    *,
    email: str,
    hashed_password: str,
    display_name: str | None,
    referral_code: str | None = None,
) -> dict[str, Any]:
    """Insert a new auth user + profile."""
    new_id = uuid.uuid4()
    normalized_email = email.strip().lower()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO auth.users (id, email, encrypted_password, created_at, updated_at)
                    VALUES (%s, %s, %s, now(), now())
                    RETURNING id, email, created_at, updated_at
                    """,
                    (new_id, normalized_email, hashed_password),
                )
            except errors.UniqueViolation as exc:
                await conn.rollback()
                raise UniqueViolationError from exc

            user_row = await cur.fetchone()
            user_id = user_row["id"]

            await cur.execute(
                """
                INSERT INTO app.profiles (
                    user_id, email, display_name, role, role_v2, is_admin, created_at, updated_at
                )
                VALUES (%s, %s, %s, 'student', 'user', false, now(), now())
                ON CONFLICT (user_id) DO UPDATE
                  SET email = excluded.email,
                      display_name = excluded.display_name,
                      updated_at = now()
                RETURNING user_id, email, display_name, role_v2, is_admin, created_at, updated_at
                """,
                (user_id, normalized_email, display_name),
            )
            profile_row = await cur.fetchone()

            redeemed_referral = None
            if referral_code:
                await cur.execute(
                    """
                    SELECT id,
                           code,
                           teacher_id,
                           email,
                           free_days,
                           free_months,
                           active,
                           redeemed_by_user_id,
                           redeemed_at,
                           created_at
                      FROM app.referral_codes
                     WHERE code = %s
                     FOR UPDATE
                    """,
                    (normalize_referral_code(referral_code),),
                )
                redeemed_referral = await cur.fetchone()
                if (
                    not redeemed_referral
                    or not redeemed_referral.get("active")
                    or redeemed_referral.get("redeemed_by_user_id") is not None
                    or normalize_referral_email(redeemed_referral.get("email") or "")
                    != normalize_referral_email(normalized_email)
                ):
                    await conn.rollback()
                    raise InvalidReferralCodeError

                start_date, end_date = referral_membership_window(
                    free_days=redeemed_referral.get("free_days"),
                    free_months=redeemed_referral.get("free_months"),
                )
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
                    VALUES (%s, 'referral', 'referral_grant', 'active', NULL, NULL, %s, %s, now(), now())
                    ON CONFLICT (user_id) DO UPDATE
                    SET plan_interval = EXCLUDED.plan_interval,
                        price_id = EXCLUDED.price_id,
                        status = EXCLUDED.status,
                        stripe_customer_id = NULL,
                        stripe_subscription_id = NULL,
                        start_date = EXCLUDED.start_date,
                        end_date = EXCLUDED.end_date,
                        updated_at = now()
                    """,
                    (user_id, start_date, end_date),
                )
                await cur.execute(
                    """
                    UPDATE app.referral_codes
                       SET redeemed_by_user_id = %s,
                           redeemed_at = now()
                     WHERE id = %s
                    """,
                    (user_id, str(redeemed_referral["id"])),
                )

            await conn.commit()
            return {
                "user": dict(user_row),
                "profile": dict(profile_row) if profile_row else None,
                "referral": dict(redeemed_referral) if redeemed_referral else None,
            }


async def get_user_by_email(email: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, email, encrypted_password, created_at, updated_at
            FROM auth.users
            WHERE lower(email) = lower(%s)
            LIMIT 1
            """,
            (email,),
        )
        try:
            row = await cur.fetchone()
        except InterfaceError:
            row = None
        return dict(row) if row else None


async def get_user_by_id(user_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, email, encrypted_password, created_at, updated_at
            FROM auth.users
            WHERE id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        try:
            row = await cur.fetchone()
        except InterfaceError:
            row = None
        return dict(row) if row else None


async def upsert_refresh_token(
    *,
    user_id: str | UUID,
    jti: str,
    token_hash: str,
    expires_at: datetime,
) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.refresh_tokens (user_id, jti, token_hash, issued_at, expires_at, last_used_at)
                VALUES (%s, %s, %s, now(), %s, now())
                ON CONFLICT (jti) DO UPDATE
                  SET token_hash = excluded.token_hash,
                      expires_at = excluded.expires_at,
                      revoked_at = NULL,
                      rotated_at = NULL,
                      last_used_at = now()
                """,
                (user_id, jti, token_hash, expires_at),
            )
            await conn.commit()


async def get_refresh_token(jti: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, user_id, jti, token_hash, expires_at, revoked_at, rotated_at
            FROM app.refresh_tokens
            WHERE jti = %s
            LIMIT 1
            """,
            (jti,),
        )
        try:
            row = await cur.fetchone()
        except InterfaceError:
            row = None
        return dict(row) if row else None


async def revoke_refresh_token(jti: str) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.refresh_tokens
                   SET revoked_at = now()
                 WHERE jti = %s
                """,
                (jti,),
            )
            await conn.commit()


async def touch_refresh_token_as_rotated(jti: str) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.refresh_tokens
                   SET rotated_at = now(),
                       last_used_at = now()
                 WHERE jti = %s
                """,
                (jti,),
            )
            await conn.commit()


async def insert_auth_event(
    *,
    user_id: str | UUID | None,
    email: str | None,
    event: str,
    ip_address: str | None,
    user_agent: str | None,
    metadata: dict[str, Any] | None = None,
) -> None:
    ip_value = ip_address if ip_address and ip_address != "unknown" else None
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.auth_events (user_id, email, event, ip_address, user_agent, metadata)
                VALUES (%s, %s, %s, %s::inet, %s, %s)
                """,
                (
                    str(user_id) if user_id else None,
                    email.lower() if email else None,
                    event,
                    ip_value,
                    user_agent,
                    Jsonb(metadata or {}),
                ),
            )
            await conn.commit()
