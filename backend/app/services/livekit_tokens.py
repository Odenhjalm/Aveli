from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Any, Literal, Optional
from uuid import UUID

from jose import jwt

from ..config import settings


class LiveKitTokenConfigError(RuntimeError):
    """Raised when LiveKit settings are missing for token generation."""


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
    """
    Build a LiveKit access token for the given user and seminar context.
    """
    if not settings.livekit_api_key or not settings.livekit_api_secret:
        raise LiveKitTokenConfigError("LiveKit API key/secret missing.")

    now = datetime.now(timezone.utc)
    expires = now + timedelta(minutes=ttl_minutes)

    publish_data = can_publish if can_publish_data is None else can_publish_data

    video_grant: dict[str, Any] = {
        "roomJoin": True,
        "room": room_name,
        "canPublish": can_publish,
        "canPublishData": publish_data,
        "canSubscribe": can_subscribe,
    }
    if can_create_room:
        video_grant["roomCreate"] = True

    metadata: dict[str, Any] = {
        "seminar_id": str(seminar_id),
        "user_id": str(user_id),
        "role": role,
    }
    if session_id:
        metadata["session_id"] = str(session_id)
    if display_name:
        metadata["display_name"] = display_name
    if avatar_url:
        metadata["avatar_url"] = avatar_url
    if extra_metadata:
        metadata.update(extra_metadata)

    claims: dict[str, Any] = {
        "iss": settings.livekit_api_key,
        "sub": settings.livekit_api_key,
        "nbf": int(now.timestamp()),
        "exp": int(expires.timestamp()),
        "name": display_name or "Aveli Participant",
        "identity": identity,
        "video": video_grant,
    }

    # LiveKit expects the metadata claim to be a JSON string when present.
    if metadata:
        claims["metadata"] = json.dumps(metadata)

    # Maintain backwards compatibility with older LiveKit deployments by keeping the legacy
    # grants structure alongside the new top-level claims.
    claims["grants"] = {
        "video": dict(video_grant),
        "metadata": dict(metadata),
    }

    return jwt.encode(claims, settings.livekit_api_secret, algorithm="HS256")
