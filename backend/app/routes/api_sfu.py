from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status


router = APIRouter(prefix="/sfu", tags=["sfu"])


def _raise_v2_feature_disabled() -> None:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Seminar live sessions have no Baseline V2 authority",
    )


@router.post("/token")
async def create_livekit_token(request: Request) -> None:
    del request
    _raise_v2_feature_disabled()


@router.post("/webhooks/livekit")
async def livekit_webhook(request: Request) -> None:
    del request
    _raise_v2_feature_disabled()
