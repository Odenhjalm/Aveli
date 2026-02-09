from typing import Any

from fastapi import APIRouter, HTTPException, Query, status

from .. import schemas
from ..auth import CurrentUser, OptionalCurrentUser
from ..permissions import AdminUser
from ..repositories import courses as courses_repo
from ..services import courses_service
from ..utils import media_signer

router = APIRouter(prefix="/courses", tags=["courses"])
config_router = APIRouter(prefix="/config", tags=["config"])
api_router = APIRouter(prefix="/api/courses", tags=["courses"])


def _attach_cover_links(course: dict) -> None:
    media_signer.attach_cover_links(course)


def _attach_media_links(item: dict) -> None:
    media_signer.attach_media_links(item)


def _virtual_module(course_id: str) -> dict[str, Any]:
    """Compatibility shim: represent a flat course as a single pseudo-module.

    The database no longer stores modules; lessons belong directly to a course.
    Some clients still expect modules + lessons-by-module payloads, so we expose a
    stable virtual module whose id equals the course id.
    """

    return {
        "id": course_id,
        "course_id": course_id,
        "title": "Lektioner",
        "position": 0,
    }


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
    for row in rows:
        _attach_cover_links(row)
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


@router.get("/{course_id}/modules")
async def modules_for_course(course_id: str):
    course = await courses_service.fetch_course(course_id=course_id)
    if not course or not course.get("is_published"):
        return {"items": []}
    return {"items": [_virtual_module(course_id)]}


@router.get("/modules/{module_id}/lessons")
async def lessons_for_module(module_id: str):
    course = await courses_service.fetch_course(course_id=module_id)
    if not course or not course.get("is_published"):
        return {"items": []}
    lessons = await courses_service.list_course_lessons(module_id)
    return {"items": lessons}


@router.get("/lessons/{lesson_id}")
async def lesson_detail(lesson_id: str, current: OptionalCurrentUser = None):
    lesson = await courses_service.fetch_lesson(lesson_id)
    if not lesson:
        raise HTTPException(status_code=404, detail="Lesson not found")
    course_id_raw = lesson.get("course_id")
    course_id = str(course_id_raw) if course_id_raw else None
    if not course_id:
        raise HTTPException(status_code=404, detail="Course not found")

    course = await courses_service.fetch_course(course_id=course_id)
    if not course or not course.get("is_published"):
        raise HTTPException(status_code=404, detail="Course not found")

    module = _virtual_module(course_id)
    modules = [module]
    course_lessons = await courses_service.list_course_lessons(course_id)
    module_lessons = course_lessons

    media: list[dict] = []
    user_id = str(current["id"]) if current else None

    can_access_media = False
    if user_id and await courses_service.is_course_owner(user_id, course_id):
        can_access_media = True
    elif lesson.get("is_intro") or course.get("is_free_intro"):
        can_access_media = True
    elif user_id and await courses_service.is_user_enrolled(user_id, course_id):
        can_access_media = True

    if can_access_media:
        media_rows = await courses_service.list_lesson_media(
            lesson_id,
            mode="student_render",
        )
        media.extend(media_rows)
    return {
        "lesson": lesson,
        "module": module,
        "modules": modules,
        "module_lessons": module_lessons,
        "course_lessons": course_lessons,
        "media": media,
    }


@router.get("/me", response_model=schemas.CourseListResponse)
async def my_courses(current: CurrentUser):
    rows = await courses_service.list_my_courses(current["id"])
    for row in rows:
        _attach_cover_links(row)
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
    if status_code == "limit_reached":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "message": "Free intro limit reached",
                "code": "limit_reached",
                "consumed": result.get("consumed"),
                "limit": result.get("limit"),
            },
        )

    if not result.get("ok"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Unable to enroll in course"
        )

    payload = {
        "enrolled": True,
        "status": status_code,
    }
    if "consumed" in result:
        payload["consumed"] = result["consumed"]
    if "limit" in result:
        payload["limit"] = result["limit"]
    return payload


@router.get("/{course_id}/latest-order")
async def latest_order(course_id: str, current: CurrentUser):
    row = await courses_service.latest_order_for_course(current["id"], course_id)
    return {"order": row}


@router.get("/free-consumed")
async def free_consumed(current: CurrentUser):
    count = await courses_service.free_consumed_count(current["id"])
    limit = await courses_service.get_free_course_limit()
    return {"consumed": count, "limit": limit}


@router.get("/config/free-limit")
async def free_limit():
    limit = await courses_service.get_free_course_limit()
    return {"limit": limit}


router.add_api_route(
    "/config/free-course-limit",
    free_limit,
    methods=["GET"],
    include_in_schema=False,
)


@config_router.get("/free-course-limit")
async def global_free_course_limit():
    return await free_limit()


@router.get("/intro-first")
async def intro_first():
    rows = await courses_service.list_public_courses(
        published_only=True,
        free_intro=True,
        limit=1,
    )
    course = rows[0] if rows else None
    if course:
        _attach_cover_links(course)
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
async def course_detail_by_slug(slug: str):
    row = await courses_service.fetch_course(slug=slug)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    if not row.get("is_published"):
        raise HTTPException(status_code=404, detail="Course not found")
    _attach_cover_links(row)
    course_id = str(row["id"])
    module = _virtual_module(course_id)
    modules = [module]
    lessons_map: dict[str, list] = {course_id: await courses_service.list_course_lessons(course_id)}
    response = {
        "course": row,
        "modules": modules,
        "lessons": lessons_map,
    }
    return response


@router.get("/{course_id}")
async def course_detail(course_id: str):
    row = await courses_service.fetch_course(course_id=course_id)
    if not row:
        raise HTTPException(status_code=404, detail="Course not found")
    if not row.get("is_published"):
        raise HTTPException(status_code=404, detail="Course not found")
    module = _virtual_module(course_id)
    modules = [module]
    lessons_map: dict[str, list] = {course_id: await courses_service.list_course_lessons(course_id)}
    return {
        "course": row,
        "modules": modules,
        "lessons": lessons_map,
    }
