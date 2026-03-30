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


@router.get("", response_model=schemas.CourseListResponse)
async def list_courses(
    search: str | None = Query(default=None, min_length=2),
    limit: int | None = Query(default=None, ge=1, le=100),
):
    rows = await courses_service.list_public_courses(search=search, limit=limit)
    return schemas.CourseListResponse(items=[schemas.Course(**row) for row in rows])


router.add_api_route("/", list_courses, methods=["GET"], include_in_schema=False)


@router.get("/{slug}/pricing")
async def course_pricing(slug: str):
    row = await courses_service.fetch_course(slug=slug)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    return {
        "amount_cents": int(row.get("price_amount_cents") or 0),
        "currency": "sek",
    }


@api_router.get("/{slug}/pricing")
async def course_pricing_api(slug: str):
    return await course_pricing(slug)


@router.get("/lessons/{lesson_id}")
async def lesson_detail(lesson_id: str, current: OptionalCurrentUser = None):
    lesson = await _assert_can_access_lesson(current, lesson_id)
    course_id = str(lesson.get("course_id") or "").strip()
    lessons = await courses_service.list_course_lessons(course_id)
    media_rows = await courses_service.list_lesson_media(lesson_id, mode="student_render")
    return {
        "lesson": lesson,
        "course_id": course_id,
        "lessons": lessons,
        "media": list(media_rows),
    }


@router.get("/me", response_model=schemas.CourseListResponse)
async def my_courses(current: CurrentUser):
    rows = await courses_service.list_my_courses(str(current["id"]))
    return schemas.CourseListResponse(items=[schemas.Course(**row) for row in rows])


async def _read_course_state_or_404(*, user_id: str, course_id: str) -> dict:
    state = await courses_service.read_canonical_course_state(user_id, course_id)
    if state is None:
        raise HTTPException(status_code=404, detail="Course not found")
    return state


@router.get("/{course_id}/enrollment")
async def enrollment_status(course_id: UUID, current: CurrentUser):
    return await _read_course_state_or_404(
        user_id=str(current["id"]),
        course_id=str(course_id),
    )


@router.get("/{course_id}/access")
async def course_access(course_id: UUID, current: CurrentUser):
    return await _read_course_state_or_404(
        user_id=str(current["id"]),
        course_id=str(course_id),
    )


@router.post("/{course_id}/enroll")
async def enroll_course(course_id: UUID, current: CurrentUser):
    normalized_course_id = str(course_id)
    try:
        return await courses_service.create_intro_course_enrollment(
            user_id=str(current["id"]),
            course_id=normalized_course_id,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Course not found") from exc
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(exc),
        ) from exc


@router.get("/by-slug/{slug}")
async def course_detail_by_slug(slug: str, current: OptionalCurrentUser = None):
    del current
    row = await courses_service.fetch_course(slug=slug)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    course_id = str(row["id"])
    lessons = await courses_service.list_course_lessons(course_id)
    return {"course": row, "lessons": lessons}


@router.get("/{course_id}")
async def course_detail(course_id: UUID, current: OptionalCurrentUser = None):
    del current
    normalized_course_id = str(course_id)
    row = await courses_service.fetch_course(course_id=normalized_course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    lessons = await courses_service.list_course_lessons(normalized_course_id)
    return {"course": row, "lessons": lessons}
