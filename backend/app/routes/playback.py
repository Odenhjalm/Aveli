from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from ..auth import CurrentUser
from ..db import get_conn, get_test_session_id
from ..routes import media as media_routes
from ..services import entitlement_service, runtime_media_service
from ..services.entitlement_service import fetch_one
from ..services.playback_delivery_service import (
    resolve_runtime_media_playback_url,
    resolve_runtime_media_stream_source,
)

router = APIRouter(tags=["playback"])


class LessonPlaybackResolveRequest(BaseModel):
    lesson_media_id: UUID


class LessonPlaybackResolveResponse(BaseModel):
    playback_url: str


async def _resolve_course_id_for_lesson_media(
    db,
    *,
    lesson_media_id: str,
    current_session_id: str | None,
) -> str:
    lesson_row = await fetch_one(
        db,
        """
        SELECT
            lm.id AS lesson_media_id,
            l.id AS lesson_id,
            l.course_id AS course_id
        FROM app.lesson_media lm
        JOIN app.lessons l ON l.id = lm.lesson_id
        WHERE lm.id = $1
          AND app.is_test_row_visible(lm.is_test, lm.test_session_id, $2)
          AND app.is_test_row_visible(l.is_test, l.test_session_id, $2)
        LIMIT 1
        """,
        lesson_media_id,
        current_session_id,
    )
    if lesson_row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson media not found",
        )

    course_id = lesson_row["course_id"]
    if not course_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found",
        )
    return str(course_id)


async def _enforce_course_entitlement(db, *, user_id: str, course_id: str) -> None:
    has_access = await entitlement_service.has_course_access(
        db=db,
        user_id=user_id,
        course_id=course_id,
    )
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden",
        )


async def _get_active_runtime_media_by_id(
    db,
    *,
    runtime_media_id: str,
    current_session_id: str | None,
) -> tuple[dict, str]:
    runtime_row = await fetch_one(
        db,
        """
        SELECT
            rm.id,
            rm.lesson_media_id,
            rm.lesson_id,
            rm.course_id,
            rm.media_asset_id,
            rm.media_object_id,
            rm.reference_type,
            rm.auth_scope,
            rm.fallback_policy,
            rm.active,
            l.course_id AS resolved_course_id
        FROM app.runtime_media rm
        JOIN app.lesson_media lm ON lm.id = rm.lesson_media_id
        JOIN app.lessons l ON l.id = lm.lesson_id
        WHERE rm.id = $1
          AND rm.active = true
          AND app.is_test_row_visible(lm.is_test, lm.test_session_id, $2)
          AND app.is_test_row_visible(l.is_test, l.test_session_id, $2)
        LIMIT 1
        """,
        runtime_media_id,
        current_session_id,
    )
    if runtime_row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Active runtime media not found",
        )

    course_id = runtime_row["resolved_course_id"]
    if not course_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found",
        )

    return dict(runtime_row), str(course_id)


@router.post("/api/playback/lesson", response_model=LessonPlaybackResolveResponse)
async def resolve_lesson_playback(
    payload: LessonPlaybackResolveRequest, current: CurrentUser
):
    user_id = str(current["id"])
    lesson_media_id = str(payload.lesson_media_id)
    current_session_id = get_test_session_id()

    async with get_conn() as db:
        course_id = await _resolve_course_id_for_lesson_media(
            db,
            lesson_media_id=lesson_media_id,
            current_session_id=current_session_id,
        )
        await _enforce_course_entitlement(
            db,
            user_id=user_id,
            course_id=course_id,
        )

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


@router.get("/api/media/stream/{runtime_media_id}")
async def stream_runtime_media(
    runtime_media_id: UUID,
    request: Request,
    current: CurrentUser,
) -> StreamingResponse:
    user_id = str(current["id"])
    current_session_id = get_test_session_id()

    async with get_conn() as db:
        runtime_row, course_id = await _get_active_runtime_media_by_id(
            db,
            runtime_media_id=str(runtime_media_id),
            current_session_id=current_session_id,
        )
        await _enforce_course_entitlement(
            db,
            user_id=user_id,
            course_id=course_id,
        )

    stream_source = await resolve_runtime_media_stream_source(runtime_row)
    return await media_routes._build_streaming_response(
        stream_source,
        request,
        lesson_media_id=str(runtime_row["lesson_media_id"]),
        mode="playback",
    )
