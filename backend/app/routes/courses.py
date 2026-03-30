from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status

from .. import schemas
from ..auth import CurrentUser, OptionalCurrentUser
from ..services import courses_service

router = APIRouter(prefix="/courses", tags=["courses"])
api_router = APIRouter(prefix="/api/courses", tags=["courses"])


async def _assert_can_access_course(user: OptionalCurrentUser, course_id: str) -> None:
    course = await courses_service.fetch_course_access_subject(course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    if not user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden",
        )
    if bool(user.get("is_admin")):
        return
    if await courses_service.can_user_read_course(str(user["id"]), course):
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Forbidden",
    )


async def _assert_can_access_lesson(user: OptionalCurrentUser, lesson_id: str) -> dict:
    lesson = await courses_service.fetch_lesson(lesson_id)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    if not user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden",
        )
    if bool(user.get("is_admin")):
        return lesson
    if await courses_service.can_user_read_lesson(str(user["id"]), lesson):
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


@router.get("/{course_id}/enrollment")
async def enrollment_status(course_id: UUID, current: CurrentUser):
    normalized_course_id = str(course_id)
    enrollment = await courses_service.get_course_enrollment(
        str(current["id"]),
        normalized_course_id,
    )
    return {
        "enrolled": enrollment is not None,
        "enrollment": enrollment,
    }


@router.get("/by-slug/{slug}")
async def course_detail_by_slug(slug: str, current: OptionalCurrentUser = None):
    row = await courses_service.fetch_course(slug=slug)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    course_id = str(row["id"])
    await _assert_can_access_course(current, course_id)
    lessons = await courses_service.list_course_lessons(course_id)
    return {"course": row, "lessons": lessons}


@router.get("/{course_id}")
async def course_detail(course_id: UUID, current: OptionalCurrentUser = None):
    normalized_course_id = str(course_id)
    await _assert_can_access_course(current, normalized_course_id)
    row = await courses_service.fetch_course(course_id=normalized_course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    lessons = await courses_service.list_course_lessons(normalized_course_id)
    return {"course": row, "lessons": lessons}
