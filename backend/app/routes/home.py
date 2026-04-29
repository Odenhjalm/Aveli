from fastapi import APIRouter, Query

from .. import schemas
from ..auth import AppEntryUser
from ..services import home_audio_service
from ..services import studio_home_player_text_catalog

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
    text_bundle = studio_home_player_text_catalog.build_home_audio_runtime_text_bundle()
    return schemas.HomeAudioFeedResponse(
        items=[schemas.HomeAudioItem(**item) for item in items],
        homeplayer_logo=schemas.HomePlayerLogoSet(
            **home_audio_service.build_homeplayer_logo_payload()
        ),
        text_bundle={
            text_id: schemas.HomePlayerCatalogTextValue(**entry)
            for text_id, entry in text_bundle.items()
        },
    )
