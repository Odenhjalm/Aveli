from typing import Any, Mapping
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse

from .. import schemas
from ..auth import AppEntryUser, OptionalCurrentUser
from ..services import (
    courses_read_service,
    courses_service,
    intro_course_progression_service,
    lesson_completion_service,
    text_catalog_service,
)
from ..services.lesson_completion_service import LessonCompletionServiceInvariantError

router = APIRouter(prefix="/courses", tags=["courses"])
api_router = APIRouter(prefix="/api/courses", tags=["courses"])

_CANONICAL_COURSE_FIELDS = (
    "id",
    "slug",
    "title",
    "teacher",
    "course_group_id",
    "group_position",
    "cover_media_id",
    "cover",
    "price_amount_cents",
    "drip_enabled",
    "drip_interval_days",
    "required_enrollment_source",
    "enrollable",
    "purchasable",
)
_CANONICAL_COURSE_LIST_FIELDS = (
    *_CANONICAL_COURSE_FIELDS,
    "description",
)

_COURSE_NOT_FOUND_DETAIL = "Kursen kunde inte hittas."
_COURSE_PUBLIC_CONTENT_NOT_FOUND_DETAIL = "Kursinnehållet kunde inte hittas."
_COURSE_PRICING_UNAVAILABLE_DETAIL = "Priset är inte tillgängligt just nu."
_COURSE_PURCHASE_REQUIRED_DETAIL = "Kursen kräver köp innan du kan fortsätta."
_LESSON_NOT_FOUND_DETAIL = "Lektionen kunde inte hittas."
_LESSON_ACCESS_DENIED_DETAIL = "Du har inte åtkomst till den här lektionen."
_LESSON_CONTENT_UNAVAILABLE_DETAIL = "Lektionen kunde inte laddas just nu."


def _canonical_course_payload(course: Mapping[str, Any]) -> dict[str, Any]:
    courses_service.reject_legacy_course_cover_output_fields(course)
    courses_service.reject_legacy_course_progression_output_fields(course)
    normalized = dict(course)
    courses_service.attach_course_access_model(normalized)
    courses_service.attach_course_teacher_read_contract(normalized)
    return {field: normalized[field] for field in _CANONICAL_COURSE_FIELDS}


def _course_response(course: Mapping[str, Any]) -> schemas.Course:
    return schemas.Course(**_canonical_course_payload(course))


def _course_list_item_response(course: Mapping[str, Any]) -> schemas.CourseListItem:
    normalized = dict(course)
    courses_service.reject_legacy_course_cover_output_fields(normalized)
    courses_service.reject_legacy_course_progression_output_fields(normalized)
    courses_service.attach_course_access_model(normalized)
    courses_service.attach_course_teacher_read_contract(normalized)
    return schemas.CourseListItem(
        **{field: normalized[field] for field in _CANONICAL_COURSE_LIST_FIELDS}
    )


def _course_list_response(
    rows: list[Mapping[str, Any]] | tuple[Mapping[str, Any], ...],
) -> schemas.CourseListResponse:
    return schemas.CourseListResponse(
        items=[_course_list_item_response(row) for row in rows]
    )


def _lesson_content_unavailable() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=_LESSON_CONTENT_UNAVAILABLE_DETAIL,
    )


def _course_access_response(payload: dict) -> schemas.CourseAccessStateResponse:
    enrollment = payload.get("enrollment")
    return schemas.CourseAccessStateResponse(
        course_id=payload["course_id"],
        group_position=payload["group_position"],
        required_enrollment_source=payload.get("required_enrollment_source"),
        is_intro_course=payload["is_intro_course"],
        selection_locked=payload["selection_locked"],
        enrollable=payload["enrollable"],
        purchasable=payload["purchasable"],
        can_access=payload["can_access"],
        next_unlock_at=payload.get("next_unlock_at"),
        enrollment=(
            schemas.CourseEnrollmentRecord(**enrollment)
            if enrollment is not None
            else None
        ),
    )


