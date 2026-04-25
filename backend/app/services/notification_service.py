from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Sequence
from urllib.parse import quote

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import pool
from .notification_contracts import (
    SUPPORTED_NOTIFICATION_CHANNELS,
    SUPPORTED_NOTIFICATION_TYPES,
    NotificationContractPayload,
    canonical_notification_type,
    default_notification_channels,
    validate_notification_payload,
)


DEFAULT_NOTIFICATION_CHANNELS: tuple[str, ...] = ("in_app",)


@dataclass(frozen=True)
class NotificationCreateResult:
    notification: dict[str, Any]
    created: bool
    delivery_count: int


@dataclass(frozen=True)
class DeviceRegistrationResult:
    device: dict[str, Any]


@dataclass(frozen=True)
class NotificationPreferenceResult:
    preference: dict[str, Any]


@dataclass(frozen=True)
class NotificationHeaderReadModel:
    show_notifications_bar: bool
    notifications: list[dict[str, Any]]


def _required_text(value: str, field_name: str) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        raise ValueError(f"{field_name} is required")
    return normalized


def _normalize_type(type: str) -> str:
    normalized_type = canonical_notification_type(_required_text(type, "type"))
    if normalized_type not in SUPPORTED_NOTIFICATION_TYPES:
        raise ValueError(f"unsupported notification type: {normalized_type}")
    return normalized_type


def _normalize_payload(payload: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, Mapping):
        raise ValueError("payload must be a mapping")
    return dict(payload)


def _optional_payload_text(payload: Mapping[str, Any], field_name: str) -> str | None:
    value = payload.get(field_name)
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _route_path(*parts: str) -> str:
    encoded_parts = [
        quote(str(part).strip(), safe="")
        for part in parts
        if str(part).strip()
    ]
    return "/" + "/".join(encoded_parts) if encoded_parts else "/"


def _notification_header_item(row: Mapping[str, Any]) -> dict[str, Any]:
    notification_type = _normalize_type(str(row.get("type") or ""))
    raw_payload = row.get("payload")
    if raw_payload is None:
        raw_payload = row.get("payload_json")
    payload = _normalize_payload(raw_payload if isinstance(raw_payload, Mapping) else {})
    notification_id = _required_text(str(row.get("id") or ""), "id")

    if notification_type == "lesson_drip":
        lesson_id = _optional_payload_text(payload, "lesson_id")
        return {
            "id": notification_id,
            "title": "Ny lektion är upplåst",
            "subtitle": _optional_payload_text(payload, "title"),
            "cta_label": "Öppna lektionen" if lesson_id else None,
            "cta_url": _route_path("lesson", lesson_id) if lesson_id else None,
        }

    if notification_type == "purchase":
        return {
            "id": notification_id,
            "title": "Köpet är klart",
            "subtitle": "Din åtkomst är aktiverad.",
            "cta_label": "Visa kurser",
            "cta_url": "/courses",
        }

    if notification_type == "message":
        return {
            "id": notification_id,
            "title": "Nytt meddelande",
            "subtitle": _optional_payload_text(payload, "message_preview"),
            "cta_label": "Öppna meddelanden",
            "cta_url": "/messages",
        }

    raise ValueError(f"unsupported notification type: {notification_type}")


def _notification_header_read_model(
    rows: Sequence[Mapping[str, Any]],
) -> NotificationHeaderReadModel:
    notifications = [_notification_header_item(row) for row in rows]
    return NotificationHeaderReadModel(
        show_notifications_bar=bool(notifications),
        notifications=notifications,
    )


