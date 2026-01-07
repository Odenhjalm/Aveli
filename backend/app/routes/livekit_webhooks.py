from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Request, status

from ..services.livekit_webhook_handler import (
    LiveKitWebhookError,
    capture_livekit_rejection,
    handle_livekit_webhook,
)

router = APIRouter(prefix="/webhooks", tags=["livekit-webhooks"])
logger = logging.getLogger(__name__)


@router.post("/livekit", status_code=status.HTTP_200_OK)
async def livekit_webhook(request: Request):
    signature = request.headers.get("X-Livekit-Signature")
    try:
        payload = await request.json()
    except Exception as exc:
        capture_livekit_rejection("invalid_json")
        logger.warning("LiveKit webhook rejected: invalid JSON (%s)", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON"
        ) from exc

    try:
        return await handle_livekit_webhook(payload, signature)
    except LiveKitWebhookError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