def _cta_text_response(response: Any) -> JSONResponse:
    return JSONResponse(
        content=jsonable_encoder(
            text_catalog_service.attach_text_bundles(
                response,
                [text_catalog_service.COURSE_CTA_BUNDLE_ID],
                text_catalog_service.DEFAULT_LOCALE,
            )
        )
    )


@router.get("", response_model=schemas.CourseListResponse)
async def list_courses(
    search: str | None = Query(default=None, min_length=2),
    limit: int | None = Query(default=None, ge=1, le=100),
):
    rows = await courses_service.list_public_courses(search=search, limit=limit)
    normalized_rows = list(rows)
    await courses_service.attach_course_cover_read_contract(normalized_rows)
    return _course_list_response(normalized_rows)


router.add_api_route("/", list_courses, methods=["GET"], include_in_schema=False)

_CANONICAL_COURSE_CURRENCY = "sek"


def _course_pricing_response(payload: dict) -> schemas.CoursePricingResponse:
    amount_cents = payload.get("amount_cents")
    if amount_cents is None or int(amount_cents) <= 0:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_COURSE_PRICING_UNAVAILABLE_DETAIL,
        )
    return schemas.CoursePricingResponse(
        amount_cents=amount_cents,
        currency=_CANONICAL_COURSE_CURRENCY,
    )


@router.get("/{slug}/pricing", response_model=schemas.CoursePricingResponse)
async def course_pricing(slug: str):
    row = await courses_service.fetch_course_pricing(slug)
    if not row:
        raise HTTPException(status_code=404, detail=_COURSE_NOT_FOUND_DETAIL)
    return _course_pricing_response(row)


@api_router.get("/{slug}/pricing", response_model=schemas.CoursePricingResponse)
async def course_pricing_api(slug: str):
    return await course_pricing(slug)


@router.get("/lessons/{lesson_id}")
async def lesson_detail(
    lesson_id: str,
    current: AppEntryUser,
    preview: bool = False,
):
    user_id = str((current or {}).get("id") or "")
    try:
        response = await courses_service.read_lesson_view_surface(
            lesson_id,
            user_id=user_id,
            preview=preview,
            teacher_id=user_id if preview else None,
        )
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=_LESSON_ACCESS_DENIED_DETAIL,
        ) from exc
    except HTTPException as exc:
        if exc.status_code == status.HTTP_503_SERVICE_UNAVAILABLE:
            raise _lesson_content_unavailable() from exc
        raise

    if response is None:
        raise HTTPException(status_code=404, detail=_LESSON_NOT_FOUND_DETAIL)
    return _cta_text_response(response)


@router.post(
    "/lessons/{lesson_id}/complete",
    response_model=schemas.LessonCompletionCommandResponse,
)
async def complete_lesson_route(
    lesson_id: str,
    current: AppEntryUser,
) -> schemas.LessonCompletionCommandResponse:
    try:
        result = await lesson_completion_service.complete_lesson(
            user_id=str(current["id"]),
            lesson_id=lesson_id,
        )
    except LessonCompletionServiceInvariantError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal Server Error",
        ) from exc

    if result["status"] == "completed":
        return schemas.LessonCompletionCommandResponse(**result)
    if result["status"] == "already_completed":
        return schemas.LessonCompletionCommandResponse(**result)
    if result["status"] == "lesson_not_found":
        raise HTTPException(status_code=404, detail=_LESSON_NOT_FOUND_DETAIL)
    if result["status"] == "access_denied":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=_LESSON_ACCESS_DENIED_DETAIL,
        )


@router.get("/me", response_model=schemas.CourseListResponse)
async def my_courses(current: AppEntryUser):
    rows = await courses_service.list_my_courses(str(current["id"]))
    normalized_rows = list(rows)
    await courses_service.attach_course_cover_read_contract(normalized_rows)
    return _course_list_response(normalized_rows)


