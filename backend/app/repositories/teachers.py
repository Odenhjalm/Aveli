from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool

TEACHER_COLUMNS = """
    id, profile_id, stripe_connect_account_id,
    payout_split_pct, onboarded_at, charges_enabled,
    payouts_enabled, requirements_due, status,
    created_at, updated_at
"""


async def get_teacher(profile_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT {cols}
              FROM app.teachers
             WHERE profile_id = %s
             LIMIT 1
            """.format(cols=TEACHER_COLUMNS),
            (profile_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def get_teacher_by_account(account_id: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT {cols}
              FROM app.teachers
             WHERE stripe_connect_account_id = %s
             LIMIT 1
            """.format(cols=TEACHER_COLUMNS),
            (account_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def upsert_teacher(
    profile_id: str | UUID,
    *,
    stripe_connect_account_id: str | None = None,
    payout_split_pct: int | None = None,
    onboarded_at: datetime | None = None,
    charges_enabled: bool | None = None,
    payouts_enabled: bool | None = None,
    requirements_due: dict[str, Any] | None = None,
    status: str | None = None,
) -> dict[str, Any]:
    insert_payout = payout_split_pct if payout_split_pct is not None else 100
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.teachers (
                    profile_id,
                    stripe_connect_account_id,
                    payout_split_pct,
                    onboarded_at,
                    charges_enabled,
                    payouts_enabled,
                    requirements_due,
                    status,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now(), now())
                ON CONFLICT (profile_id) DO UPDATE
                   SET stripe_connect_account_id = COALESCE(excluded.stripe_connect_account_id, app.teachers.stripe_connect_account_id),
                       payout_split_pct = COALESCE(%s, app.teachers.payout_split_pct),
                       onboarded_at = COALESCE(excluded.onboarded_at, app.teachers.onboarded_at),
                       charges_enabled = COALESCE(excluded.charges_enabled, app.teachers.charges_enabled),
                       payouts_enabled = COALESCE(excluded.payouts_enabled, app.teachers.payouts_enabled),
                       requirements_due = COALESCE(excluded.requirements_due, app.teachers.requirements_due),
                       status = COALESCE(excluded.status, app.teachers.status),
                       updated_at = now()
                RETURNING {cols}
                """.format(cols=TEACHER_COLUMNS),
                (
                    profile_id,
                    stripe_connect_account_id,
                    insert_payout,
                    onboarded_at,
                    charges_enabled if charges_enabled is not None else False,
                    payouts_enabled if payouts_enabled is not None else False,
                    Jsonb(requirements_due or {}),
                    status or "pending",
                    payout_split_pct,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return dict(row)


async def update_teacher_status(
    profile_id: str | UUID,
    *,
    stripe_connect_account_id: str | None = None,
    charges_enabled: bool | None = None,
    payouts_enabled: bool | None = None,
    requirements_due: dict[str, Any] | None = None,
    status: str | None = None,
    onboarded_at: datetime | None = None,
) -> dict[str, Any] | None:
    fields: list[str] = []
    params: list[Any] = []
    if stripe_connect_account_id is not None:
        fields.append("stripe_connect_account_id = %s")
        params.append(stripe_connect_account_id)
    if charges_enabled is not None:
        fields.append("charges_enabled = %s")
        params.append(charges_enabled)
    if payouts_enabled is not None:
        fields.append("payouts_enabled = %s")
        params.append(payouts_enabled)
    if requirements_due is not None:
        fields.append("requirements_due = %s")
        params.append(Jsonb(requirements_due))
    if status is not None:
        fields.append("status = %s")
        params.append(status)
    if onboarded_at is not None:
        fields.append("onboarded_at = %s")
        params.append(onboarded_at)

    if not fields:
        return await get_teacher(profile_id)

    params.extend([profile_id])

    query = """
        UPDATE app.teachers
           SET {sets}, updated_at = now()
         WHERE profile_id = %s
         RETURNING {cols}
    """.format(
        sets=", ".join(fields),
        cols=TEACHER_COLUMNS,
    )

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None
