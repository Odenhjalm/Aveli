from __future__ import annotations

from datetime import datetime
from typing import Any, Mapping
from uuid import uuid4

from psycopg.rows import dict_row

from ..db import get_conn, pool

MembershipRow = dict[str, Any]
_UNSET = object()
_MEMBERSHIP_COLUMNS = (
    "membership_id",
    "user_id",
    "status",
    "effective_at",
    "expires_at",
    "canceled_at",
    "ended_at",
    "source",
    "created_at",
    "updated_at",
)
_MEMBERSHIP_SELECT = f"""
    SELECT {", ".join(_MEMBERSHIP_COLUMNS)}
      FROM app.memberships
"""


async def get_membership(user_id: str, *, conn: Any | None = None) -> MembershipRow | None:
    async def _execute(active_conn: Any) -> MembershipRow | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                {_MEMBERSHIP_SELECT}
                 WHERE user_id = %s
                 LIMIT 1
                """,
                (user_id,),
            )
            row = await cur.fetchone()
        return _normalize_membership_row(row)

    if conn is not None:
        return await _execute(conn)

    async with get_conn() as cur:
        await cur.execute(
            f"""
            {_MEMBERSHIP_SELECT}
             WHERE user_id = %s
             LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
    return _normalize_membership_row(row)


async def list_current_member_user_ids() -> list[str]:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT DISTINCT user_id
              FROM app.memberships
             WHERE status = 'active'
                OR (status = 'canceled' AND expires_at IS NOT NULL AND expires_at > now())
            """
        )
        rows = await cur.fetchall()
    return [str(row["user_id"]) for row in (rows or []) if row.get("user_id")]


async def upsert_membership_record(
    user_id: str,
    *,
    status: str | None = None,
    effective_at: datetime | None | object = _UNSET,
    expires_at: datetime | None | object = _UNSET,
    canceled_at: datetime | None | object = _UNSET,
    ended_at: datetime | None | object = _UNSET,
    source: str | None | object = _UNSET,
    conn: Any | None = None,
) -> MembershipRow:
    if conn is not None:
        existing = await get_membership(user_id, conn=conn)
    else:
        existing = await get_membership(user_id)
    membership_id = str((existing or {}).get("membership_id") or uuid4())

    resolved_status = str(status or (existing or {}).get("status") or "inactive").strip().lower()
    raw_source = _resolve_explicit(source, (existing or {}).get("source"))
    resolved_source = str(raw_source or "").strip().lower()
    if not resolved_source:
        raise RuntimeError("app.memberships requires explicit canonical source")

    values = {
        "membership_id": membership_id,
        "user_id": user_id,
        "status": resolved_status,
        "effective_at": _resolve_explicit(effective_at, (existing or {}).get("effective_at")),
        "expires_at": _resolve_explicit(expires_at, (existing or {}).get("expires_at")),
        "canceled_at": _resolve_explicit(canceled_at, (existing or {}).get("canceled_at")),
        "ended_at": _resolve_explicit(ended_at, (existing or {}).get("ended_at")),
        "source": resolved_source,
    }
    if values["source"] == "referral" and values["expires_at"] is None:
        raise RuntimeError("referral memberships require expires_at")

    async def _execute(active_conn: Any) -> MembershipRow:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                INSERT INTO app.memberships (
                    membership_id,
                    user_id,
                    status,
                    effective_at,
                    expires_at,
                    canceled_at,
                    ended_at,
                    source,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now(), now())
                ON CONFLICT (user_id) DO UPDATE
                SET status = EXCLUDED.status,
                    effective_at = EXCLUDED.effective_at,
                    expires_at = EXCLUDED.expires_at,
                    canceled_at = EXCLUDED.canceled_at,
                    ended_at = EXCLUDED.ended_at,
                    source = EXCLUDED.source,
                    updated_at = now()
                RETURNING {", ".join(_MEMBERSHIP_COLUMNS)}
                """,
                (
                    values["membership_id"],
                    values["user_id"],
                    values["status"],
                    values["effective_at"],
                    values["expires_at"],
                    values["canceled_at"],
                    values["ended_at"],
                    values["source"],
                ),
            )
            row = await cur.fetchone()
        return _normalize_membership_row(row) or {}

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        membership = await _execute(conn)
        await conn.commit()
        return membership


def _resolve_explicit(explicit: Any, fallback: Any) -> Any:
    if explicit is _UNSET:
        return fallback
    return explicit


def _normalize_membership_row(row: Mapping[str, Any] | None) -> MembershipRow | None:
    if row is None:
        return None
    return dict(row)


__all__ = [
    "get_membership",
    "list_current_member_user_ids",
    "upsert_membership_record",
]
