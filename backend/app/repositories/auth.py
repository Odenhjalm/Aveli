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
_CANONICAL_AUTH_EVENT_TYPES = frozenset(
    {
        "admin_bootstrap_consumed",
        "onboarding_completed",
        "teacher_role_granted",
        "teacher_role_revoked",
    }
)


class UniqueViolationError(Exception):
    """Raised when attempting to insert a record that already exists."""


async def _upsert_profile_row(
    *,
    user_id: str | UUID,
    display_name: str | None,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.profiles (
                    user_id,
                    display_name,
                    bio,
                    avatar_media_id,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, now(), now())
                ON CONFLICT (user_id) DO UPDATE
                  SET display_name = COALESCE(app.profiles.display_name, excluded.display_name),
                      updated_at = now()
                RETURNING user_id, display_name, bio, avatar_media_id, created_at, updated_at
                """,
                (user_id, display_name, None, None),
            )
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


async def mark_user_email_verified(email: str) -> dict[str, Any] | None:
    normalized_email = email.strip().lower()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE auth.users
                   SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
                       confirmed_at = COALESCE(confirmed_at, now()),
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
    rotated_from_jti: str | None = None,
) -> None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.refresh_tokens (
                    user_id,
                    jti,
                    token_hash,
                    issued_at,
                    expires_at,
                    last_used_at,
                    rotated_from_jti
                )
                VALUES (%s, %s, %s, now(), %s, now(), %s)
                ON CONFLICT (jti) DO UPDATE
                  SET token_hash = excluded.token_hash,
                      expires_at = excluded.expires_at,
                      rotated_from_jti = excluded.rotated_from_jti,
                      revoked_at = NULL,
                      rotated_at = NULL,
                      last_used_at = now()
                """,
                (user_id, jti, token_hash, expires_at, rotated_from_jti),
            )
            await conn.commit()


async def get_refresh_token(jti: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT jti,
                   user_id,
                   token_hash,
                   issued_at,
                   expires_at,
                   last_used_at,
                   rotated_at,
                   revoked_at,
                   rotated_from_jti
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
    actor_user_id: str | UUID | None,
    subject_user_id: str | UUID,
    event_type: str,
    metadata: dict[str, Any] | None = None,
) -> None:
    normalized_event_type = str(event_type or "").strip()
    if normalized_event_type not in _CANONICAL_AUTH_EVENT_TYPES:
        raise ValueError("Invalid canonical auth event type")

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.auth_events (
                    actor_user_id,
                    subject_user_id,
                    event_type,
                    metadata
                )
                VALUES (%s, %s, %s, %s)
                """,
                (
                    str(actor_user_id) if actor_user_id else None,
                    str(subject_user_id),
                    normalized_event_type,
                    Jsonb(metadata or {}),
                ),
            )
            await conn.commit()
