from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Body, HTTPException, status
from psycopg import Error as PsycopgError

from ..auth import CurrentUser
from ..permissions import TeacherEntryUser
from ..schemas.checkout import CheckoutCreateResponse
from ..schemas.course_bundles import (
    CourseBundleResponse,
    CourseBundleListResponse,
)
from ..services import course_bundles_service

router = APIRouter(tags=["course-bundles"])


def _raise_bundle_database_error(exc: PsycopgError) -> None:
    mapped = course_bundles_service.map_bundle_database_error(exc)
    raise HTTPException(status_code=mapped.status_code, detail=mapped.detail) from exc


@router.get(
    "/api/course-bundles/{bundle_id}",
    response_model=CourseBundleResponse,
)
async def get_bundle(bundle_id: str) -> CourseBundleResponse:
    try:
        bundle = await course_bundles_service.get_bundle(bundle_id)
    except PsycopgError as exc:
        _raise_bundle_database_error(exc)
    if not bundle:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Paketet hittades inte")
    return bundle


@router.post(
    "/api/teachers/course-bundles",
    response_model=CourseBundleResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_bundle(
    current: TeacherEntryUser,
    payload: Any = Body(default=None),
) -> CourseBundleResponse:
    try:
        request = course_bundles_service.parse_create_request(payload)
        return await course_bundles_service.create_bundle(current, request)
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except PsycopgError as exc:
        _raise_bundle_database_error(exc)


@router.patch(
    "/api/teachers/course-bundles/{bundle_id}",
    response_model=CourseBundleResponse,
)
async def update_bundle(
    bundle_id: str,
    current: TeacherEntryUser,
    payload: Any = Body(default=None),
) -> CourseBundleResponse:
    try:
        request = course_bundles_service.parse_update_request(payload)
        return await course_bundles_service.update_bundle(current, bundle_id, request)
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except PsycopgError as exc:
        _raise_bundle_database_error(exc)


@router.get(
    "/api/teachers/course-bundles",
    response_model=CourseBundleListResponse,
)
async def list_teacher_bundles(current: TeacherEntryUser) -> CourseBundleListResponse:
    try:
        bundles = await course_bundles_service.list_teacher_bundles(current)
        return CourseBundleListResponse(items=bundles)
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except PsycopgError as exc:
        _raise_bundle_database_error(exc)


@router.post(
    "/api/teachers/course-bundles/{bundle_id}/courses",
    response_model=CourseBundleResponse,
)
async def add_course_to_bundle(
    bundle_id: str,
    current: TeacherEntryUser,
    payload: Any = Body(default=None),
) -> CourseBundleResponse:
    try:
        course_id, position = course_bundles_service.parse_attach_request(payload)
        return await course_bundles_service.attach_course(
            current,
            bundle_id,
            course_id=course_id,
            position=position,
        )
    except course_bundles_service.CourseBundleConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except course_bundles_service.CourseBundleError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except PsycopgError as exc:
        _raise_bundle_database_error(exc)


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
    except PsycopgError as exc:
        _raise_bundle_database_error(exc)
