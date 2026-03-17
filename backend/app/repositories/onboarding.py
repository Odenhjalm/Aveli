from __future__ import annotations

from typing import Any

from psycopg import errors
from psycopg.rows import dict_row

from ..db import get_conn, pool

OnboardingRow = dict[str, Any]


async def get_user_onboarding(user_id: str) -> OnboardingRow | None:
    async with get_conn() as cur:
        try:
            await cur.execute(
                """
                SELECT user_id,
                       selected_intro_course_id,
                       profile_completed_at,
                       onboarding_completed_at,
                       created_at,
                       updated_at
                  FROM app.user_onboarding
                 WHERE user_id = %s
                 LIMIT 1
                """,
                (user_id,),
            )
        except errors.UndefinedTable:
            return None
        row = await cur.fetchone()
    return dict(row) if row else None


async def ensure_user_onboarding(user_id: str) -> OnboardingRow | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.user_onboarding (
                        user_id,
                        created_at,
                        updated_at
                    )
                    VALUES (%s, now(), now())
                    ON CONFLICT (user_id) DO UPDATE
                    SET updated_at = app.user_onboarding.updated_at
                    RETURNING user_id,
                              selected_intro_course_id,
                              profile_completed_at,
                              onboarding_completed_at,
                              created_at,
                              updated_at
                    """,
                    (user_id,),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def set_selected_intro_course(
    user_id: str,
    *,
    course_id: str,
) -> OnboardingRow | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.user_onboarding (
                        user_id,
                        selected_intro_course_id,
                        created_at,
                        updated_at
                    )
                    VALUES (%s, %s, now(), now())
                    ON CONFLICT (user_id) DO UPDATE
                    SET selected_intro_course_id = EXCLUDED.selected_intro_course_id,
                        updated_at = now()
                    RETURNING user_id,
                              selected_intro_course_id,
                              profile_completed_at,
                              onboarding_completed_at,
                              created_at,
                              updated_at
                    """,
                    (user_id, course_id),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def mark_profile_completed(user_id: str) -> OnboardingRow | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.user_onboarding (
                        user_id,
                        profile_completed_at,
                        created_at,
                        updated_at
                    )
                    VALUES (%s, now(), now(), now())
                    ON CONFLICT (user_id) DO UPDATE
                    SET profile_completed_at = COALESCE(
                            app.user_onboarding.profile_completed_at,
                            EXCLUDED.profile_completed_at
                        ),
                        updated_at = now()
                    RETURNING user_id,
                              selected_intro_course_id,
                              profile_completed_at,
                              onboarding_completed_at,
                              created_at,
                              updated_at
                    """,
                    (user_id,),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def mark_onboarding_completed(user_id: str) -> OnboardingRow | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.user_onboarding (
                        user_id,
                        onboarding_completed_at,
                        created_at,
                        updated_at
                    )
                    VALUES (%s, now(), now(), now())
                    ON CONFLICT (user_id) DO UPDATE
                    SET onboarding_completed_at = COALESCE(
                            app.user_onboarding.onboarding_completed_at,
                            EXCLUDED.onboarding_completed_at
                        ),
                        updated_at = now()
                    RETURNING user_id,
                              selected_intro_course_id,
                              profile_completed_at,
                              onboarding_completed_at,
                              created_at,
                              updated_at
                    """,
                    (user_id,),
                )
            except errors.UndefinedTable:
                await conn.rollback()
                return None
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


__all__ = [
    "ensure_user_onboarding",
    "get_user_onboarding",
    "mark_onboarding_completed",
    "mark_profile_completed",
    "set_selected_intro_course",
]
