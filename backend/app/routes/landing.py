from fastapi import APIRouter

from .. import models
from ..services import courses_service

router = APIRouter(prefix="/landing", tags=["landing"])


@router.get("/intro-courses")
async def intro_courses():
    rows = await models.list_intro_courses()
    await courses_service.attach_course_cover_read_contract(rows)
    return {"items": rows}


@router.get("/popular-courses")
async def popular_courses():
    rows = await models.list_popular_courses()
    await courses_service.warn_course_cover_contracts(rows)
    return {"items": rows}


@router.get("/teachers")
async def teachers():
    rows = await models.list_teachers()
    return {"items": rows}


@router.get("/services")
async def services():
    rows = await models.list_services()
    return {"items": rows}