async def _hydrate_purchase_payload_from_order(
    active_conn: Any,
    payload: Mapping[str, Any],
) -> dict[str, Any]:
    if all(
        payload.get(field) is not None
        for field in ("product_id", "amount", "currency")
    ):
        return dict(payload)

    order_id = _required_text(str(payload.get("order_id") or ""), "order_id")
    async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            select course_id::text as course_id,
                   bundle_id::text as bundle_id,
                   order_type,
                   amount_cents,
                   currency
              from app.orders
             where id = %s::uuid
             limit 1
            """,
            (order_id,),
        )
        row = await cur.fetchone()

    if row is None:
        raise ValueError("purchase notification order_id does not resolve")

    order_type = str(row.get("order_type") or "").strip()
    product_id = (
        payload.get("product_id")
        or row.get("course_id")
        or row.get("bundle_id")
    )
    if not product_id and order_type == "subscription":
        product_id = "membership"
    if not product_id:
        product_id = order_type
    hydrated = dict(payload)
    hydrated["product_id"] = product_id
    hydrated["amount"] = (
        payload.get("amount")
        if payload.get("amount") is not None
        else row.get("amount_cents")
    )
    hydrated["currency"] = (
        payload.get("currency")
        if payload.get("currency") is not None
        else row.get("currency")
    )
    return hydrated


async def _validated_contract_payload(
    active_conn: Any,
    notification_type: str,
    payload: Mapping[str, Any],
) -> NotificationContractPayload:
    try:
        return validate_notification_payload(notification_type, payload)
    except ValueError as exc:
        missing_canonical_purchase_fields = any(
            payload.get(field) is None
            for field in ("product_id", "amount", "currency")
        )
        if not missing_canonical_purchase_fields:
            raise
        raw_type = notification_type.strip()
        if raw_type not in {
            "purchase",
            "stripe_course_purchase_fulfilled",
            "stripe_membership_activated",
        }:
            raise
        if payload.get("order_id") is None:
            raise exc
        hydrated_payload = await _hydrate_purchase_payload_from_order(
            active_conn,
            payload,
        )
        return validate_notification_payload(notification_type, hydrated_payload)


def _preference_payload(
    notification_type: str,
    push_enabled: bool,
    in_app_enabled: bool,
) -> dict[str, Any]:
    return {
        "type": notification_type,
        "push_enabled": bool(push_enabled),
        "in_app_enabled": bool(in_app_enabled),
    }


def _default_preference_payload(notification_type: str) -> dict[str, Any]:
    channels = set(default_notification_channels(notification_type))
    return _preference_payload(
        notification_type,
        push_enabled="push" in channels,
        in_app_enabled="in_app" in channels,
    )


def _channels_from_preference(preference: Mapping[str, Any]) -> tuple[str, ...]:
    channels: list[str] = []
    if bool(preference.get("in_app_enabled")):
        channels.append("in_app")
    if bool(preference.get("push_enabled")):
        channels.append("push")
    return tuple(channels)


async def _get_preference_row(
    active_conn: Any,
    *,
    user_id: str,
    notification_type: str,
) -> dict[str, Any] | None:
    async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            select user_id::text as user_id,
                   type,
                   push_enabled,
                   in_app_enabled,
                   created_at,
                   updated_at
              from app.notification_preferences
             where user_id = %s::uuid
               and type = %s
             limit 1
            """,
            (user_id, notification_type),
        )
        row = await cur.fetchone()
    return dict(row) if row else None


async def resolve_notification_channels(
    type: str,
    user_id: str,
    *,
    conn: Any | None = None,
) -> tuple[str, ...]:
    normalized_user_id = _required_text(user_id, "user_id")
    normalized_type = _normalize_type(type)

    async def _execute(active_conn: Any) -> tuple[str, ...]:
        row = await _get_preference_row(
            active_conn,
            user_id=normalized_user_id,
            notification_type=normalized_type,
        )
        if row is None:
            return default_notification_channels(normalized_type)
        return _channels_from_preference(row)

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        return await _execute(active_conn)


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
    raw_payload = _normalize_payload(payload)
    # Channel selection is now backend policy. The parameter remains only so
    # existing call sites keep their compatibility while policy remains central.
    del channels

    async def _execute(active_conn: Any) -> NotificationCreateResult:
        contract_payload = await _validated_contract_payload(
            active_conn,
            normalized_type,
            raw_payload,
        )
        normalized_channels = await resolve_notification_channels(
            contract_payload.type,
            normalized_user_id,
            conn=active_conn,
        )
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
                          read_at,
                          created_at
                """,
                (
                    normalized_user_id,
                    contract_payload.type,
                    Jsonb(contract_payload.payload),
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
                           read_at,
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


async def register_device(
    *,
    user_id: str,
    push_token: str,
    platform: str,
    conn: Any | None = None,
) -> DeviceRegistrationResult:
    normalized_user_id = _required_text(user_id, "user_id")
    normalized_push_token = _required_text(push_token, "push_token")
    normalized_platform = _required_text(platform, "platform")

    async def _execute(active_conn: Any) -> DeviceRegistrationResult:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.user_devices (
                    user_id,
                    push_token,
                    platform,
                    active
                )
                values (
                    %s::uuid,
                    %s,
                    %s,
                    true
                )
                on conflict (push_token) do update
                  set user_id = excluded.user_id,
                      platform = excluded.platform,
                      active = true
                returning id::text as id,
                          user_id::text as user_id,
                          push_token,
                          platform,
                          active,
                          created_at
                """,
                (normalized_user_id, normalized_push_token, normalized_platform),
            )
            row = await cur.fetchone()
            if row is None:
                raise RuntimeError("device registration returned no row")
            return DeviceRegistrationResult(device=dict(row))

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        result = await _execute(active_conn)
        await active_conn.commit()
        return result


async def deactivate_device(
    *,
    user_id: str,
    device_id: str,
    conn: Any | None = None,
) -> bool:
    normalized_user_id = _required_text(user_id, "user_id")
    normalized_device_id = _required_text(device_id, "device_id")

    async def _execute(active_conn: Any) -> bool:
        async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                update app.user_devices
                   set active = false
                 where id = %s::uuid
                   and user_id = %s::uuid
                   and active = true
                """,
                (normalized_device_id, normalized_user_id),
            )
            return cur.rowcount > 0

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        deactivated = await _execute(active_conn)
        await active_conn.commit()
        return deactivated


async def mark_notification_read(
    *,
    user_id: str,
    notification_id: str,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    normalized_user_id = _required_text(user_id, "user_id")
    normalized_notification_id = _required_text(notification_id, "notification_id")

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                update app.notifications
                   set read_at = coalesce(read_at, clock_timestamp())
                 where id = %s::uuid
                   and user_id = %s::uuid
                returning id::text as id,
                          user_id::text as user_id,
                          type,
                          payload_json as payload,
                          read_at,
                          (read_at is not null) as is_read,
                          created_at
                """,
                (normalized_notification_id, normalized_user_id),
            )
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        result = await _execute(active_conn)
        await active_conn.commit()
        return result


