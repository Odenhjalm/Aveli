from __future__ import annotations

from typing import Any, Optional


def _seminars_disabled() -> RuntimeError:
    return RuntimeError("seminars have no Baseline V2 authority")


async def get_seminar_attendee(seminar_id: str, user_id: str) -> Optional[dict]:
    del seminar_id, user_id
    return None


async def get_seminar(seminar_id: str) -> dict | None:
    del seminar_id
    return None


async def list_host_seminars(host_id: str) -> list[dict]:
    del host_id
    return []


async def list_public_seminars(limit: int = 20) -> list[dict]:
    del limit
    return []


async def create_seminar(**kwargs: Any) -> dict:
    del kwargs
    raise _seminars_disabled()


async def update_seminar(**kwargs: Any) -> dict | None:
    del kwargs
    raise _seminars_disabled()


async def set_seminar_status(**kwargs: Any) -> dict | None:
    del kwargs
    raise _seminars_disabled()


async def create_seminar_session(**kwargs: Any) -> dict:
    del kwargs
    raise _seminars_disabled()


async def update_seminar_session(**kwargs: Any) -> dict | None:
    del kwargs
    raise _seminars_disabled()


async def get_seminar_session(session_id: str) -> Optional[dict]:
    del session_id
    return None


async def get_latest_session(seminar_id: str) -> Optional[dict]:
    del seminar_id
    return None


async def get_session_by_room(livekit_room: str) -> Optional[dict]:
    del livekit_room
    return None


async def list_seminar_sessions(seminar_id: str) -> list[dict]:
    del seminar_id
    return []


async def list_seminar_attendees(seminar_id: str) -> list[dict]:
    del seminar_id
    return []


async def list_seminar_recordings(seminar_id: str) -> list[dict]:
    del seminar_id
    return []


async def get_recording_by_asset_url(asset_url: str) -> dict | None:
    del asset_url
    return None


async def register_attendee(**kwargs: Any) -> dict:
    del kwargs
    raise _seminars_disabled()


async def unregister_attendee(*, seminar_id: str, user_id: str) -> bool:
    del seminar_id, user_id
    return False


async def get_user_seminar_role(user_id: str, seminar_id: str) -> Optional[str]:
    del user_id, seminar_id
    return None


async def touch_attendee_presence(**kwargs: Any) -> dict | None:
    del kwargs
    raise _seminars_disabled()


async def upsert_recording(**kwargs: Any) -> dict:
    del kwargs
    raise _seminars_disabled()


async def user_can_access_seminar(user_id: str, seminar_id: str) -> bool:
    del user_id, seminar_id
    return False


async def user_has_seminar_access(user_id: str, seminar: dict) -> bool:
    del user_id, seminar
    return False
