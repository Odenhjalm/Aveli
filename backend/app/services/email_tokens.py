from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

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
    claims = verify_email_token_claims(token, expected_type)
    return str(claims["email"])


def verify_email_token_claims(token: str, expected_type: str) -> dict[str, Any]:
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

    expires_at = _normalize_expires_at(payload.get("exp"))

    return {
        "email": _normalize_email(email),
        "expires_at": expires_at,
    }


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


def _normalize_expires_at(value: object) -> datetime:
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc)
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError as exc:
            raise EmailTokenError("Invalid or expired email token") from exc
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    raise EmailTokenError("Invalid or expired email token")
