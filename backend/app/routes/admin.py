from fastapi import APIRouter, HTTPException, Response, status

from .. import models, schemas
from ..permissions import AdminUser

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/dashboard", response_model=schemas.AdminDashboard)
async def admin_dashboard(current: AdminUser):
    del current
    return schemas.AdminDashboard(is_admin=True, requests=[], certificates=[])


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


@router.patch(
    "/teachers/{teacher_id}/priority",
    response_model=schemas.TeacherPriorityRecord,
)
async def admin_set_teacher_priority(
    teacher_id: str,
    payload: schemas.TeacherPriorityUpdate,
    current: AdminUser,
):
    existing = await models.get_teacher_course_priority(teacher_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Teacher not found")
    await models.upsert_teacher_course_priority(
        teacher_id=teacher_id,
        priority=payload.priority,
        notes=payload.notes,
        updated_by=str(current["id"]),
    )
    updated = await models.get_teacher_course_priority(teacher_id)
    if not updated:
        raise HTTPException(status_code=404, detail="Teacher not found")
    return schemas.TeacherPriorityRecord.model_validate(updated)


@router.delete(
    "/teachers/{teacher_id}/priority",
    response_model=schemas.TeacherPriorityRecord,
)
async def admin_clear_teacher_priority(
    teacher_id: str,
    current: AdminUser,
):
    existing = await models.get_teacher_course_priority(teacher_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Teacher not found")
    await models.delete_teacher_course_priority(teacher_id)
    refreshed = await models.get_teacher_course_priority(teacher_id)
    if not refreshed:
        raise HTTPException(status_code=404, detail="Teacher not found")
    return schemas.TeacherPriorityRecord.model_validate(refreshed)