@router.get(
    "/intro-selection",
    response_model=schemas.IntroSelectionStateResponse,
)
async def intro_selection_state(current: AppEntryUser):
    state = await intro_course_progression_service.read_intro_selection_state(
        user_id=str(current["id"]),
    )
    return schemas.IntroSelectionStateResponse(
        selection_locked=state["selection_locked"],
        selection_lock_reason=state["selection_lock_reason"],
        eligible_courses=[
            _course_list_item_response(row) for row in state["eligible_courses"]
        ],
    )


async def _read_course_state_or_404(*, user_id: str, course_id: str) -> dict:
    state = await courses_service.read_canonical_course_state(user_id, course_id)
    if state is None:
        raise HTTPException(status_code=404, detail=_COURSE_NOT_FOUND_DETAIL)
    return state


@router.get(
    "/{course_id}/enrollment",
    response_model=schemas.CourseAccessStateResponse,
)
async def enrollment_status(course_id: UUID, current: AppEntryUser):
    state = await _read_course_state_or_404(
        user_id=str(current["id"]),
        course_id=str(course_id),
    )
    return _course_access_response(state)


@router.get("/{course_id}/access", response_model=schemas.CourseAccessStateResponse)
async def course_access(course_id: UUID, current: AppEntryUser):
    state = await _read_course_state_or_404(
        user_id=str(current["id"]),
        course_id=str(course_id),
    )
    return _course_access_response(state)


@router.post("/{course_id}/enroll", response_model=schemas.CourseAccessStateResponse)
async def enroll_course(course_id: UUID, current: AppEntryUser):
    normalized_course_id = str(course_id)
    try:
        state = await courses_service.create_intro_course_enrollment(
            user_id=str(current["id"]),
            course_id=normalized_course_id,
        )
        return _course_access_response(state)
    except courses_service.IntroCourseSelectionLockedByIncompleteDripError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"reason": "incomplete_drip"},
        ) from exc
    except (
        courses_service.IntroCourseSelectionLockedByIncompleteLessonCompletionError
    ) as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"reason": "incomplete_lesson_completion"},
        ) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=_COURSE_NOT_FOUND_DETAIL) from exc
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=_COURSE_PURCHASE_REQUIRED_DETAIL,
        ) from exc


@router.get("/by-slug/{slug}", response_model=schemas.CourseDetailResponse)
async def course_detail_by_slug(slug: str, current: OptionalCurrentUser = None):
    del current
    detail = await courses_read_service.read_course_detail(slug=slug)
    if detail is None:
        raise HTTPException(status_code=404, detail=_COURSE_NOT_FOUND_DETAIL)
    return detail


@router.get(
    "/{course_id_or_slug}/entry-view",
)
async def course_entry_view(
    course_id_or_slug: str,
    current: OptionalCurrentUser = None,
):
    response = await courses_service.read_course_entry_view_surface(
        course_id_or_slug,
        current,
    )
    if response is None:
        raise HTTPException(status_code=404, detail=_COURSE_NOT_FOUND_DETAIL)
    return _cta_text_response(response)


@router.get("/{course_id}/public", response_model=schemas.CoursePublicContent)
async def course_public_content(course_id: UUID):
    row = await courses_read_service.read_public_course_content(str(course_id))
    if row is None:
        raise HTTPException(
            status_code=404,
            detail=_COURSE_PUBLIC_CONTENT_NOT_FOUND_DETAIL,
        )
    return schemas.CoursePublicContent(**row)


@router.get("/{course_id}", response_model=schemas.CourseDetailResponse)
async def course_detail(course_id: UUID, current: OptionalCurrentUser = None):
    del current
    detail = await courses_read_service.read_course_detail(course_id=str(course_id))
    if detail is None:
        raise HTTPException(status_code=404, detail=_COURSE_NOT_FOUND_DETAIL)
    return detail
