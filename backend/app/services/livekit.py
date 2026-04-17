from __future__ import annotations

from typing import Any, Optional

_PAUSED_DETAIL = "LiveKit är pausat."


class LiveKitRESTError(RuntimeError):
    """Raised when the paused LiveKit REST surface is invoked."""


async def create_room(
    name: str,
    *,
    metadata: Optional[dict[str, Any]] = None,
    max_participants: Optional[int] = None,
    empty_timeout: int = 0,
) -> None:
    del name, metadata, max_participants, empty_timeout
    raise LiveKitRESTError(_PAUSED_DETAIL)


async def end_room(name: str, *, reason: Optional[str] = None) -> None:
    del name, reason
    raise LiveKitRESTError(_PAUSED_DETAIL)
