from fastapi import APIRouter, HTTPException, Response, status

from .. import models, schemas
from ..permissions import AdminUser

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/settings", response_model=schemas.AdminSettingsResponse)
async def admin_settings(current: AdminUser):
    priorities_raw = await models.list_teacher_course_priorities()
    metrics_raw = await models.fetch_admin_metrics()
    priorities = [
        schemas.TeacherPriorityRecord.model_validate(item) for item in priorities_raw
    ]
    metrics = schemas.AdminMetrics.model_validate(metrics_raw)
    return schemas.AdminSettingsResponse(metrics=metrics, priorities=priorities)


@router.post(
    "/users/{user_id}/grant-teacher-role",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def admin_grant_teacher_role(user_id: str, current: AdminUser):
    try:
        await models.grant_teacher_role(user_id, str(current["id"]))
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="user_not_found") from exc
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="forbidden",
        ) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/users/{user_id}/revoke-teacher-role",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def admin_revoke_teacher_role(user_id: str, current: AdminUser):
    try:
        await models.revoke_teacher_role(user_id, str(current["id"]))
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="user_not_found") from exc
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="forbidden",
        ) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)
