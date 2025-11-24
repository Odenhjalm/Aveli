from fastapi import APIRouter, HTTPException, Response, status

from .. import models, schemas
from ..permissions import AdminUser

router = APIRouter(prefix="/admin", tags=["admin"])


async def _ensure_teacher_application_payload() -> list[schemas.TeacherApplication]:
    rows = await models.list_teacher_applications()
    return [schemas.TeacherApplication(**row) for row in rows]


async def _approve_teacher(user_id: str, reviewer_id: str):
    await models.approve_teacher_user(user_id, reviewer_id)


async def _reject_teacher(user_id: str, reviewer_id: str):
    await models.reject_teacher_user(user_id, reviewer_id)


@router.get("/dashboard", response_model=schemas.AdminDashboard)
async def admin_dashboard(current: AdminUser):
    requests = await _ensure_teacher_application_payload()
    certificates = await models.list_recent_certificates()
    return schemas.AdminDashboard(
        is_admin=True,
        requests=requests,
        certificates=certificates,
    )


@router.get("/settings", response_model=schemas.AdminSettingsResponse)
async def admin_settings(current: AdminUser):
    priorities_raw = await models.list_teacher_course_priorities()
    metrics_raw = await models.fetch_admin_metrics()
    priorities = [
        schemas.TeacherPriorityRecord.model_validate(item) for item in priorities_raw
    ]
    metrics = schemas.AdminMetrics.model_validate(metrics_raw)
    return schemas.AdminSettingsResponse(metrics=metrics, priorities=priorities)


@router.get(
    "/teacher-requests",
    response_model=schemas.TeacherApplicationListResponse,
)
async def admin_teacher_requests(current: AdminUser):
    items = await _ensure_teacher_application_payload()
    return schemas.TeacherApplicationListResponse(items=items)


@router.post("/teachers/{user_id}/approve", status_code=status.HTTP_204_NO_CONTENT)
async def admin_approve_teacher(user_id: str, current: AdminUser):
    await _approve_teacher(user_id, current["id"])
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/teacher-requests/{user_id}/approve",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def admin_teacher_request_approve(user_id: str, current: AdminUser):
    await _approve_teacher(user_id, current["id"])
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/teachers/{user_id}/reject", status_code=status.HTTP_204_NO_CONTENT)
async def admin_reject_teacher(user_id: str, current: AdminUser):
    await _reject_teacher(user_id, current["id"])
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/teacher-requests/{user_id}/reject",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def admin_teacher_request_reject(user_id: str, current: AdminUser):
    await _reject_teacher(user_id, current["id"])
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch(
    "/certificates/{certificate_id}",
    response_model=schemas.CertificateRecord,
)
async def admin_update_certificate(
    certificate_id: str,
    payload: schemas.CertificateStatusUpdate,
    current: AdminUser,
):
    row = await models.set_certificate_status(certificate_id, payload.status)
    if not row:
        raise HTTPException(status_code=404, detail="Certificate not found")
    return row


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
