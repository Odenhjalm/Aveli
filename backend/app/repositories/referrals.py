from __future__ import annotations

from typing import Any

from psycopg import errors
from psycopg.rows import dict_row

from ..db import get_conn, pool

ReferralRow = dict[str, Any]


class UniqueReferralCodeError(Exception):
    """Raised when a generated referral code collides with an existing one."""


def normalize_referral_code(code: str) -> str:
    return code.strip().upper()


def normalize_referral_email(email: str) -> str:
    return email.strip().lower()


async def create_referral_code(
    *,
    teacher_id: str,
    code: str,
    email: str,
    free_days: int | None = None,
    free_months: int | None = None,
) -> ReferralRow:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    INSERT INTO app.referral_codes (
                      code,
                      teacher_id,
                      email,
                      free_days,
                      free_months,
                      active,
                      created_at
                    )
                    VALUES (%s, %s, %s, %s, %s, true, now())
                    RETURNING
                      id,
                      code,
                      teacher_id,
                      email,
                      free_days,
                      free_months,
                      active,
                      redeemed_by_user_id,
                      redeemed_at,
                      created_at
                    """,
                    (
                        normalize_referral_code(code),
                        teacher_id,
                        normalize_referral_email(email),
                        free_days,
                        free_months,
                    ),
                )
            except errors.UniqueViolation as exc:
                await conn.rollback()
                raise UniqueReferralCodeError from exc
            row = await cur.fetchone()
            await conn.commit()
    return dict(row)


async def get_referral_by_code(code: str) -> ReferralRow | None:
    async with get_conn() as cur:
        try:
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
                 LIMIT 1
                """,
                (normalize_referral_code(code),),
            )
        except errors.UndefinedTable:
            return None
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_redeemable_referral(code: str, email: str) -> ReferralRow | None:
    async with get_conn() as cur:
        try:
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
                   AND lower(email) = lower(%s)
                   AND active = true
                   AND redeemed_by_user_id IS NULL
                 LIMIT 1
                """,
                (normalize_referral_code(code), normalize_referral_email(email)),
            )
        except errors.UndefinedTable:
            return None
        row = await cur.fetchone()
    return dict(row) if row else None


__all__ = [
    "ReferralRow",
    "UniqueReferralCodeError",
    "create_referral_code",
    "get_referral_by_code",
    "get_redeemable_referral",
    "normalize_referral_code",
    "normalize_referral_email",
]
