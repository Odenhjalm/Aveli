from uuid import UUID

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict

from ..auth import CurrentUser
from ..services import lesson_playback_service

router = APIRouter(tags=["playback"])


class LessonPlaybackResolveRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_media_id: UUID


class LessonPlaybackResolveResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    playback_url: str


@router.post("/api/playback/lesson", response_model=LessonPlaybackResolveResponse)
async def resolve_lesson_playback(
    payload: LessonPlaybackResolveRequest,
    current: CurrentUser,
):
    playback = await lesson_playback_service.resolve_lesson_media_playback(
        lesson_media_id=str(payload.lesson_media_id),
        user_id=str(current["id"]),
    )
    playback_url = str(playback.get("playback_url") or "").strip()
    if not playback_url:
        raise HTTPException(status_code=503, detail="Playback is unavailable")
    return LessonPlaybackResolveResponse(playback_url=playback_url)
