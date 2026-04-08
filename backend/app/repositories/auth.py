from __future__ import annotations

from datetime import datetime
import uuid
from typing import Any
from uuid import UUID

from psycopg import InterfaceError, errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool
from .auth_subjects import ensure_auth_subject
from .profiles import get_profile as get_profile_for_user

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
    display_name: str | None,
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

    _add_column(
        "display_name",
        display_name,
        update_expression="COALESCE(app.profiles.display_name, excluded.display_name)",
    )
    _add_column("bio", None)
    _add_column("photo_url", None)
    _add_column("avatar_media_id", None)
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
                display_name=display_name,
            )
            profile_row = await get_profile_for_user(user_id)
            return {
                "user": dict(user_row),
                "profile": profile_row,
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
