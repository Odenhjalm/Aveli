from fastapi import APIRouter

from .. import models, schemas
from ..services import courses_service
from ..utils.profile_media import profile_projection_with_avatar

router = APIRouter(prefix="/landing", tags=["landing"])

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
    "short_description",
)


def _course_list_response(rows) -> schemas.CourseListResponse:
    normalized_rows = [dict(row) for row in rows]
    courses_service.attach_course_access_model(normalized_rows)
    courses_service.attach_course_teacher_read_contract(normalized_rows)
    return schemas.CourseListResponse(
        items=[
            schemas.CourseListItem(
                **{field: row.get(field) for field in _CANONICAL_COURSE_FIELDS}
            )
            for row in normalized_rows
        ]
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
    rows = await models.list_teacher_profiles()
    items: list[schemas.LandingTeacherCard] = []
    for row in rows:
        profile = await profile_projection_with_avatar(dict(row))
        items.append(
            schemas.LandingTeacherCard(
                id=str(profile["user_id"]),
                display_name=profile["display_name"],
                avatar_url=profile.get("photo_url"),
                bio=profile.get("bio"),
            )
        )
    return schemas.LandingTeacherSectionResponse(items=items)


@router.get(
    "/services",
    response_model=schemas.LandingServiceSectionResponse,
)
async def services():
    rows = await models.list_services()
    return schemas.LandingServiceSectionResponse(
        items=[schemas.LandingServiceCard(**row) for row in rows]
    )
