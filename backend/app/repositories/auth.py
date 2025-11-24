from __future__ import annotations

from datetime import datetime
import uuid
from typing import Any
from uuid import UUID

from psycopg import InterfaceError, errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool


class UniqueViolationError(Exception):
    """Raised when attempting to insert a record that already exists."""


async def create_user(
    *,
    email: str,
    hashed_password: str,
    display_name: str | None,
) -> dict[str, Any]:
    """Insert a new auth user + profile."""
    new_id = uuid.uuid4()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO auth.users (id, email, encrypted_password, created_at, updated_at)
                    VALUES (%s, %s, %s, now(), now())
                    RETURNING id, email, created_at, updated_at
                    """,
                    (new_id, email, hashed_password),
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
                (user_id, email, display_name),
            )
            profile_row = await cur.fetchone()

            await conn.commit()
            return {
                "user": dict(user_row),
                "profile": dict(profile_row) if profile_row else None,
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
