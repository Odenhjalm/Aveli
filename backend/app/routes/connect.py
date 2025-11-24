from __future__ import annotations

from fastapi import APIRouter, status

from .. import schemas
from ..permissions import TeacherUser
from ..services import connect_service

router = APIRouter(prefix="/connect", tags=["stripe-connect"])


@router.post(
    "/onboarding",
    response_model=schemas.ConnectOnboardingResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_onboarding_link(
    payload: schemas.ConnectOnboardingRequest,
    current: TeacherUser,
):
    result = await connect_service.create_onboarding_link(
        teacher_id=current["id"],
        refresh_url=payload.refresh_url,
        return_url=payload.return_url,
    )
    return schemas.ConnectOnboardingResponse(**result)


@router.get(
    "/status",
    response_model=schemas.ConnectStatusResponse,
)
async def get_connect_status(current: TeacherUser):
    result = await connect_service.get_connect_status(current["id"])
    return schemas.ConnectStatusResponse(**result)
