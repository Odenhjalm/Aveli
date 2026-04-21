from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg.rows import dict_row

from ..db import get_conn, pool

_VALID_ONBOARDING_STATES = frozenset({"incomplete", "welcome_pending", "completed"})
_VALID_ROLES = frozenset({"learner", "teacher", "admin"})
_CANONICAL_INITIAL_ONBOARDING_STATE = "incomplete"
_CANONICAL_INITIAL_ROLE = "learner"


def _normalize_text(value: object) -> str:
    return str(value or "").strip().lower()


def _validated_onboarding_state(value: object) -> str:
    normalized = _normalize_text(value)
    if normalized not in _VALID_ONBOARDING_STATES:
        raise ValueError("Invalid canonical onboarding_state")
    return normalized


def _validated_initial_onboarding_state(value: object) -> str:
    normalized = _validated_onboarding_state(value)
    if normalized == "completed":
        raise ValueError("Auth subject creation cannot complete onboarding")
    if normalized == "welcome_pending":
        raise ValueError("Auth subject creation cannot skip create-profile")
    return normalized


def _validated_role(value: object) -> str:
    normalized = _normalize_text(value)
    if normalized not in _VALID_ROLES:
        raise ValueError("Invalid canonical role")
    return normalized


async def get_auth_subject(user_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT user_id,
                   email,
                   onboarding_state,
                   role::text as role
            FROM app.auth_subjects
            WHERE user_id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def ensure_auth_subject(
    user_id: str | UUID,
    *,
    email: str | None = None,
    onboarding_state: str,
    role: str,
) -> dict[str, Any] | None:
    validated_onboarding_state = _validated_initial_onboarding_state(onboarding_state)
    validated_role = _validated_role(role)

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.auth_subjects (
                    user_id,
                    email,
                    onboarding_state,
                    role
                )
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (user_id) DO NOTHING
                RETURNING user_id, email, onboarding_state, role::text as role
                """,
                (
                    user_id,
                    email,
                    validated_onboarding_state,
                    validated_role,
                ),
            )
            row = await cur.fetchone()
            if row is None:
                await cur.execute(
                    """
                    SELECT user_id, email, onboarding_state, role::text as role
                    FROM app.auth_subjects
                    WHERE user_id = %s
                    LIMIT 1
                    """,
                    (user_id,),
                )
                row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def ensure_authenticated_auth_subject(
    user_id: str | UUID,
    *,
    email: str | None = None,
) -> dict[str, Any] | None:
    normalized_email = (
        str(email).strip().lower() or None if email is not None else None
    )
    return await ensure_auth_subject(
        user_id,
        email=normalized_email,
        onboarding_state=_CANONICAL_INITIAL_ONBOARDING_STATE,
        role=_CANONICAL_INITIAL_ROLE,
    )


async def set_role_authority(
    user_id: str | UUID,
    *,
    role: str,
) -> dict[str, Any] | None:
    validated_role = _validated_role(role)
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET role = %s
                 WHERE user_id = %s
                 RETURNING user_id, email, onboarding_state, role::text as role
                """,
                (validated_role, user_id),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None


async def mark_create_profile_step_complete(
    user_id: str | UUID,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET onboarding_state = 'welcome_pending'
                 WHERE user_id = %s
                   AND onboarding_state = 'incomplete'
                 RETURNING user_id, email, onboarding_state, role::text as role
                """,
                (user_id,),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None
