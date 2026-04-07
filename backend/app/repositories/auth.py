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
from .auth_subjects import ensure_auth_subject
from .profiles import get_profile as get_profile_for_user
from .referrals import normalize_referral_code, normalize_referral_email

_USER_BY_ID_COLUMNS = (
    "id",
    "email",
    "encrypted_password",
    "email_confirmed_at",
    "confirmed_at",
    "created_at",
    "updated_at",
)
_TABLE_COLUMNS_CACHE: dict[tuple[str, str], set[str]] = {}


class UniqueViolationError(Exception):
    """Raised when attempting to insert a record that already exists."""


class InvalidReferralCodeError(Exception):
    """Raised when a supplied referral code cannot be redeemed."""


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


def _with_missing_keys(row: dict[str, Any], expected_columns: tuple[str, ...]) -> dict[str, Any]:
    for column in expected_columns:
        row.setdefault(column, None)
    return row


async def _upsert_profile_row(
    *,
    user_id: str | UUID,
    email: str,
    display_name: str | None,
    onboarding_state: str,
    role_v2: str,
    role: str,
    is_admin: bool,
) -> dict[str, Any] | None:
    available_columns = await _table_columns("app", "profiles")
    if "user_id" not in available_columns:
        return None

    insert_columns: list[str] = ["user_id"]
    insert_values: list[object] = [user_id]
    update_clauses: list[str] = []

    def _add_column(
        column: str,
        value: object,
        *,
        update_expression: str | None = None,
    ) -> None:
        if column not in available_columns:
            return
        insert_columns.append(column)
        insert_values.append(value)
        if update_expression is not None:
            update_clauses.append(f"{column} = {update_expression}")

    _add_column("email", email, update_expression="excluded.email")
    _add_column(
        "display_name",
        display_name,
        update_expression="COALESCE(app.profiles.display_name, excluded.display_name)",
    )
    _add_column("bio", None)
    _add_column("photo_url", None)
    _add_column("avatar_media_id", None)
    _add_column("onboarding_state", onboarding_state, update_expression="excluded.onboarding_state")
    _add_column("role_v2", role_v2, update_expression="excluded.role_v2")
    _add_column("role", role, update_expression="excluded.role")
    _add_column("is_admin", is_admin, update_expression="excluded.is_admin")
    if "created_at" in available_columns:
        insert_columns.append("created_at")
        insert_values.append("now()")
    if "updated_at" in available_columns:
        insert_columns.append("updated_at")
        insert_values.append("now()")
        update_clauses.append("updated_at = now()")

    placeholders = [
        value if value == "now()" else "%s"
        for value in insert_values
    ]
    params = [value for value in insert_values if value != "now()"]
    returning_columns = [
        column
        for column in (
            "user_id",
            "email",
            "display_name",
            "bio",
            "photo_url",
            "avatar_media_id",
            "created_at",
            "updated_at",
        )
        if column in available_columns
    ]
    if not returning_columns:
        return None
    if not update_clauses:
        update_clauses.append("user_id = excluded.user_id")

    query = f"""
        INSERT INTO app.profiles ({", ".join(insert_columns)})
        VALUES ({", ".join(placeholders)})
        ON CONFLICT (user_id) DO UPDATE
          SET {", ".join(update_clauses)}
        RETURNING {", ".join(returning_columns)}
    """

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


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
    canonical_onboarding_state = "incomplete"
    canonical_role = "learner"
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
                INSERT INTO app.auth_subjects (
                    user_id,
                    onboarding_state,
                    role_v2,
                    role,
                    is_admin
                )
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (user_id) DO NOTHING
                """,
                (
                    user_id,
                    canonical_onboarding_state,
                    canonical_role,
                    canonical_role,
                    False,
                ),
            )

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
            await ensure_auth_subject(
                user_id,
                onboarding_state=canonical_onboarding_state,
                role_v2=canonical_role,
                role=canonical_role,
                is_admin=False,
            )
            await _upsert_profile_row(
                user_id=user_id,
                email=normalized_email,
                display_name=display_name,
                onboarding_state=canonical_onboarding_state,
                role_v2=canonical_role,
                role=canonical_role,
                is_admin=False,
            )
            profile_row = await get_profile_for_user(user_id)
            return {
                "user": dict(user_row),
                "profile": profile_row,
                "referral": dict(redeemed_referral) if redeemed_referral else None,
            }


async def get_user_by_email(email: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id,
                   email,
                   encrypted_password,
                   email_confirmed_at,
                   confirmed_at,
                   created_at,
                   updated_at
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
    available_columns = await _table_columns("auth", "users")
    if "id" not in available_columns:
        return None

    selected_columns = [column for column in _USER_BY_ID_COLUMNS if column in available_columns]
    async with get_conn() as cur:
        await cur.execute(
            f"""
            SELECT {", ".join(selected_columns)}
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
        return _with_missing_keys(dict(row), _USER_BY_ID_COLUMNS) if row else None


async def mark_user_email_verified(email: str) -> dict[str, Any] | None:
    normalized_email = email.strip().lower()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE auth.users
                   SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
                       confirmed_at = COALESCE(confirmed_at, now()),
                       raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                           || '{"email_verified": true}'::jsonb,
                       raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
                           || '{"email_verified": true}'::jsonb,
                       updated_at = now()
                 WHERE lower(email) = lower(%s)
                 RETURNING id, email, email_confirmed_at, confirmed_at
                """,
                (normalized_email,),
            )
            row = await cur.fetchone()
            await conn.commit()
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


async def revoke_refresh_tokens_for_user(user_id: str | UUID) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.refresh_tokens
                   SET revoked_at = now()
                 WHERE user_id = %s
                   AND revoked_at IS NULL
                """,
                (user_id,),
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
