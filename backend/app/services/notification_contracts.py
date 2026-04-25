from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping


SUPPORTED_NOTIFICATION_CHANNELS = {"push", "in_app", "email"}
SUPPORTED_NOTIFICATION_TYPES: tuple[str, ...] = (
    "lesson_drip",
    "purchase",
    "message",
)

_CANONICAL_TYPE_ALIASES = {
    "stripe_course_purchase_fulfilled": "purchase",
    "stripe_membership_activated": "purchase",
}

_DEFAULT_CHANNEL_POLICY: dict[str, tuple[str, ...]] = {
    "lesson_drip": ("in_app", "push"),
    "purchase": ("in_app", "push"),
    "message": ("in_app",),
}


@dataclass(frozen=True)
class NotificationContractPayload:
    type: str
    payload: dict[str, Any]


def _required_text(value: Any, field_name: str) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        raise ValueError(f"{field_name} is required")
    return normalized


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _required_amount(value: Any, field_name: str) -> int:
    if isinstance(value, bool) or value is None:
        raise ValueError(f"{field_name} is required")
    try:
        amount = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field_name} must be an integer") from exc
    if amount < 0:
        raise ValueError(f"{field_name} must be non-negative")
    return amount


def canonical_notification_type(notification_type: str) -> str:
    normalized_type = _required_text(notification_type, "type")
    return _CANONICAL_TYPE_ALIASES.get(normalized_type, normalized_type)


def validate_notification_payload(
    notification_type: str,
    payload: Mapping[str, Any],
) -> NotificationContractPayload:
    if not isinstance(payload, Mapping):
        raise ValueError("payload must be a mapping")

    canonical_type = canonical_notification_type(notification_type)
    if canonical_type == "lesson_drip":
        canonical_payload: dict[str, Any] = {
            "lesson_id": _required_text(payload.get("lesson_id"), "lesson_id"),
            "course_id": _required_text(payload.get("course_id"), "course_id"),
        }
        title = _optional_text(payload.get("title"))
        if title is not None:
            canonical_payload["title"] = title
        return NotificationContractPayload(
            type=canonical_type,
            payload=canonical_payload,
        )

    if canonical_type == "purchase":
        return NotificationContractPayload(
            type=canonical_type,
            payload={
                "product_id": _required_text(payload.get("product_id"), "product_id"),
                "amount": _required_amount(payload.get("amount"), "amount"),
                "currency": _required_text(payload.get("currency"), "currency").lower(),
            },
        )

    if canonical_type == "message":
        return NotificationContractPayload(
            type=canonical_type,
            payload={
                "thread_id": _required_text(payload.get("thread_id"), "thread_id"),
                "message_preview": _required_text(
                    payload.get("message_preview"),
                    "message_preview",
                ),
            },
        )

    raise ValueError(f"unsupported notification type: {canonical_type}")


def default_notification_channels(notification_type: str) -> tuple[str, ...]:
    canonical_type = canonical_notification_type(notification_type)
    try:
        return _DEFAULT_CHANNEL_POLICY[canonical_type]
    except KeyError as exc:
        raise ValueError(f"unsupported notification type: {canonical_type}") from exc


__all__ = [
    "NotificationContractPayload",
    "SUPPORTED_NOTIFICATION_CHANNELS",
    "SUPPORTED_NOTIFICATION_TYPES",
    "canonical_notification_type",
    "default_notification_channels",
    "validate_notification_payload",
]
