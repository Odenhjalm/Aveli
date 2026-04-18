from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status


router = APIRouter(prefix="/api/notifications", tags=["notifications"])


def _has_admin_role(current: dict) -> bool:
    return str(current.get("role") or "").strip().lower() == "admin"


def _raise_v2_feature_disabled() -> None:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Notifications have no Baseline V2 authority",
    )


async def _event_host_access(event_id: str, user_id: str) -> tuple[bool, bool]:
    del event_id, user_id
    return False, False


async def _course_owner(course_id: str) -> str | None:
    del course_id
    return None


@router.get("")
async def list_notifications(request: Request) -> None:
    del request
    _raise_v2_feature_disabled()


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_notification(request: Request) -> None:
    del request
    _raise_v2_feature_disabled()


@router.api_route("/{path:path}", methods=["GET", "POST", "PATCH", "PUT", "DELETE"])
async def disabled_notification_surface(path: str, request: Request) -> None:
    del path, request
    _raise_v2_feature_disabled()
