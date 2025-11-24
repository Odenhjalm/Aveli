from pathlib import Path
from typing import List

from fastapi import APIRouter, HTTPException, Query, Response, status
from fastapi.responses import FileResponse

from .. import models, repositories, schemas
from ..auth import CurrentUser, OptionalCurrentUser
from ..config import settings
from ..utils.profile_media import profile_media_item_from_row

router = APIRouter(prefix="/community", tags=["community"])


def _resolve_media_path(subpath: str) -> Path:
    if not subpath:
        raise HTTPException(status_code=400, detail="Path is required")
    base = Path(settings.media_root).resolve()
    target = (base / subpath.lstrip("/")).resolve()
    if not str(target).startswith(str(base)):
        raise HTTPException(status_code=400, detail="Invalid path")
    if not target.exists():
        raise HTTPException(status_code=404, detail="File not found")
    return target


@router.get("/posts", response_model=schemas.CommunityPostListResponse)
async def community_posts(limit: int = Query(default=50, ge=1, le=200)):
    items = await models.list_community_posts(limit)
    return {"items": items}


@router.post(
    "/posts", response_model=schemas.CommunityPost, status_code=status.HTTP_201_CREATED
)
async def community_create_post(
    payload: schemas.CommunityPostCreate,
    current_user: CurrentUser,
):
    content = payload.content.strip()
    if not content:
        raise HTTPException(status_code=422, detail="Inlägget får inte vara tomt")
    row = await models.create_community_post(
        author_id=current_user["id"],
        content=content,
        media_paths=payload.media_paths or [],
    )
    return row


@router.get("/teachers", response_model=schemas.TeacherDirectoryResponse)
async def community_teachers(limit: int = Query(default=100, ge=1, le=200)):
    items = await models.list_teacher_directory(limit)
    return {"items": items}


@router.get("/teachers/{user_id}", response_model=schemas.TeacherDetailResponse)
async def community_teacher_detail(user_id: str, current: OptionalCurrentUser = None):
    teacher = await models.get_teacher_directory_item(user_id)
    services = await models.list_teacher_services(user_id)
    meditations = await models.list_teacher_meditations(user_id)

    viewer_id = str(current["id"]) if current else None
    is_admin = bool(current.get("is_admin")) if current else False
    can_view_full = viewer_id == user_id or is_admin

    certificate_rows = await models.certificates_of(
        user_id, verified_only=not can_view_full
    )
    if can_view_full:
        certificates = [dict(row) for row in certificate_rows]
    else:
        certificates = [
            {
                "id": row["id"],
                "title": row["title"],
                "status": row["status"],
                "created_at": row["created_at"],
                "updated_at": row["updated_at"],
            }
            for row in certificate_rows
            if row.get("status") == "verified"
        ]

    return {
        "teacher": teacher,
        "services": services,
        "meditations": meditations,
        "certificates": certificates,
    }


@router.get(
    "/teachers/{user_id}/media",
    response_model=schemas.TeacherProfileMediaPublicResponse,
)
async def community_teacher_profile_media(user_id: str):
    rows = await repositories.list_public_teacher_profile_media(user_id)
    items = [profile_media_item_from_row(row) for row in rows]
    return {"items": items}


@router.get("/teachers/{user_id}/services", response_model=List[schemas.ServiceSummary])
async def community_teacher_services(user_id: str):
    return await models.list_teacher_services(user_id)


@router.get(
    "/services/{service_id}",
    response_model=schemas.ServiceDetailResponse,
)
async def community_service_detail(service_id: str):
    service, provider = await models.service_detail(service_id)
    if not service:
        raise HTTPException(status_code=404, detail="Service not found")
    return {"service": service, "provider": provider}


@router.get(
    "/teachers/{user_id}/meditations", response_model=List[schemas.MeditationSummary]
)
async def community_teacher_meditations(user_id: str):
    return await models.list_teacher_meditations(user_id)


