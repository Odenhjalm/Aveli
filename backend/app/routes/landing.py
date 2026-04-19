from fastapi import APIRouter

from .. import models, schemas

router = APIRouter(prefix="/landing", tags=["landing"])


def _course_list_response(rows) -> schemas.CourseListResponse:
    return schemas.CourseListResponse(
        items=[schemas.Course(**row) for row in rows]
    )


@router.get("/intro-courses", response_model=schemas.CourseListResponse)
async def intro_courses():
    rows = await models.list_intro_courses()
    return _course_list_response(rows)


@router.get("/popular-courses", response_model=schemas.CourseListResponse)
async def popular_courses():
    rows = await models.list_popular_courses()
    return _course_list_response(rows)


@router.get(
    "/teachers",
    response_model=schemas.LandingTeacherSectionResponse,
)
async def teachers():
    rows = await models.list_teachers()
    return schemas.LandingTeacherSectionResponse(
        items=[schemas.LandingTeacherCard(**row) for row in rows]
    )


@router.get(
    "/services",
    response_model=schemas.LandingServiceSectionResponse,
)
async def services():
    rows = await models.list_services()
    return schemas.LandingServiceSectionResponse(
        items=[schemas.LandingServiceCard(**row) for row in rows]
    )
