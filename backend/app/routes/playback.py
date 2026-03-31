from uuid import UUID

from fastapi import APIRouter
from pydantic import BaseModel

from ..auth import CurrentUser
from ..services import lesson_playback_service

router = APIRouter(tags=["playback"])


class LessonPlaybackResolveRequest(BaseModel):
    lesson_media_id: UUID


class LessonPlaybackResolveResponse(BaseModel):
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
    return LessonPlaybackResolveResponse(playback_url=str(playback["playback_url"]))
