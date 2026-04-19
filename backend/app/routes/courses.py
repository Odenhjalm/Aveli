from typing import Any, Mapping
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status

from .. import schemas
from ..auth import AppEntryUser, OptionalCurrentUser
from ..services import courses_read_service, courses_service

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


def _canonical_course_payload(course: Mapping[str, Any]) -> dict[str, Any]:
    courses_service.reject_legacy_course_cover_output_fields(course)
    normalized = dict(course)
    courses_service.attach_course_access_model(normalized)
    courses_service.attach_course_teacher_read_contract(normalized)
    return {field: normalized.get(field) for field in _CANONICAL_COURSE_FIELDS}


def _course_response(course: Mapping[str, Any]) -> schemas.Course:
    return schemas.Course(**_canonical_course_payload(course))


def _course_list_response(
    rows: list[Mapping[str, Any]] | tuple[Mapping[str, Any], ...],
) -> schemas.CourseListResponse:
    return schemas.CourseListResponse(items=[_course_response(row) for row in rows])


def _lesson_structure_payload(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": row.get("id"),
        "lesson_title": row.get("lesson_title"),
        "position": row.get("position"),
    }


async def _assert_can_access_lesson(user: dict | None, lesson_id: str) -> dict:
    access = await courses_service.read_canonical_lesson_access(
        str((user or {}).get("id") or ""),
        lesson_id,
    )
    lesson = access["lesson"]
    if lesson is None:
        raise HTTPException(status_code=404, detail="Lesson not found")
    if not user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden",
        )
    if access["can_access"]:
        return lesson
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Forbidden",
    )


def _course_access_response(payload: dict) -> schemas.CourseAccessStateResponse:
    enrollment = payload.get("enrollment")
    return schemas.CourseAccessStateResponse(
        course_id=payload["course_id"],
        group_position=payload["group_position"],
        required_enrollment_source=payload.get("required_enrollment_source"),
        enrollable=payload["enrollable"],
        purchasable=payload["purchasable"],
        enrollment=(
            schemas.CourseEnrollmentRecord(**enrollment)
            if enrollment is not None
            else None
        ),
    )


def _lesson_content_response(
    *,
    lesson: dict,
    course_id: str,
    lessons: list[dict] | tuple[dict, ...],
    media_rows: list[dict] | tuple[dict, ...],
) -> schemas.LessonContentResponse:
    return schemas.LessonContentResponse(
        lesson=schemas.LessonContentItem(**lesson),
        course_id=course_id,
        lessons=[
            schemas.LessonStructureItem(**_lesson_structure_payload(row))
            for row in lessons
        ],
        media=[schemas.LearnerLessonMediaItem(**row) for row in media_rows],
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
            detail="Course pricing is not configured",
        )
    return schemas.CoursePricingResponse(
        amount_cents=amount_cents,
        currency=_CANONICAL_COURSE_CURRENCY,
    )


@router.get("/{slug}/pricing", response_model=schemas.CoursePricingResponse)
async def course_pricing(slug: str):
    row = await courses_service.fetch_course_pricing(slug)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    return _course_pricing_response(row)


@api_router.get("/{slug}/pricing", response_model=schemas.CoursePricingResponse)
async def course_pricing_api(slug: str):
    return await course_pricing(slug)


@router.get("/lessons/{lesson_id}", response_model=schemas.LessonContentResponse)
async def lesson_detail(lesson_id: str, current: AppEntryUser):
    lesson = await _assert_can_access_lesson(current, lesson_id)
    course_id = str(lesson.get("course_id") or "").strip()
    if course_id == "":
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Lesson course_id is required",
        )
    protected_content = await courses_service.read_protected_lesson_content_surface(
        lesson_id,
        user_id=str((current or {}).get("id") or ""),
    )
    if protected_content is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical lesson content is unavailable",
        )
    lessons = await courses_service.list_course_lesson_structure(course_id)
    return _lesson_content_response(
        lesson=protected_content["lesson"],
        course_id=course_id,
        lessons=list(lessons),
        media_rows=list(protected_content["media"]),
    )


@router.get("/me", response_model=schemas.CourseListResponse)
async def my_courses(current: AppEntryUser):
    rows = await courses_service.list_my_courses(str(current["id"]))
    normalized_rows = list(rows)
    await courses_service.attach_course_cover_read_contract(normalized_rows)
    return _course_list_response(normalized_rows)


async def _read_course_state_or_404(*, user_id: str, course_id: str) -> dict:
    state = await courses_service.read_canonical_course_state(user_id, course_id)
    if state is None:
        raise HTTPException(status_code=404, detail="Course not found")
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
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Course not found") from exc
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(exc),
        ) from exc


@router.get("/by-slug/{slug}", response_model=schemas.CourseDetailResponse)
async def course_detail_by_slug(slug: str, current: OptionalCurrentUser = None):
    del current
    detail = await courses_read_service.read_course_detail(slug=slug)
    if not detail:
        raise HTTPException(status_code=404, detail="Course not found")
    return detail


@router.get("/{course_id}/public", response_model=schemas.CoursePublicContent)
async def course_public_content(course_id: UUID):
    row = await courses_read_service.read_public_course_content(str(course_id))
    if not row:
        raise HTTPException(status_code=404, detail="Public content not found")
    return schemas.CoursePublicContent(**row)


@router.get("/{course_id}", response_model=schemas.CourseDetailResponse)
async def course_detail(course_id: UUID, current: OptionalCurrentUser = None):
    del current
    detail = await courses_read_service.read_course_detail(course_id=str(course_id))
    if not detail:
        raise HTTPException(status_code=404, detail="Course not found")
    return detail
