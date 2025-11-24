import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import httpx
from jose import jwt

from ..config import settings

logger = logging.getLogger(__name__)


class LiveKitRESTError(RuntimeError):
    """Raised when LiveKit REST API returns an unexpected response."""


def _build_admin_token(video_grants: dict[str, Any]) -> Optional[str]:
    if not settings.livekit_api_key or not settings.livekit_api_secret:
        return None
    now = datetime.now(timezone.utc)
    exp = now + timedelta(minutes=10)
    claims: dict[str, Any] = {
        "iss": settings.livekit_api_key,
        "sub": settings.livekit_api_key,
        "nbf": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "video": video_grants,
        # mark the token as an admin/server token to avoid identity confusion
        "kind": "server",
        "name": "Aveli Server",
    }
    return jwt.encode(claims, settings.livekit_api_secret, algorithm="HS256")


def _build_auth_header(video_grants: dict[str, Any]) -> Optional[str]:
    token = _build_admin_token(video_grants)
    if not token:
        return None
    return f"Bearer {token}"


def _build_url(path: str) -> Optional[str]:
    if not settings.livekit_api_url:
        return None
    base = settings.livekit_api_url.rstrip("/")
    return f"{base}{path}"


async def create_room(
    name: str,
    *,
    metadata: Optional[dict[str, Any]] = None,
    max_participants: Optional[int] = None,
    empty_timeout: int = 0,
) -> Optional[dict[str, Any]]:
    """
    Ensure the LiveKit room exists before the host joins.

    Uses the Twirp RoomService CreateRoom endpoint. Returns the JSON response or None if LiveKit is
    not configured.
    """
    auth_header = _build_auth_header({"roomCreate": True, "roomList": True})
    url = _build_url("/twirp/livekit.RoomService/CreateRoom")
    if not auth_header or not url:
        logger.info("LiveKit REST not configured; skipping CreateRoom call.")
        return None

    payload: dict[str, Any] = {
        "name": name,
        "empty_timeout": empty_timeout,
        "max_participants": max_participants,
    }
    if metadata:
        payload["metadata"] = json.dumps(metadata)

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            response = await client.post(
                url,
                json=payload,
                headers={
                    "Authorization": auth_header,
                    "Content-Type": "application/json",
                },
            )
        except httpx.HTTPError as exc:
            logger.warning("LiveKit CreateRoom request failed: %s", exc)
            raise LiveKitRESTError("CreateRoom request failed") from exc

        if response.status_code >= 400:
            logger.warning(
                "LiveKit CreateRoom failed: status=%s body=%s",
                response.status_code,
                response.text,
            )
            raise LiveKitRESTError(
                f"CreateRoom failed with status {response.status_code}"
            )
        return response.json()


async def end_room(name: str, *, reason: Optional[str] = None) -> None:
    """
    Request LiveKit to end a room when the host finishes a session.
    """
    auth_header = _build_auth_header({"room": name, "roomAdmin": True})
    url = _build_url("/twirp/livekit.RoomService/EndRoom")
    if not auth_header or not url:
        logger.info("LiveKit REST not configured; skipping EndRoom call.")
        return

    payload = {"room": name}
    if reason:
        payload["reason"] = reason

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            response = await client.post(
                url,
                json=payload,
                headers={
                    "Authorization": auth_header,
                    "Content-Type": "application/json",
                },
            )
        except httpx.HTTPError as exc:
            logger.warning("LiveKit EndRoom request failed: %s", exc)
            raise LiveKitRESTError("EndRoom request failed") from exc

        if response.status_code >= 400:
            logger.warning(
                "LiveKit EndRoom failed: status=%s body=%s",
                response.status_code,
                response.text,
            )
            raise LiveKitRESTError(f"EndRoom failed with status {response.status_code}")
