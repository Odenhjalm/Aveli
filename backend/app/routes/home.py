from fastapi import APIRouter, Query

from .. import schemas
from ..auth import AppEntryUser
from ..services import home_audio_service

router = APIRouter(prefix="/home", tags=["home"])


@router.get(
    "/audio",
    response_model=schemas.HomeAudioFeedResponse,
)
async def home_audio_feed(
    current: AppEntryUser,
    limit: int = Query(default=12, ge=1, le=50),
):
    items = await home_audio_service.list_home_audio_media(
        str(current["id"]),
        limit=limit,
    )
    return schemas.HomeAudioFeedResponse(
        items=[schemas.HomeAudioItem(**item) for item in items],
    )
