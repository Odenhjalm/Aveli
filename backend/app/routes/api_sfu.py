from fastapi import APIRouter, HTTPException, Request, status

from .. import repositories, schemas
from ..auth import CurrentUser
from ..config import settings
from ..services.livekit_webhook_handler import (
    LiveKitWebhookError,
    capture_livekit_rejection,
    handle_livekit_webhook,
)
from ..services.livekit_tokens import LiveKitTokenConfigError, build_token

router = APIRouter(prefix="/sfu", tags=["sfu"])


@router.post("/token", response_model=schemas.LiveKitTokenResponse)
async def create_livekit_token(
    payload: schemas.LiveKitTokenRequest, current: CurrentUser
):
    if (
        not settings.livekit_api_key
        or not settings.livekit_api_secret
        or not settings.livekit_ws_url
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LiveKit configuration missing",
        )

    seminar = await repositories.get_seminar(str(payload.seminar_id))
    if not seminar:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Seminar not found"
        )

    role = await repositories.get_user_seminar_role(
        str(current["id"]), str(payload.seminar_id)
    )
    if role is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="No access to seminar"
        )

    session = None
    if payload.session_id:
        session = await repositories.get_seminar_session(str(payload.session_id))
        if not session or str(session["seminar_id"]) != str(seminar["id"]):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Seminar session not found",
            )
    if session is None:
        session = await repositories.get_latest_session(str(seminar["id"]))
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No seminar session available"
        )
    if session["status"] == "ended":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Session already ended"
        )

    room_name = (
        session.get("livekit_room")
        or seminar.get("livekit_room")
        or f"seminar-{seminar['id']}"
    )
    identity = f"{current['id']}"
    display_name = current.get("display_name") or current.get("email")
    avatar_url = current.get("photo_url")

    can_create_room = role == "host" and session.get("status") in {"scheduled", "live"}
    is_host = role == "host"
    can_publish = True if is_host else session.get("status") == "live"

    try:
        token = build_token(
            seminar_id=seminar["id"],
            session_id=session["id"],
            user_id=current["id"],
            identity=identity,
            display_name=display_name,
            avatar_url=avatar_url,
            role="host" if role == "host" else "participant",
            room_name=room_name,
            can_create_room=can_create_room,
            can_publish=can_publish,
            can_publish_data=can_publish,
            can_subscribe=True,
            extra_metadata={
                "session_status": session.get("status"),
                "host_id": str(seminar["host_id"]),
            },
        )
    except LiveKitTokenConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)
        ) from exc

    return schemas.LiveKitTokenResponse(ws_url=settings.livekit_ws_url, token=token)


@router.post("/webhooks/livekit")
async def livekit_webhook(request: Request):
    signature = request.headers.get("X-Livekit-Signature")
    try:
        payload = await request.json()
    except Exception as exc:
        capture_livekit_rejection("invalid_json")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON"
        ) from exc
    try:
        return await handle_livekit_webhook(payload, signature)
    except LiveKitWebhookError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
