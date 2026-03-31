from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status

from .. import schemas
from ..auth import CurrentUser, OptionalCurrentUser
from ..services import courses_service

router = APIRouter(prefix="/courses", tags=["courses"])
api_router = APIRouter(prefix="/api/courses", tags=["courses"])


async def _assert_can_access_lesson(user: OptionalCurrentUser, lesson_id: str) -> dict:
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
    if bool(user.get("is_admin")):
        return lesson
    if access["can_access"]:
        return lesson
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Forbidden",
    )


def _course_detail_response(
    course: dict,
    lessons: list[dict] | tuple[dict, ...],
) -> schemas.CourseDetailResponse:
    return schemas.CourseDetailResponse(
        course=schemas.Course(**course),
        lessons=[schemas.LessonStructureItem(**row) for row in lessons],
    )


def _course_access_response(payload: dict) -> schemas.CourseAccessStateResponse:
    enrollment = payload.get("enrollment")
    return schemas.CourseAccessStateResponse(
        course_id=payload["course_id"],
        course_step=payload["course_step"],
        required_enrollment_source=payload.get("required_enrollment_source"),
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
        lessons=[schemas.LessonStructureItem(**row) for row in lessons],
        media=[schemas.LearnerLessonMediaItem(**row) for row in media_rows],
    )


@router.get("", response_model=schemas.CourseListResponse)
async def list_courses(
    search: str | None = Query(default=None, min_length=2),
    limit: int | None = Query(default=None, ge=1, le=100),
):
    rows = await courses_service.list_public_courses(search=search, limit=limit)
    return schemas.CourseListResponse(items=[schemas.Course(**row) for row in rows])


router.add_api_route("/", list_courses, methods=["GET"], include_in_schema=False)


def _course_pricing_response(payload: dict) -> schemas.CoursePricingResponse:
    amount_cents = payload.get("amount_cents")
    currency = payload.get("currency")
    if amount_cents is None or currency is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Course pricing is not configured",
        )
    return schemas.CoursePricingResponse(
        amount_cents=amount_cents,
        currency=currency,
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
async def lesson_detail(lesson_id: str, current: OptionalCurrentUser = None):
    lesson = await _assert_can_access_lesson(current, lesson_id)
    course_id = str(lesson.get("course_id") or "").strip()
    lessons = await courses_service.list_course_lessons(course_id)
    media_rows = await courses_service.list_lesson_media(lesson_id, mode="student_render")
    return _lesson_content_response(
        lesson=lesson,
        course_id=course_id,
        lessons=list(lessons),
        media_rows=list(media_rows),
    )


@router.get("/me", response_model=schemas.CourseListResponse)
async def my_courses(current: CurrentUser):
    rows = await courses_service.list_my_courses(str(current["id"]))
    return schemas.CourseListResponse(items=[schemas.Course(**row) for row in rows])


async def _read_course_state_or_404(*, user_id: str, course_id: str) -> dict:
    state = await courses_service.read_canonical_course_state(user_id, course_id)
    if state is None:
        raise HTTPException(status_code=404, detail="Course not found")
    return state


@router.get(
    "/{course_id}/enrollment",
    response_model=schemas.CourseAccessStateResponse,
)
async def enrollment_status(course_id: UUID, current: CurrentUser):
    state = await _read_course_state_or_404(
        user_id=str(current["id"]),
        course_id=str(course_id),
    )
    return _course_access_response(state)


@router.get("/{course_id}/access", response_model=schemas.CourseAccessStateResponse)
async def course_access(course_id: UUID, current: CurrentUser):
    state = await _read_course_state_or_404(
        user_id=str(current["id"]),
        course_id=str(course_id),
    )
    return _course_access_response(state)


@router.post("/{course_id}/enroll", response_model=schemas.CourseAccessStateResponse)
async def enroll_course(course_id: UUID, current: CurrentUser):
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
    row = await courses_service.fetch_course(slug=slug)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    course_id = str(row["id"])
    lessons = await courses_service.list_course_lessons(course_id)
    return _course_detail_response(row, list(lessons))


@router.get("/{course_id}/public", response_model=schemas.CoursePublicContent)
async def course_public_content(course_id: UUID):
    course = await courses_service.fetch_course(course_id=str(course_id))
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    row = await courses_service.fetch_course_public_content(str(course_id))
    if not row:
        raise HTTPException(status_code=404, detail="Public content not found")
    return schemas.CoursePublicContent(**row)


@router.get("/{course_id}", response_model=schemas.CourseDetailResponse)
async def course_detail(course_id: UUID, current: OptionalCurrentUser = None):
    del current
    normalized_course_id = str(course_id)
    row = await courses_service.fetch_course(course_id=normalized_course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    lessons = await courses_service.list_course_lessons(normalized_course_id)
    return _course_detail_response(row, list(lessons))
