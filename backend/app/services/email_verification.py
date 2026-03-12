from __future__ import annotations

from urllib.parse import urlencode

from .. import repositories
from ..config import settings
from .email_service import send_email
from .email_templates import render_template
from .email_tokens import EmailTokenError, create_email_token, verify_email_token

_VERIFY_TOKEN_EXPIRY_MINUTES = 15
_VERIFY_EMAIL_SUBJECT = "Verify your Aveli account"
_DEFAULT_FRONTEND_BASE_URL = "https://app.aveli.app"


class InvalidEmailVerificationTokenError(ValueError):
    pass


async def send_verification_email(email: str) -> None:
    normalized_email = email.strip().lower()
    token = create_email_token(
        normalized_email,
        token_type="verify",
        expires_minutes=_VERIFY_TOKEN_EXPIRY_MINUTES,
    )
    verify_url = _build_verify_url(token)
    html_body = render_template("verify_email.html", verify_url=verify_url)
    text_body = f"Verify your Aveli account: {verify_url}"

    await send_email(
        to_email=normalized_email,
        subject=_VERIFY_EMAIL_SUBJECT,
        text_body=text_body,
        html_body=html_body,
    )


async def verify_email_token_and_mark_user(token: str) -> dict[str, str]:
    try:
        email = verify_email_token(token, expected_type="verify")
    except EmailTokenError as exc:
        raise InvalidEmailVerificationTokenError("invalid_or_expired_token") from exc

    user = await repositories.get_user_by_email(email)
    if not user:
        raise InvalidEmailVerificationTokenError("invalid_or_expired_token")

    updated = await repositories.mark_user_email_verified(email)
    if not updated:
        raise InvalidEmailVerificationTokenError("invalid_or_expired_token")

    return {"status": "verified", "email": email}


def _build_verify_url(token: str) -> str:
    base_url = (settings.frontend_base_url or _DEFAULT_FRONTEND_BASE_URL).rstrip("/")
    return f"{base_url}/verify?{urlencode({'token': token})}"
