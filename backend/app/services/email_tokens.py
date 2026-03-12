from __future__ import annotations

from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt

from ..config import settings

_TOKEN_TYPE = "verify"
_TOKEN_TTL = timedelta(minutes=15)


class EmailVerificationTokenError(ValueError):
    pass


def create_verification_token(email: str) -> str:
    expires_at = datetime.now(timezone.utc) + _TOKEN_TTL
    payload = {
        "sub": email.strip().lower(),
        "type": _TOKEN_TYPE,
        "exp": expires_at,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def verify_verification_token(token: str) -> str:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
    except JWTError as exc:
        raise EmailVerificationTokenError("Invalid verification token") from exc

    if payload.get("type") != _TOKEN_TYPE:
        raise EmailVerificationTokenError("Invalid verification token")
    if "exp" not in payload:
        raise EmailVerificationTokenError("Invalid verification token")

    email = payload.get("sub")
    if not isinstance(email, str) or not email.strip():
        raise EmailVerificationTokenError("Invalid verification token")

    return email.strip().lower()
