from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, Field

from .. import repositories
from ..services.email_service import EmailDeliveryError
from ..services.email_tokens import (
    EmailVerificationTokenError,
    verify_verification_token,
)
from ..services.email_verification import mark_email_verified, send_verification_email

router = APIRouter(prefix="/auth", tags=["auth"])


class SendVerificationRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)


@router.post("/send-verification", status_code=status.HTTP_202_ACCEPTED)
async def send_verification(payload: SendVerificationRequest):
    user = await repositories.get_user_by_email(payload.email)
    if user:
        try:
            await send_verification_email(user["email"])
        except EmailDeliveryError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Failed to send verification email",
            ) from exc

    return {"status": "ok"}


@router.get("/verify-email")
async def verify_email(token: str = Query(..., min_length=1)):
    try:
        email = verify_verification_token(token)
    except EmailVerificationTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification token",
        ) from exc

    user = await repositories.get_user_by_email(email)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    updated = await mark_email_verified(email)
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return {"status": "verified"}
