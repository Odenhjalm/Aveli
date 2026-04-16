from __future__ import annotations

from typing import Any, Mapping

from ..services import subscription_service


def is_membership_checkout_session(payload: Mapping[str, Any]) -> bool:
    return subscription_service.is_membership_checkout_session(payload)


def is_membership_event_type(event_type: str | None) -> bool:
    return subscription_service.is_membership_event_type(event_type)


async def handle_event(event: Mapping[str, Any]) -> None:
    await subscription_service.process_event(event)


async def ensure_completed_event_effect_applied(event: Mapping[str, Any]) -> bool:
    return await subscription_service.ensure_completed_event_effect_applied(event)
