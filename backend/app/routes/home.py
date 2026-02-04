from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Request

from .. import repositories, schemas
from ..auth import CurrentUser
from ..db import get_conn
from ..services import courses_service
from .media import _build_streaming_response

router = APIRouter(prefix="/home", tags=["home"])


@router.get("/audio", response_model=schemas.HomeAudioFeedResponse)
async def home_audio_feed(
    current: CurrentUser,
    limit: int = Query(default=12, ge=1, le=50),
):
    items = await courses_service.list_home_audio_media(
        str(current["id"]),
        limit=limit,
    )
    return schemas.HomeAudioFeedResponse(
        items=[schemas.HomeAudioItem(**item) for item in items],
    )


@router.get("/uploads/{media_id}")
async def home_uploaded_media(
    media_id: UUID,
    request: Request,
    current: CurrentUser,
):
    upload = await repositories.get_active_home_upload_by_media_id(str(media_id))
    if not upload:
        raise HTTPException(status_code=404, detail="Media not found")

    user_id = str(current["id"])
    teacher_id = str(upload["teacher_id"])
    if user_id != teacher_id:
        async with get_conn() as cur:
            await cur.execute(
                """
                SELECT 1
                FROM app.enrollments e
                JOIN app.courses c ON c.id = e.course_id
                WHERE e.user_id = %s
                  AND e.status = 'active'
                  AND c.is_published = true
                  AND c.created_by = %s
                LIMIT 1
                """,
                (user_id, teacher_id),
            )
            row = await cur.fetchone()
        if not row:
            raise HTTPException(status_code=403, detail="Access denied")

    stream_row = {
        "id": upload.get("media_id"),
        "storage_path": upload.get("storage_path"),
        "storage_bucket": upload.get("storage_bucket"),
        "content_type": upload.get("content_type"),
        "byte_size": upload.get("byte_size"),
        "original_name": upload.get("original_name"),
    }
    return await _build_streaming_response(stream_row, request)
