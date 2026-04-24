from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import pool


DEFAULT_NOTIFICATION_CHANNELS: tuple[str, ...] = ("in_app",)
SUPPORTED_NOTIFICATION_CHANNELS = {"push", "in_app", "email"}


@dataclass(frozen=True)
class NotificationCreateResult:
    notification: dict[str, Any]
    created: bool
    delivery_count: int


def _required_text(value: str, field_name: str) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        raise ValueError(f"{field_name} is required")
    return normalized


def _normalize_payload(payload: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, Mapping):
        raise ValueError("payload must be a mapping")
    return dict(payload)


def _normalize_channels(channels: Sequence[str] | None) -> tuple[str, ...]:
    raw_channels = channels if channels is not None else DEFAULT_NOTIFICATION_CHANNELS
    normalized: list[str] = []
    for channel in raw_channels:
        value = _required_text(str(channel), "channel")
        if value not in SUPPORTED_NOTIFICATION_CHANNELS:
            raise ValueError(f"unsupported notification channel: {value}")
        if value not in normalized:
            normalized.append(value)
    if not normalized:
        raise ValueError("at least one notification channel is required")
    return tuple(normalized)


async def create_notification(
    user_id: str,
    type: str,
    payload: Mapping[str, Any],
    dedup_key: str,
    *,
    channels: Sequence[str] | None = None,
    conn: Any | None = None,
) -> NotificationCreateResult:
    normalized_user_id = _required_text(user_id, "user_id")
    normalized_type = _required_text(type, "type")
    normalized_dedup_key = _required_text(dedup_key, "dedup_key")
    normalized_payload = _normalize_payload(payload)
    normalized_channels = _normalize_channels(channels)

    async def _execute(active_conn: Any) -> NotificationCreateResult:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.notifications (
                    user_id,
                    type,
                    payload_json,
                    dedup_key
                )
                values (
                    %s::uuid,
                    %s,
                    %s,
                    %s
                )
                on conflict (dedup_key) do nothing
                returning id::text as id,
                          user_id::text as user_id,
                          type,
                          payload_json,
                          dedup_key,
                          created_at
                """,
                (
                    normalized_user_id,
                    normalized_type,
                    Jsonb(normalized_payload),
                    normalized_dedup_key,
                ),
            )
            row = await cur.fetchone()
            created = row is not None

            if row is None:
                await cur.execute(
                    """
                    select id::text as id,
                           user_id::text as user_id,
                           type,
                           payload_json,
                           dedup_key,
                           created_at
                      from app.notifications
                     where dedup_key = %s
                     limit 1
                    """,
                    (normalized_dedup_key,),
                )
                row = await cur.fetchone()
                if row is None:
                    raise RuntimeError("notification dedup lookup returned no row")
                return NotificationCreateResult(
                    notification=dict(row),
                    created=False,
                    delivery_count=0,
                )

            await cur.execute(
                """
                insert into app.notification_deliveries (
                    notification_id,
                    channel
                )
                select %s::uuid,
                       channel
                  from unnest(%s::text[]) as configured(channel)
                on conflict (notification_id, channel) do nothing
                returning id
                """,
                (row["id"], list(normalized_channels)),
            )
            delivery_rows = await cur.fetchall()
            return NotificationCreateResult(
                notification=dict(row),
                created=created,
                delivery_count=len(delivery_rows),
            )

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        result = await _execute(active_conn)
        await active_conn.commit()
        return result


__all__ = [
    "DEFAULT_NOTIFICATION_CHANNELS",
    "NotificationCreateResult",
    "create_notification",
]