@router.get("/teachers/{user_id}/certificates")
async def community_teacher_certificates(user_id: str, current: CurrentUser):
    viewer_id = str(current["id"])
    if user_id != viewer_id and not bool(current.get("is_admin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed to access certificates",
        )
    rows = await models.certificates_of(user_id, verified_only=False)
    return {"items": [dict(row) for row in rows]}


@router.get(
    "/profiles/{user_id}",
    response_model=schemas.ProfileDetailResponse,
)
async def community_profile_detail(user_id: str, current: CurrentUser):
    viewer_id = str(current["id"])
    if user_id != viewer_id and not bool(current.get("is_admin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed to access this profile",
        )
    detail = await models.profile_overview(user_id, viewer_id)
    if not detail:
        raise HTTPException(status_code=404, detail="Profile not found")
    return detail


@router.get(
    "/meditations/public",
    response_model=schemas.MeditationListResponse,
)
async def community_public_meditations(
    limit: int = Query(default=100, ge=1, le=500),
):
    items = await models.list_public_meditations(limit)
    return {"items": items}


@router.get("/meditations/audio")
async def community_meditation_audio(path: str = Query(..., min_length=1)):
    file_path = _resolve_media_path(path)
    return FileResponse(file_path)


@router.post(
    "/follows/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def community_follow(user_id: str, current: CurrentUser):
    follower_id = str(current["id"])
    if user_id == follower_id:
        raise HTTPException(status_code=400, detail="Cannot follow yourself")
    await models.follow_user(follower_id, user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete(
    "/follows/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def community_unfollow(user_id: str, current: CurrentUser):
    await models.unfollow_user(str(current["id"]), user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/certificates/verified-count")
async def community_verified_count(user_id: list[str] = Query(default=[])):
    counts = await models.verified_certificate_counts(user_id)
    return {"counts": counts}


@router.get(
    "/tarot/requests",
    response_model=schemas.TarotRequestListResponse,
)
async def community_tarot_requests(current: CurrentUser):
    items = await models.list_tarot_requests_for_user(current["id"])
    return {"items": items}


@router.post(
    "/tarot/requests",
    response_model=schemas.TarotRequestRecord,
    status_code=status.HTTP_201_CREATED,
)
async def community_create_tarot_request(
    payload: schemas.TarotRequestCreate,
    current: CurrentUser,
):
    question = payload.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="Frågan får inte vara tom")
    row = await models.create_tarot_request(current["id"], question)
    return row


@router.get(
    "/notifications",
    response_model=schemas.NotificationListResponse,
)
async def community_notifications(current: CurrentUser, unread_only: bool = False):
    items = await models.list_notifications_for_user(current["id"], unread_only)
    return {"items": items}


@router.patch(
    "/notifications/{notification_id}",
    response_model=schemas.NotificationRecord,
)
async def community_update_notification(
    notification_id: str,
    payload: schemas.NotificationUpdate,
    current: CurrentUser,
):
    row = await models.mark_notification_read(
        notification_id, current["id"], payload.is_read
    )
    if not row:
        raise HTTPException(status_code=404, detail="Notification not found")
    return row


@router.get("/services/{service_id}/reviews", response_model=schemas.ReviewListResponse)
async def service_reviews(service_id: str):
    items = await models.list_reviews_for_service(service_id)
    return {"items": items}


@router.post(
    "/services/{service_id}/reviews",
    response_model=schemas.ReviewRecord,
    status_code=status.HTTP_201_CREATED,
)
async def service_add_review(
    service_id: str,
    payload: schemas.ReviewCreate,
    current_user: CurrentUser,
):
    rating = int(payload.rating)
    if rating < 1 or rating > 5:
        raise HTTPException(status_code=422, detail="Betyg måste vara mellan 1 och 5")
    row = await models.add_review_for_service(
        service_id=service_id,
        reviewer_id=current_user["id"],
        rating=rating,
        comment=payload.comment.strip() if payload.comment else None,
    )
    return row


@router.get("/messages", response_model=schemas.MessageListResponse)
async def community_messages(
    current: CurrentUser, channel: str = Query(..., min_length=3)
):
    try:
        items = await models.list_channel_messages(channel, str(current["id"]))
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from exc
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)
        ) from exc
    return {"items": items}


@router.post(
    "/messages",
    response_model=schemas.MessageRecord,
    status_code=status.HTTP_201_CREATED,
)
async def community_send_message(
    payload: schemas.MessageCreate,
    current_user: CurrentUser,
):
    content = payload.content.strip()
    if not content:
        raise HTTPException(status_code=422, detail="Meddelandet får inte vara tomt")
    try:
        row = await models.create_channel_message(
            channel=payload.channel,
            sender_id=str(current_user["id"]),
            content=content,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from exc
    except PermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)
        ) from exc
    return row
