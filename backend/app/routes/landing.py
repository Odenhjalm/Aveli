from fastapi import APIRouter

from .. import models, schemas

router = APIRouter(prefix="/landing", tags=["landing"])


@router.get(
    "/intro-courses",
    response_model=schemas.LandingCourseSectionResponse,
)
async def intro_courses():
    rows = await models.list_intro_courses()
    return schemas.LandingCourseSectionResponse(
        items=[schemas.LandingCourseCard(**row) for row in rows]
    )


@router.get(
    "/popular-courses",
    response_model=schemas.LandingCourseSectionResponse,
)
async def popular_courses():
    rows = await models.list_popular_courses()
    return schemas.LandingCourseSectionResponse(
        items=[schemas.LandingCourseCard(**row) for row in rows]
    )


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
