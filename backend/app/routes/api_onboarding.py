from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from ..auth import CurrentUser
from ..schemas.onboarding import IntroCourseSelectionRequest, OnboardingPayload
from ..services import onboarding_service
from ..utils import media_signer

router = APIRouter(prefix="/api/onboarding", tags=["onboarding"])


@router.get("/me", response_model=OnboardingPayload)
async def onboarding_me(current: CurrentUser) -> OnboardingPayload:
    try:
        return await onboarding_service.get_onboarding_payload(str(current["id"]))
    except onboarding_service.OnboardingError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.get("/intro-courses")
async def onboarding_intro_courses(current: CurrentUser):
    try:
        rows = await onboarding_service.list_intro_courses()
    except onboarding_service.OnboardingError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    for row in rows:
        media_signer.attach_cover_links(row)
    return {"items": rows}


@router.post(
    "/select-intro-course",
    response_model=OnboardingPayload,
    status_code=status.HTTP_200_OK,
)
async def select_intro_course(
    payload: IntroCourseSelectionRequest,
    current: CurrentUser,
) -> OnboardingPayload:
    try:
        return await onboarding_service.select_intro_course(
            str(current["id"]),
            course_id=payload.course_id,
        )
    except onboarding_service.OnboardingError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post("/complete", response_model=OnboardingPayload)
async def complete_onboarding(current: CurrentUser) -> OnboardingPayload:
    try:
        return await onboarding_service.complete_onboarding(str(current["id"]))
    except onboarding_service.OnboardingError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
