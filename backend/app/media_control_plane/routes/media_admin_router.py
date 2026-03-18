"""Admin routes for the media control plane."""

from datetime import datetime, timezone

from fastapi import APIRouter

from ...permissions import AdminUser


router = APIRouter(prefix="/admin/media", tags=["media-admin"])


@router.get("/health")
async def media_control_plane_health(current: AdminUser) -> dict[str, object]:
    """Return an admin-only status payload for the control plane workspace."""

    return {
        "control_plane": "media",
        "status": "ok",
        "access": "admin_only",
        "workspace": "media_control_plane",
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "viewer_id": str(current["id"]),
        "capabilities": [
            {
                "id": "runtime_media",
                "label": "Runtime media reference layer",
                "status": "ready",
            },
            {
                "id": "upload_routing",
                "label": "Upload routing and processing handoff",
                "status": "ready",
            },
            {
                "id": "diagnostics",
                "label": "Admin diagnostics workspace",
                "status": "ready",
            },
        ],
        "actions": [
            {"id": "admin_dashboard", "label": "Admin dashboard", "route": "/admin"},
            {
                "id": "admin_settings",
                "label": "Admin settings",
                "route": "/admin/settings",
            },
            {"id": "studio", "label": "Teacher studio", "route": "/studio"},
        ],
    }
