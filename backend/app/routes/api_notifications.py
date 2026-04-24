from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Response, status

from ..auth import CurrentUser
from ..schemas import notifications as notification_schemas
from ..services import notification_service


router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.post(
    "/devices",
    response_model=notification_schemas.DeviceRecord,
    status_code=status.HTTP_201_CREATED,
)
async def register_device(
    payload: notification_schemas.DeviceRegisterRequest,
    current: CurrentUser,
):
    result = await notification_service.register_device(
        user_id=str(current["id"]),
        push_token=payload.push_token,
        platform=payload.platform,
    )
    return result.device


@router.delete(
    "/devices/{device_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_device(device_id: str, current: CurrentUser):
    deactivated = await notification_service.deactivate_device(
        user_id=str(current["id"]),
        device_id=device_id,
    )
    if not deactivated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="device_not_found",
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("", response_model=notification_schemas.NotificationListResponse)
async def list_notifications(
    current: CurrentUser,
    limit: int = Query(default=50, ge=1, le=100),
):
    items = await notification_service.list_notifications_for_user(
        user_id=str(current["id"]),
        limit=limit,
    )
    return {"items": items}
