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


@router.get(
    "/preferences",
    response_model=notification_schemas.NotificationPreferenceListResponse,
)
async def list_preferences(current: CurrentUser):
    items = await notification_service.list_notification_preferences(
        user_id=str(current["id"]),
    )
    return {"items": items}


@router.patch(
    "/preferences/{notification_type}",
    response_model=notification_schemas.NotificationPreferenceRecord,
)
async def update_preference(
    notification_type: str,
    payload: notification_schemas.NotificationPreferenceUpdateRequest,
    current: CurrentUser,
):
    try:
        result = await notification_service.set_notification_preference(
            user_id=str(current["id"]),
            type=notification_type,
            push_enabled=payload.push_enabled,
            in_app_enabled=payload.in_app_enabled,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    return result.preference


@router.patch(
    "/{notification_id}/read",
    response_model=notification_schemas.NotificationHeaderItem,
)
async def mark_read(notification_id: str, current: CurrentUser):
    notification = await notification_service.mark_notification_read_for_header(
        user_id=str(current["id"]),
        notification_id=notification_id,
    )
    if notification is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="notification_not_found",
        )
    return notification


@router.get("", response_model=notification_schemas.NotificationListResponse)
async def list_notifications(
    current: CurrentUser,
    limit: int = Query(default=50, ge=1, le=100),
):
    read_model = await notification_service.list_notification_header_read_model(
        user_id=str(current["id"]),
        limit=limit,
    )
    return {
        "show_notifications_bar": read_model.show_notifications_bar,
        "notifications": read_model.notifications,
    }
