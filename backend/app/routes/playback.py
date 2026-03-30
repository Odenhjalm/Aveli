from uuid import UUID

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import RedirectResponse
from pydantic import BaseModel

from ..auth import CurrentUser
from ..db import get_conn
from ..services import courses_service, runtime_media_service, storage_service
from ..services.playback_delivery_service import (
    resolve_runtime_media_playback_url,
    resolve_runtime_media_stream_source,
)

router = APIRouter(tags=["playback"])


class LessonPlaybackResolveRequest(BaseModel):
    lesson_media_id: UUID


class LessonPlaybackResolveResponse(BaseModel):
    playback_url: str


async def _resolve_lesson_media_subject(lesson_media_id: str) -> dict:
    async with get_conn() as db:
        await db.execute(
            """
            select
                lm.id,
                lm.lesson_id,
                l.course_id
            from app.lesson_media as lm
            join app.lessons as l
              on l.id = lm.lesson_id
            where lm.id = %s
            limit 1
            """,
            (lesson_media_id,),
        )
        row = await db.fetchone()
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson media not found",
        )
    return dict(row)


async def _enforce_lesson_media_access(*, user_id: str, lesson_media_id: str) -> None:
    subject = await _resolve_lesson_media_subject(lesson_media_id)
    lesson = await courses_service.fetch_lesson(str(subject["lesson_id"]))
    if not lesson:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson not found",
        )
    if await courses_service.can_user_read_lesson(user_id, lesson):
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Forbidden",
    )


@router.post("/api/playback/lesson", response_model=LessonPlaybackResolveResponse)
async def resolve_lesson_playback(
    payload: LessonPlaybackResolveRequest,
    current: CurrentUser,
):
    lesson_media_id = str(payload.lesson_media_id)
    await _enforce_lesson_media_access(
        user_id=str(current["id"]),
        lesson_media_id=lesson_media_id,
    )
    async with get_conn() as db:
        runtime_row = await runtime_media_service.get_active_runtime_media_for_lesson_media(
            db=db,
            lesson_media_id=lesson_media_id,
        )
    if runtime_row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Active runtime media not found",
        )
    playback_url = await resolve_runtime_media_playback_url(runtime_row)
    return LessonPlaybackResolveResponse(playback_url=playback_url)


@router.get("/api/media/stream/{lesson_media_id}")
async def stream_runtime_media(
    lesson_media_id: UUID,
    current: CurrentUser,
):
    normalized_lesson_media_id = str(lesson_media_id)
    await _enforce_lesson_media_access(
        user_id=str(current["id"]),
        lesson_media_id=normalized_lesson_media_id,
    )
    async with get_conn() as db:
        runtime_row = await runtime_media_service.get_active_runtime_media(
            db=db,
            lesson_media_id=normalized_lesson_media_id,
        )
    if runtime_row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Active runtime media not found",
        )

    stream_source = await resolve_runtime_media_stream_source(runtime_row)
    storage_client = storage_service.get_storage_service(stream_source["storage_bucket"])
    try:
        signed = await storage_client.get_presigned_url(
            stream_source["storage_path"],
            ttl=900,
            download=False,
        )
    except storage_service.StorageServiceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Storage signing unavailable",
        ) from exc
    return RedirectResponse(url=signed.url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
