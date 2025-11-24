from fastapi import APIRouter

from .. import models
from ..utils import media_signer

router = APIRouter(prefix="/landing", tags=["landing"])


@router.get("/intro-courses")
async def intro_courses():
    rows = await models.list_intro_courses()
    for row in rows:
        media_signer.attach_cover_links(row)
    return {"items": rows}


@router.get("/popular-courses")
async def popular_courses():
    rows = await models.list_popular_courses()
    for row in rows:
        media_signer.attach_cover_links(row)
    return {"items": rows}


@router.get("/teachers")
async def teachers():
    rows = await models.list_teachers()
    return {"items": rows}


@router.get("/services")
async def services():
    rows = await models.list_services()
    return {"items": rows}
