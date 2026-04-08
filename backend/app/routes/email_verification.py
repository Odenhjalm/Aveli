from __future__ import annotations

from collections import defaultdict, deque
import logging
import time

from fastapi import APIRouter, HTTPException, Query, status

from .. import repositories, schemas
from ..services.email_verification import (
    InvalidEmailVerificationTokenError,
    InvalidInviteTokenError,
    send_verification_email,
    validate_invite_token,
    verify_email_token_and_mark_user,
)

router = APIRouter(prefix="/auth", tags=["auth"])

logger = logging.getLogger(__name__)

_RATE_LIMIT_WINDOW_SECONDS = 60 * 60
_RATE_LIMIT_MAX_ATTEMPTS = 5
_send_verification_attempts: defaultdict[str, deque[float]] = defaultdict(deque)


def _consume_send_verification_attempt(email: str) -> bool:
    bucket = _send_verification_attempts[email]
    now = time.monotonic()
    while bucket and now - bucket[0] > _RATE_LIMIT_WINDOW_SECONDS:
        bucket.popleft()
    if len(bucket) >= _RATE_LIMIT_MAX_ATTEMPTS:
        return False
    bucket.append(now)
    return True


@router.post("/send-verification")
async def send_verification(payload: schemas.AuthForgotPasswordRequest):
    normalized_email = payload.email.strip().lower()
    if not _consume_send_verification_attempt(normalized_email):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="rate_limited",
        )

    user = await repositories.get_user_by_email(normalized_email)
    if user:
        try:
            await send_verification_email(user["email"])
        except Exception:
            logger.exception(
                "Failed to send verification email email=%s",
                normalized_email,
            )

    return {"status": "ok"}


@router.get("/verify-email")
async def verify_email(token: str = Query(..., min_length=1)):
    try:
        result = await verify_email_token_and_mark_user(token)
    except InvalidEmailVerificationTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="invalid_or_expired_token",
        ) from exc

    return {"status": result["status"]}


@router.get("/validate-invite")
async def validate_invite(token: str = Query(..., min_length=1)):
    try:
        email = validate_invite_token(token)
    except InvalidInviteTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="invalid_or_expired_token",
        ) from exc

    return {"status": "valid", "email": email}
