from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from ..auth import CurrentUser
from ..permissions import TeacherUser
from ..schemas.checkout import CheckoutCreateResponse
from ..schemas.course_bundles import (
    CourseBundleCourseRequest,
    CourseBundleCreateRequest,
    CourseBundleResponse,
    CourseBundleListResponse,
)
from ..services import course_bundles_service

router = APIRouter(tags=["course-bundles"])


@router.get(
    "/api/course-bundles/{bundle_id}",
    response_model=CourseBundleResponse,
)
async def get_bundle(bundle_id: str) -> CourseBundleResponse:
    bundle = await course_bundles_service.get_bundle(bundle_id)
    if not bundle:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Paketet hittades inte")
    return bundle


@router.post(
    "/api/teachers/course-bundles",
    response_model=CourseBundleResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_bundle(
    payload: CourseBundleCreateRequest,
    current: TeacherUser,
) -> CourseBundleResponse:
    try:
        return await course_bundles_service.create_bundle(current, payload)
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.get(
    "/api/teachers/course-bundles",
    response_model=CourseBundleListResponse,
)
async def list_teacher_bundles(current: TeacherUser) -> CourseBundleListResponse:
    try:
        bundles = await course_bundles_service.list_teacher_bundles(current)
        return CourseBundleListResponse(items=bundles)
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/api/teachers/course-bundles/{bundle_id}/courses",
    response_model=CourseBundleResponse,
)
async def add_course_to_bundle(
    bundle_id: str,
    payload: CourseBundleCourseRequest,
    current: TeacherUser,
) -> CourseBundleResponse:
    try:
        return await course_bundles_service.attach_course(
            current,
            bundle_id,
            course_id=payload.course_id,
            position=payload.position,
        )
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/api/course-bundles/{bundle_id}/checkout-session",
    response_model=CheckoutCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_bundle_checkout(
    bundle_id: str,
    current: CurrentUser,
) -> CheckoutCreateResponse:
    try:
        return await course_bundles_service.create_checkout_session(current, bundle_id)
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
