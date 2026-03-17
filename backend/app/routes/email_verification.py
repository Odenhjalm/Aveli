from __future__ import annotations

from collections import defaultdict, deque
import logging
import time

from fastapi import APIRouter, Query, status
from fastapi.responses import JSONResponse

from .. import repositories, schemas
from ..auth import OptionalCurrentUser
from ..services.email_verification import (
    InvalidEmailVerificationTokenError,
    send_verification_email,
    verify_email_token_and_mark_user,
)
from ..services import onboarding_service

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
        return JSONResponse(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            content={"error": "rate_limited"},
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


@router.get("/verify-email", response_model=schemas.VerifyEmailResponse)
async def verify_email(
    token: str = Query(..., min_length=1),
    current: OptionalCurrentUser = None,
):
    try:
        result = await verify_email_token_and_mark_user(token)
    except InvalidEmailVerificationTokenError:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "invalid_or_expired_token"},
        )

    current_email = str((current or {}).get("email") or "").strip().lower()
    verified_email = str(result.get("email") or "").strip().lower()
    if current and current_email and current_email == verified_email:
        payload = await onboarding_service.get_onboarding_payload(str(current["id"]))
        return schemas.VerifyEmailResponse(status=result["status"], onboarding=payload)
    return schemas.VerifyEmailResponse(
        status=result["status"],
        redirect_after_login=onboarding_service.RESUME_ONBOARDING_ROUTE,
    )
