from __future__ import annotations

from typing import Any, Literal, Optional
from uuid import UUID

_PAUSED_DETAIL = "LiveKit är pausat."


class LiveKitTokenConfigError(RuntimeError):
    """Raised when the paused LiveKit token surface is invoked."""


def build_token(
    *,
    seminar_id: UUID,
    session_id: Optional[UUID],
    user_id: UUID,
    identity: str,
    display_name: Optional[str],
    avatar_url: Optional[str],
    role: Literal["host", "participant"],
    room_name: str,
    can_create_room: bool = False,
    can_publish: bool = True,
    can_publish_data: Optional[bool] = None,
    can_subscribe: bool = True,
    ttl_minutes: int = 60,
    extra_metadata: Optional[dict[str, Any]] = None,
) -> str:
    del (
        seminar_id,
        session_id,
        user_id,
        identity,
        display_name,
        avatar_url,
        role,
        room_name,
        can_create_room,
        can_publish,
        can_publish_data,
        can_subscribe,
        ttl_minutes,
        extra_metadata,
    )
    raise LiveKitTokenConfigError(_PAUSED_DETAIL)
