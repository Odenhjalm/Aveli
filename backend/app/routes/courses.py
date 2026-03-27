from fastapi import APIRouter, HTTPException, Query, status

from .. import schemas
from ..auth import CurrentUser, OptionalCurrentUser
from ..permissions import AdminUser
from ..repositories import courses as courses_repo
from ..services import courses_service

router = APIRouter(prefix="/courses", tags=["courses"])
api_router = APIRouter(prefix="/api/courses", tags=["courses"])


async def assert_can_access_course(user: OptionalCurrentUser, course_id: str) -> None:
    course = await courses_service.fetch_course_access_subject(course_id)
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    if not user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden",
        )

    user_id = str(user["id"])
    role_value = str(user.get("role_v2") or "").lower()
    if bool(user.get("is_admin")) or role_value == "admin":
        return

    if await courses_service.can_user_read_course(user_id, course):
        return

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Forbidden",
    )


@router.get("", response_model=schemas.CourseListResponse)
async def list_courses(
    published_only: bool = True,
    free_intro: bool | None = None,
    search: str | None = Query(default=None, min_length=2),
    limit: int | None = Query(default=None, ge=1, le=100),
):
    rows = await courses_service.list_public_courses(
        published_only=True,
        free_intro=free_intro,
        search=search,
        limit=limit,
    )
    items = [schemas.Course(**row) for row in rows]
    return schemas.CourseListResponse(items=items)


router.add_api_route("/", list_courses, methods=["GET"], include_in_schema=False)


@router.get("/{slug}/pricing")
async def course_pricing(slug: str):
    row = await courses_repo.get_course_by_slug(slug)
    if not row:
        raise HTTPException(status_code=404, detail="course not found")
    amount_cents = int(row.get("price_amount_cents") or 0)
    currency = (row.get("currency") or "sek").lower()
    return {"amount_cents": amount_cents, "currency": currency}


@api_router.get("/{slug}/pricing")
async def course_pricing_api(slug: str):
    return await course_pricing(slug)


@router.post("/{slug}/bind-price")
async def bind_course_price(slug: str, payload: dict[str, str], current: AdminUser):
    row = await courses_repo.get_course_by_slug(slug)
    if not row:
        raise HTTPException(status_code=404, detail="course not found")
    price_id = (payload or {}).get("stripe_price_id")
    if not price_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="stripe_price_id required",
        )
    product_id = row.get("stripe_product_id")
    await courses_repo.update_course_stripe_ids(str(row["id"]), product_id, price_id)
    return {"ok": True, "stripe_price_id": price_id}


@router.get("/lessons/{lesson_id}")
async def lesson_detail(lesson_id: str, current: OptionalCurrentUser = None):
    lesson = await courses_service.fetch_lesson(lesson_id)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    course_id_raw = lesson.get("course_id")
    course_id = str(course_id_raw) if course_id_raw else None
    if not course_id:
        raise HTTPException(status_code=404, detail="Course not found")

    await assert_can_access_course(current, course_id)

    lessons = await courses_service.list_course_lessons(course_id)

    media_rows = await courses_service.list_lesson_media(
        lesson_id,
        mode="student_render",
    )
    media: list[dict] = list(media_rows)
    return {
        "lesson": lesson,
        "course_id": course_id,
        "lessons": lessons,
        "media": media,
    }


@router.get("/me", response_model=schemas.CourseListResponse)
async def my_courses(current: CurrentUser):
    rows = await courses_service.list_my_courses(current["id"])
    items = [schemas.Course(**row) for row in rows]
    return schemas.CourseListResponse(items=items)


@router.get("/{course_id}/enrollment")
async def enrollment_status(course_id: str, current: CurrentUser):
    enrolled = await courses_service.is_user_enrolled(current["id"], course_id)
    return {"enrolled": enrolled}


@router.post("/{course_id}/enroll")
async def enroll_course(course_id: str, current: CurrentUser):
    result = await courses_service.enroll_free_intro(current["id"], course_id)
    status_code = result.get("status")

    if status_code == "not_found":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Course not found"
        )
    if status_code == "not_free_intro":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Course is not marked as free intro",
        )
    if status_code in {"subscription_required", "limit_reached"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Monthly intro limit reached"
                if status_code == "limit_reached"
                else "Active subscription required"
            ),
        )

    if not result.get("ok"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Unable to enroll in course"
        )

    return {
        "enrolled": True,
        "status": status_code,
    }


@router.get("/{course_id}/latest-order")
async def latest_order(course_id: str, current: CurrentUser):
    row = await courses_service.latest_order_for_course(current["id"], course_id)
    return {"order": row}


@router.get("/intro-first")
async def intro_first():
    rows = await courses_service.list_public_courses(
        published_only=True,
        free_intro=True,
        limit=1,
    )
    course = rows[0] if rows else None
    return {"course": course}


@router.get("/{course_id}/access")
async def course_access(course_id: str, current: CurrentUser):
    snapshot = await courses_service.course_access_snapshot(
        current["id"], course_id
    )
    return snapshot


@router.get("/{course_id}/quiz")
async def quiz_info(course_id: str, current: CurrentUser):
    info = await courses_service.course_quiz_info(course_id, current["id"])
    return info


@router.get("/quiz/{quiz_id}/questions")
async def quiz_questions(quiz_id: str):
    rows = await courses_service.quiz_questions(quiz_id)
    return {"items": rows}


@router.post("/quiz/{quiz_id}/submit")
async def quiz_submit(
    quiz_id: str, payload: schemas.QuizSubmission, current: CurrentUser
):
    result = await courses_service.submit_quiz(
        quiz_id, current["id"], payload.answers
    )
    return result


@router.get("/by-slug/{slug}")
async def course_detail_by_slug(slug: str, current: OptionalCurrentUser = None):
    row = await courses_service.fetch_course(slug=slug)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    course_id = str(row["id"])
    await assert_can_access_course(current, course_id)
    lessons = await courses_service.list_course_lessons(course_id)
    return {"course": row, "lessons": lessons}


@router.get("/{course_id}")
async def course_detail(course_id: str, current: OptionalCurrentUser = None):
    await assert_can_access_course(current, course_id)
    row = await courses_service.fetch_course(course_id=course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    lessons = await courses_service.list_course_lessons(course_id)
    return {"course": row, "lessons": lessons}
