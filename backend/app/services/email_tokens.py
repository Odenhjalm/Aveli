from __future__ import annotations

from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt

from ..config import settings

_SUPPORTED_TOKEN_TYPES = frozenset({"invite", "reset", "verify"})


class EmailTokenError(ValueError):
    pass


def create_email_token(email: str, token_type: str, expires_minutes: int) -> str:
    normalized_type = _normalize_token_type(token_type)
    if expires_minutes <= 0:
        raise EmailTokenError("expires_minutes must be positive")

    normalized_email = _normalize_email(email)
    payload = {
        "sub": normalized_email,
        "type": normalized_type,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=expires_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def verify_email_token(token: str, expected_type: str) -> str:
    normalized_type = _normalize_token_type(expected_type)
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
    except JWTError as exc:
        raise EmailTokenError("Invalid or expired email token") from exc

    if payload.get("type") != normalized_type:
        raise EmailTokenError("Invalid or expired email token")

    email = payload.get("sub")
    if not isinstance(email, str) or not email.strip():
        raise EmailTokenError("Invalid or expired email token")

    return _normalize_email(email)


def _normalize_token_type(token_type: str) -> str:
    normalized = token_type.strip().lower()
    if normalized not in _SUPPORTED_TOKEN_TYPES:
        raise EmailTokenError("Unsupported email token type")
    return normalized


def _normalize_email(email: str) -> str:
    normalized = email.strip().lower()
    if not normalized:
        raise EmailTokenError("Email is required")
    return normalized
