from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status


router = APIRouter(prefix="/api/events", tags=["events"])


def _has_admin_role(current: dict) -> bool:
    return str(current.get("role") or "").strip().lower() == "admin"


def _raise_v2_feature_disabled() -> None:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Events have no Baseline V2 authority",
    )


async def _get_event_row(event_id: str) -> dict | None:
    del event_id
    return None


async def _user_is_event_participant(event_id: str, user_id: str) -> bool:
    del event_id, user_id
    return False


async def _user_is_active_event_host(event_id: str, user_id: str) -> bool:
    del event_id, user_id
    return False


@router.get("")
async def list_events(request: Request) -> None:
    del request
    _raise_v2_feature_disabled()


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_event(request: Request) -> None:
    del request
    _raise_v2_feature_disabled()


@router.get("/{event_id}")
async def get_event(event_id: UUID, current: dict) -> None:
    del event_id, current
    _raise_v2_feature_disabled()


@router.patch("/{event_id}")
async def update_event(event_id: UUID, request: Request, current: dict) -> None:
    del event_id, request, current
    _raise_v2_feature_disabled()


@router.post("/{event_id}/participants", status_code=status.HTTP_201_CREATED)
async def register_participant(event_id: UUID, request: Request, current: dict) -> None:
    del event_id, request, current
    _raise_v2_feature_disabled()


@router.get("/{event_id}/notifications")
async def list_event_notifications(event_id: UUID, current: dict) -> None:
    del event_id, current
    _raise_v2_feature_disabled()


@router.api_route("/{path:path}", methods=["GET", "POST", "PATCH", "PUT", "DELETE"])
async def disabled_event_surface(path: str, request: Request) -> None:
    del path, request
    _raise_v2_feature_disabled()