async def mark_notification_read_for_header(
    *,
    user_id: str,
    notification_id: str,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    row = await mark_notification_read(
        user_id=user_id,
        notification_id=notification_id,
        conn=conn,
    )
    if row is None:
        return None
    return _notification_header_item(row)


async def list_notifications_for_user(
    *,
    user_id: str,
    limit: int = 50,
    conn: Any | None = None,
) -> list[dict[str, Any]]:
    normalized_user_id = _required_text(user_id, "user_id")
    normalized_limit = max(1, min(100, int(limit)))

    async def _execute(active_conn: Any) -> list[dict[str, Any]]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select id::text as id,
                       user_id::text as user_id,
                       type,
                       payload_json as payload,
                       read_at,
                       (read_at is not null) as is_read,
                       created_at
                  from app.notifications
                 where user_id = %s::uuid
                   and exists (
                       select 1
                         from app.notification_deliveries as d
                        where d.notification_id = app.notifications.id
                          and d.channel = 'in_app'
                   )
                 order by created_at desc, id desc
                 limit %s
                """,
                (normalized_user_id, normalized_limit),
            )
            return [dict(row) for row in await cur.fetchall()]

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        return await _execute(active_conn)


async def list_notification_header_read_model(
    *,
    user_id: str,
    limit: int = 50,
    conn: Any | None = None,
) -> NotificationHeaderReadModel:
    rows = await list_notifications_for_user(
        user_id=user_id,
        limit=limit,
        conn=conn,
    )
    return _notification_header_read_model(rows)


async def list_notification_preferences(
    *,
    user_id: str,
    conn: Any | None = None,
) -> list[dict[str, Any]]:
    normalized_user_id = _required_text(user_id, "user_id")

    async def _execute(active_conn: Any) -> list[dict[str, Any]]:
        preferences: list[dict[str, Any]] = []
        for notification_type in SUPPORTED_NOTIFICATION_TYPES:
            row = await _get_preference_row(
                active_conn,
                user_id=normalized_user_id,
                notification_type=notification_type,
            )
            if row is None:
                preferences.append(_default_preference_payload(notification_type))
            else:
                preferences.append(
                    _preference_payload(
                        notification_type,
                        push_enabled=bool(row["push_enabled"]),
                        in_app_enabled=bool(row["in_app_enabled"]),
                    )
                )
        return preferences

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        return await _execute(active_conn)


async def set_notification_preference(
    *,
    user_id: str,
    type: str,
    push_enabled: bool,
    in_app_enabled: bool,
    conn: Any | None = None,
) -> NotificationPreferenceResult:
    normalized_user_id = _required_text(user_id, "user_id")
    normalized_type = _normalize_type(type)

    async def _execute(active_conn: Any) -> NotificationPreferenceResult:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.notification_preferences (
                    user_id,
                    type,
                    push_enabled,
                    in_app_enabled
                )
                values (
                    %s::uuid,
                    %s,
                    %s,
                    %s
                )
                on conflict (user_id, type) do update
                  set push_enabled = excluded.push_enabled,
                      in_app_enabled = excluded.in_app_enabled,
                      updated_at = clock_timestamp()
                returning user_id::text as user_id,
                          type,
                          push_enabled,
                          in_app_enabled,
                          created_at,
                          updated_at
                """,
                (
                    normalized_user_id,
                    normalized_type,
                    bool(push_enabled),
                    bool(in_app_enabled),
                ),
            )
            row = await cur.fetchone()
        if row is None:
            raise RuntimeError("notification preference upsert returned no row")
        return NotificationPreferenceResult(
            preference=_preference_payload(
                str(row["type"]),
                push_enabled=bool(row["push_enabled"]),
                in_app_enabled=bool(row["in_app_enabled"]),
            )
        )

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore[attr-defined]
        result = await _execute(active_conn)
        await active_conn.commit()
        return result


__all__ = [
    "DEFAULT_NOTIFICATION_CHANNELS",
    "DeviceRegistrationResult",
    "NotificationCreateResult",
    "NotificationHeaderReadModel",
    "NotificationPreferenceResult",
    "SUPPORTED_NOTIFICATION_CHANNELS",
    "create_notification",
    "deactivate_device",
    "list_notification_header_read_model",
    "list_notifications_for_user",
    "list_notification_preferences",
    "mark_notification_read",
    "mark_notification_read_for_header",
    "register_device",
    "resolve_notification_channels",
    "set_notification_preference",
]
