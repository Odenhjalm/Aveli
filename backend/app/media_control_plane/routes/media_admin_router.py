"""Placeholder admin routes for the media control plane."""

from fastapi import APIRouter


router = APIRouter(prefix="/admin/media", tags=["media-admin"])


@router.get("/health")
async def media_control_plane_health() -> dict[str, str]:
    """Return a static health response for the control plane workspace."""

    return {"media_control_plane": "initialized"}
